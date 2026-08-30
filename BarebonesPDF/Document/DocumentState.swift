import AppKit
import Combine
import PDFKit

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

final class DocumentState: NSObject, ObservableObject {
    @Published private(set) var pdfDocument: PDFDocument
    @Published var selectedPageIndexes = IndexSet()
    @Published var currentPageIndex = 0
    @Published private(set) var pageCount = 0
    @Published private(set) var zoomPercent = 100
    @Published var sidebarVisible = AppPreferences.sidebarVisible {
        didSet { AppPreferences.sidebarVisible = sidebarVisible }
    }
    @Published var inspectorVisible = AppPreferences.inspectorVisible {
        didSet { AppPreferences.inspectorVisible = inspectorVisible }
    }
    @Published var annotationBarVisible = false
    @Published var searchVisible = false
    @Published var metadataVisible = false
    @Published var viewerMode = AppPreferences.viewerMode {
        didSet {
            AppPreferences.viewerMode = viewerMode
            pdfView?.displayMode = viewerMode.pdfDisplayMode
        }
    }
    @Published var zoomBehavior = AppPreferences.zoomBehavior {
        didSet { AppPreferences.zoomBehavior = zoomBehavior }
    }
    @Published var activeTool: AnnotationTool = .select
    @Published var selectedAnnotation: PDFAnnotation?
    @Published var annotationColor = NSColor.systemYellow
    @Published var annotationOpacity: Double = 0.45
    @Published var annotationLineWidth: Double = 2
    @Published var annotationFont = NSFont.systemFont(ofSize: 13)
    @Published var pendingSignatureImage: NSImage?
    @Published var pendingSignatureName = "Signature"
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [PDFSelection] = []
    @Published private(set) var searchResultIndex = -1
    @Published private(set) var isSearching = false
    @Published private(set) var isBusy = false
    @Published private(set) var busyMessage = ""
    @Published private(set) var isEdited = false
    @Published var presentedError: PresentedError?
    @Published var needsPassword = false
    @Published var fileURL: URL?

    weak var pdfView: InteractivePDFView?
    weak var undoManager: UndoManager?
    var onDocumentChanged: (() -> Void)?
    var onDocumentReplaced: ((PDFDocument) -> Void)?

    init(document: PDFDocument, fileURL: URL?) {
        pdfDocument = document
        self.fileURL = fileURL
        super.init()
        finishReplacingDocument()
    }

    var hasDocument: Bool { pageCount > 0 }
    var canNavigateBackward: Bool { currentPageIndex > 0 }
    var canNavigateForward: Bool { currentPageIndex + 1 < pageCount }
    var pageDisplayText: String { pageCount == 0 ? "—" : "\(currentPageIndex + 1) of \(pageCount)" }
    var selectedPageSummary: String {
        switch selectedPageIndexes.count {
        case 0: return "No pages selected"
        case 1: return "Page \((selectedPageIndexes.first ?? 0) + 1)"
        default: return "\(selectedPageIndexes.count) pages"
        }
    }

    func attach(pdfView: InteractivePDFView) {
        self.pdfView = pdfView
        pdfView.document = pdfDocument
        pdfView.displayMode = viewerMode.pdfDisplayMode
        pdfView.documentState = self
        applyPreferredZoom()
    }

    func synchronize(document: PDFDocument) {
        guard pdfDocument !== document else { return }
        pdfDocument = document
        isEdited = false
        finishReplacingDocument()
        pdfView?.document = document
        applyPreferredZoom()
    }

    func markSaved() {
        isEdited = false
    }

    func updateFromPDFView(page: PDFPage?, scaleFactor: CGFloat) {
        if let page {
            let index = pdfDocument.index(for: page)
            if index != NSNotFound, index != currentPageIndex {
                currentPageIndex = index
                if selectedPageIndexes.count <= 1 { selectedPageIndexes = IndexSet(integer: index) }
            }
        }
        let value = max(1, Int((scaleFactor * 100).rounded()))
        if value != zoomPercent { zoomPercent = value }
    }

    func goToPage(_ oneBasedPage: Int) {
        guard pageCount > 0 else { return }
        let index = min(max(oneBasedPage - 1, 0), pageCount - 1)
        guard let page = pdfDocument.page(at: index) else { return }
        pdfView?.go(to: page)
        currentPageIndex = index
    }

    func previousPage() { goToPage(currentPageIndex) }
    func nextPage() { goToPage(currentPageIndex + 2) }

    func zoomIn() {
        guard let pdfView else { return }
        zoomBehavior = .manual
        pdfView.zoomIn(nil)
        updateFromPDFView(page: pdfView.currentPage, scaleFactor: pdfView.scaleFactor)
    }

    func zoomOut() {
        guard let pdfView else { return }
        zoomBehavior = .manual
        pdfView.zoomOut(nil)
        updateFromPDFView(page: pdfView.currentPage, scaleFactor: pdfView.scaleFactor)
    }

    func actualSize() {
        zoomBehavior = .manual
        pdfView?.autoScales = false
        pdfView?.scaleFactor = 1
    }

    func fitPage() {
        guard let pdfView else { return }
        zoomBehavior = .fitPage
        pdfView.autoScales = true
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
    }

    func fitWidth() {
        guard let pdfView, let page = pdfView.currentPage ?? pdfDocument.page(at: 0) else { return }
        zoomBehavior = .fitWidth
        pdfView.autoScales = false
        let pageWidth = max(1, page.bounds(for: pdfView.displayBox).width)
        let availableWidth = max(1, pdfView.bounds.width - 36)
        let target = min(pdfView.maxScaleFactor, max(pdfView.minScaleFactor, availableWidth / pageWidth))
        if abs(pdfView.scaleFactor - target) > 0.001 { pdfView.scaleFactor = target }
    }

    func applyPreferredZoom() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch self.zoomBehavior {
            case .manual: break
            case .fitPage: self.fitPage()
            case .fitWidth: self.fitWidth()
            }
        }
    }

    func rotateSelectedPages(degrees: Int) {
        let indexes = effectivePageSelection
        mutateDocument(actionName: degrees < 0 ? "Rotate Pages Left" : "Rotate Pages Right") {
            try PageEditingEngine.rotate(document: $0, indexes: indexes, degrees: degrees)
        }
    }

    func duplicateSelectedPages() {
        let indexes = effectivePageSelection
        mutateDocument(actionName: "Duplicate Pages") { document in
            selectedPageIndexes = try PageEditingEngine.duplicate(document: document, indexes: indexes)
        }
    }

    func deleteSelectedPages() {
        let indexes = selectedPageIndexes
        guard !indexes.isEmpty else {
            present(error: PageEditingError.noPagesSelected)
            return
        }
        mutateDocument(actionName: "Delete Pages") { document in
            try PageEditingEngine.delete(document: document, indexes: indexes)
            selectedPageIndexes = document.pageCount == 0 ? [] : IndexSet(integer: min(indexes.first ?? 0, document.pageCount - 1))
        }
    }

    func insertBlankPage() {
        let insertionIndex = min((selectedPageIndexes.last ?? (pageCount - 1)) + 1, pageCount)
        let size = selectedPageIndexes.first
            .flatMap { pdfDocument.page(at: $0)?.bounds(for: .mediaBox).size }
            ?? CGSize(width: 612, height: 792)
        mutateDocument(actionName: "Insert Blank Page") { document in
            selectedPageIndexes = try PageEditingEngine.insertBlank(document: document, at: insertionIndex, size: size)
        }
    }

    func insertPagesFromPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a PDF whose pages will be inserted after the current selection."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard let incoming = PDFDocument(url: url), !incoming.isLocked else {
                    self.present(title: "Could Not Insert Pages", message: "The selected PDF could not be read or is password protected.")
                    return
                }
                do {
                    let pages = try (0..<incoming.pageCount).map { index -> PDFPage in
                        guard let page = incoming.page(at: index) else { throw ExportError.pageUnavailable }
                        return try PageEditingEngine.copy(page: page)
                    }
                    let insertion = min((self.selectedPageIndexes.last ?? (self.pageCount - 1)) + 1, self.pageCount)
                    self.mutateDocument(actionName: "Insert Pages") { document in
                        self.selectedPageIndexes = try PageEditingEngine.insert(document: document, pages: pages, at: insertion)
                    }
                } catch {
                    self.present(error: error)
                }
            }
        }
    }

    func moveSelectedPages(to destination: Int) {
        let indexes = selectedPageIndexes
        mutateDocument(actionName: "Reorder Pages") { document in
            selectedPageIndexes = try PageEditingEngine.move(document: document, indexes: indexes, to: destination)
        }
    }

    func extractSelectedPages() {
        guard !selectedPageIndexes.isEmpty else {
            present(error: ExportError.noPagesSelected)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Extracted Pages.pdf"
        panel.message = "Save the selected pages as a separate PDF."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                self.performBusy("Exporting selected pages…") {
                    try ExportService.writeSelectedPages(from: self.pdfDocument, indexes: self.selectedPageIndexes, to: url)
                }
            }
        }
    }

    func exportSelectedPageImage(format: PageImageFormat) {
        let index = selectedPageIndexes.first ?? (pageCount > 0 ? currentPageIndex : -1)
        guard index >= 0, let page = pdfDocument.page(at: index) else {
            present(error: ExportError.noPagesSelected)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "Page \(index + 1).\(format.fileExtension)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                self.performBusy("Rendering page image…") {
                    let data = try ExportService.imageData(for: page, format: format)
                    try SafeSaveService.write(data: data, to: url)
                }
            }
        }
    }

    func printDocument() {
        guard let operation = pdfDocument.printOperation(
            for: NSPrintInfo.shared,
            scalingMode: .pageScaleToFit,
            autoRotate: true
        ) else { return }
        operation.run()
    }

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchResultIndex = -1
            pdfView?.highlightedSelections = nil
            return
        }
        isSearching = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let results = self.pdfDocument.findString(query, withOptions: [.caseInsensitive])
            self.searchResults = results
            self.searchResultIndex = results.isEmpty ? -1 : 0
            self.isSearching = false
            self.showCurrentSearchResult()
        }
    }

    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        searchResultIndex = (searchResultIndex + 1) % searchResults.count
        showCurrentSearchResult()
    }

    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        searchResultIndex = (searchResultIndex - 1 + searchResults.count) % searchResults.count
        showCurrentSearchResult()
    }

    func closeSearch() {
        searchVisible = false
        pdfView?.highlightedSelections = nil
    }

    func unlock(with password: String) {
        if pdfDocument.unlock(withPassword: password) {
            needsPassword = false
            finishReplacingDocument()
            pdfView?.document = pdfDocument
        } else {
            present(title: "Password Not Accepted", message: "The password did not unlock this PDF.")
        }
    }

    func select(annotation: PDFAnnotation?) {
        selectedAnnotation = annotation
        guard let annotation else { return }
        annotationColor = annotation.color
        annotationOpacity = Double(annotation.color.alphaComponent)
        annotationLineWidth = Double(annotation.border?.lineWidth ?? 1)
        if let font = annotation.font { annotationFont = font }
    }

    func deleteSelectedAnnotation() {
        guard let annotation = selectedAnnotation, let page = annotation.page else { return }
        mutateDocument(actionName: "Delete Annotation") { _ in
            page.removeAnnotation(annotation)
            selectedAnnotation = nil
            pdfView?.updateSelectionOverlay()
        }
    }

    func deleteActiveContext() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.deleteBackward(nil)
            return
        }
        if selectedAnnotation != nil {
            deleteSelectedAnnotation()
        } else if !selectedPageIndexes.isEmpty {
            deleteSelectedPages()
        }
    }

    func updateSelectedAnnotation(
        actionName: String = "Change Annotation",
        mutation: (PDFAnnotation) -> Void
    ) {
        guard let annotation = selectedAnnotation else { return }
        mutateDocument(actionName: actionName) { _ in
            mutation(annotation)
            pdfView?.needsDisplay = true
            pdfView?.updateSelectionOverlay()
        }
    }

    func applyAnnotationAppearance() {
        updateSelectedAnnotation(actionName: "Change Annotation Appearance") { annotation in
            let alphaColor = annotationColor.withAlphaComponent(annotationOpacity)
            annotation.color = alphaColor
            let border = annotation.border ?? PDFBorder()
            border.lineWidth = annotationLineWidth
            annotation.border = border
            if annotation.type == PDFAnnotationSubtype.freeText.rawValue {
                annotation.font = annotationFont
                annotation.fontColor = annotationColor.withAlphaComponent(1)
            }
        }
    }

    func applyMetadata(_ metadata: EditableMetadata) {
        mutateDocument(actionName: "Edit Document Information") { document in
            MetadataService.apply(metadata, to: document)
        }
    }

    func registerAnnotationChange(actionName: String, beforeData: Data?) {
        guard let beforeData else {
            changed()
            return
        }
        registerUndo(snapshot: beforeData, actionName: actionName)
        changed()
    }

    func snapshot() -> Data? { pdfDocument.dataRepresentation() }

    func present(error: Error) {
        present(title: "BarebonesPDF Could Not Complete That Action", message: error.localizedDescription)
    }

    func present(title: String, message: String) {
        presentedError = PresentedError(title: title, message: message)
    }

    private var effectivePageSelection: IndexSet {
        if !selectedPageIndexes.isEmpty { return selectedPageIndexes }
        return pageCount > 0 ? IndexSet(integer: currentPageIndex) : []
    }

    private func mutateDocument(actionName: String, operation: (PDFDocument) throws -> Void) {
        let before = pdfDocument.dataRepresentation()
        guard before != nil || pdfDocument.pageCount == 0 else {
            present(error: BarebonesDocumentError.unableToEncode)
            return
        }
        performBusy("Updating pages…") {
            do {
                try operation(pdfDocument)
                if let before {
                    registerUndo(snapshot: before, actionName: actionName)
                } else {
                    registerUndoToEmptyDocument(actionName: actionName)
                }
                changed()
            } catch {
                if let before { restoreWithoutUndo(from: before) }
                throw error
            }
        }
    }

    private func registerUndo(snapshot: Data, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDocument(from: snapshot, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func registerUndoToEmptyDocument(actionName: String) {
        undoManager?.registerUndo(withTarget: self) { target in
            guard let redo = target.pdfDocument.dataRepresentation() else { return }
            let emptyDocument = PDFDocument()
            target.pdfDocument = emptyDocument
            target.onDocumentReplaced?(emptyDocument)
            target.finishReplacingDocument()
            target.pdfView?.document = emptyDocument
            target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                redoTarget.restoreDocument(from: redo, actionName: actionName)
            }
            target.undoManager?.setActionName(actionName)
            target.changed()
        }
        undoManager?.setActionName(actionName)
    }

    private func restoreDocument(from data: Data, actionName: String) {
        guard let redo = pdfDocument.dataRepresentation(), let document = PDFDocument(data: data) else { return }
        pdfDocument = document
        onDocumentReplaced?(document)
        finishReplacingDocument()
        pdfView?.document = document
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDocument(from: redo, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        changed()
    }

    private func restoreWithoutUndo(from data: Data) {
        guard let document = PDFDocument(data: data) else { return }
        pdfDocument = document
        onDocumentReplaced?(document)
        finishReplacingDocument()
        pdfView?.document = document
    }

    private func changed() {
        pageCount = pdfDocument.pageCount
        currentPageIndex = min(currentPageIndex, max(0, pageCount - 1))
        isEdited = true
        onDocumentChanged?()
        pdfView?.layoutDocumentView()
        pdfView?.needsDisplay = true
    }

    private func finishReplacingDocument() {
        SignatureImageAnnotation.restoreCustomSignatures(in: pdfDocument)
        pageCount = pdfDocument.pageCount
        currentPageIndex = min(currentPageIndex, max(0, pageCount - 1))
        selectedPageIndexes = pageCount > 0 ? IndexSet(integer: currentPageIndex) : []
        selectedAnnotation = nil
        needsPassword = pdfDocument.isLocked
    }

    private func showCurrentSearchResult() {
        guard searchResults.indices.contains(searchResultIndex) else {
            pdfView?.highlightedSelections = nil
            return
        }
        let selection = searchResults[searchResultIndex]
        pdfView?.highlightedSelections = [selection]
        pdfView?.go(to: selection)
        if let page = selection.pages.first {
            let index = pdfDocument.index(for: page)
            if index != NSNotFound { currentPageIndex = index }
        }
    }

    private func performBusy(_ message: String, operation: () throws -> Void) {
        isBusy = true
        busyMessage = message
        defer {
            isBusy = false
            busyMessage = ""
        }
        do {
            try operation()
        } catch {
            present(error: error)
        }
    }
}
