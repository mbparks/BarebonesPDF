import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

final class SignatureImageAnnotation: PDFAnnotation {
    static let imageDataKey = PDFAnnotationKey(rawValue: "BarebonesSignatureData")
    static let imageNameKey = PDFAnnotationKey(rawValue: "BarebonesSignatureName")

    static func make(bounds: CGRect, image: NSImage, name: String) -> SignatureImageAnnotation {
        let annotation = SignatureImageAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
        annotation.contents = name
        if let data = image.tiffRepresentation {
            annotation.setValue(data, forAnnotationKey: imageDataKey)
        }
        annotation.setValue(name, forAnnotationKey: imageNameKey)
        annotation.color = .clear
        annotation.shouldPrint = true
        return annotation
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let data = value(forAnnotationKey: Self.imageDataKey) as? Data,
              let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            super.draw(with: box, in: context)
            return
        }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }

    static func restoreCustomSignatures(in document: PDFDocument) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard !(annotation is SignatureImageAnnotation),
                      let data = annotation.value(forAnnotationKey: imageDataKey) as? Data,
                      let image = NSImage(data: data) else { continue }
                let name = annotation.value(forAnnotationKey: imageNameKey) as? String ?? annotation.contents ?? "Signature"
                let restored = SignatureImageAnnotation.make(bounds: annotation.bounds, image: image, name: name)
                restored.shouldDisplay = annotation.shouldDisplay
                restored.shouldPrint = annotation.shouldPrint
                page.removeAnnotation(annotation)
                page.addAnnotation(restored)
            }
        }
    }
}

final class InteractivePDFView: PDFView {
    weak var documentState: DocumentState?

    private var gesturePage: PDFPage?
    private var gestureStart = CGPoint.zero
    private var gesturePoints: [CGPoint] = []
    private var gestureSnapshot: Data?
    private var draggedAnnotation: PDFAnnotation?
    private var draggedAnnotationOriginalBounds: CGRect?
    private var annotationDragOffset = CGPoint.zero
    private let selectionLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        selectionLayer.fillColor = NSColor.clear.cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
        selectionLayer.lineWidth = 2
        selectionLayer.lineDashPattern = [5, 3]
        selectionLayer.isHidden = true
        layer?.addSublayer(selectionLayer)
        registerForDraggedTypes([.fileURL])
        displaysPageBreaks = true
        pageBreakMargins = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        backgroundColor = .windowBackgroundColor
        minScaleFactor = 0.1
        maxScaleFactor = 8
        setAccessibilityLabel("PDF document canvas")
    }

    override func layout() {
        super.layout()
        updateSelectionOverlay()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        documentState?.applyPreferredZoom()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let state = documentState else {
            super.mouseDown(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else {
            super.mouseDown(with: event)
            return
        }
        let pagePoint = convert(viewPoint, to: page)
        gesturePage = page
        gestureStart = pagePoint
        gesturePoints = [pagePoint]
        gestureSnapshot = state.snapshot()

        switch state.activeTool {
        case .select:
            if let annotation = annotation(at: pagePoint, on: page) {
                state.select(annotation: annotation)
                draggedAnnotation = annotation
                draggedAnnotationOriginalBounds = annotation.bounds
                annotationDragOffset = CGPoint(
                    x: pagePoint.x - annotation.bounds.origin.x,
                    y: pagePoint.y - annotation.bounds.origin.y
                )
                updateSelectionOverlay()
            } else {
                state.select(annotation: nil)
                super.mouseDown(with: event)
            }
        case .editText:
            state.select(annotation: nil)
            guard let word = page.selectionForWord(at: pagePoint) else {
                clearSelection()
                state.present(
                    title: "Text Cannot Be Selected",
                    message: "No selectable text was found there. This may be a scanned page or outlined artwork."
                )
                return
            }
            setCurrentSelection(word, animate: false)
            state.beginTextEdit(on: page, selectionBounds: word.bounds(for: page))
        case .eraser:
            if let annotation = annotation(at: pagePoint, on: page), isEditable(annotation) {
                state.select(annotation: annotation)
                state.deleteSelectedAnnotation()
            }
        case .textBox, .note, .signature:
            addPointAnnotation(tool: state.activeTool, at: pagePoint, on: page, state: state)
        case .highlight, .underline, .strikethrough:
            super.mouseDown(with: event)
        case .ink, .rectangle, .oval, .line, .arrow:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state = documentState, let page = gesturePage else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(convert(event.locationInWindow, from: nil), to: page)
        switch state.activeTool {
        case .select where draggedAnnotation != nil:
            guard let annotation = draggedAnnotation else { return }
            var bounds = annotation.bounds
            bounds.origin = CGPoint(x: point.x - annotationDragOffset.x, y: point.y - annotationDragOffset.y)
            let pageBounds = page.bounds(for: displayBox)
            bounds.origin.x = min(max(bounds.origin.x, pageBounds.minX), pageBounds.maxX - bounds.width)
            bounds.origin.y = min(max(bounds.origin.y, pageBounds.minY), pageBounds.maxY - bounds.height)
            annotation.bounds = bounds
            needsDisplay = true
            updateSelectionOverlay()
        case .ink:
            gesturePoints.append(point)
        case .highlight, .underline, .strikethrough:
            super.mouseDragged(with: event)
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let state = documentState, let page = gesturePage else {
            super.mouseUp(with: event)
            return
        }
        let endPoint = convert(convert(event.locationInWindow, from: nil), to: page)
        let before = gestureSnapshot ?? state.snapshot()

        switch state.activeTool {
        case .select:
            if let draggedAnnotation, draggedAnnotation.bounds != draggedAnnotationOriginalBounds {
                state.registerAnnotationChange(actionName: "Move Annotation", beforeData: before)
            } else {
                if draggedAnnotation == nil { super.mouseUp(with: event) }
            }
        case .highlight, .underline, .strikethrough:
            super.mouseUp(with: event)
            addMarkupAnnotations(tool: state.activeTool, state: state, beforeData: before)
        case .ink:
            gesturePoints.append(endPoint)
            if let annotation = makeInkAnnotation(points: gesturePoints, state: state) {
                page.addAnnotation(annotation)
                state.select(annotation: annotation)
                state.registerAnnotationChange(actionName: "Draw Annotation", beforeData: before)
            }
        case .rectangle, .oval, .line, .arrow:
            if let annotation = makeShapeAnnotation(
                tool: state.activeTool,
                start: gestureStart,
                end: endPoint,
                state: state
            ) {
                page.addAnnotation(annotation)
                state.select(annotation: annotation)
                state.registerAnnotationChange(actionName: "Add \(state.activeTool.title)", beforeData: before)
            }
        default:
            break
        }

        draggedAnnotation = nil
        draggedAnnotationOriginalBounds = nil
        gesturePage = nil
        gesturePoints = []
        gestureSnapshot = nil
        updateSelectionOverlay()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedPDFURL(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = draggedPDFURL(from: sender) else { return false }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                Task { @MainActor [weak self] in self?.documentState?.present(error: error) }
            }
        }
        return true
    }

    func updateSelectionOverlay() {
        guard let annotation = documentState?.selectedAnnotation,
              let page = annotation.page else {
            selectionLayer.isHidden = true
            return
        }
        let rect = convert(annotation.bounds, from: page).insetBy(dx: -3, dy: -3)
        selectionLayer.frame = bounds
        selectionLayer.path = CGPath(rect: rect, transform: nil)
        selectionLayer.isHidden = false
    }

    private func addPointAnnotation(tool: AnnotationTool, at point: CGPoint, on page: PDFPage, state: DocumentState) {
        let before = state.snapshot()
        let annotation: PDFAnnotation?
        switch tool {
        case .textBox:
            annotation = PDFAnnotation(
                bounds: CGRect(x: point.x, y: point.y - 48, width: 180, height: 56),
                forType: .freeText,
                withProperties: nil
            )
            annotation?.contents = "Text"
            annotation?.font = state.annotationFont
            annotation?.fontColor = state.annotationColor.withAlphaComponent(1)
            annotation?.alignment = .left
        case .note:
            annotation = PDFAnnotation(
                bounds: CGRect(x: point.x - 12, y: point.y - 12, width: 28, height: 28),
                forType: .text,
                withProperties: nil
            )
            annotation?.contents = "Note"
            annotation?.iconType = .comment
        case .signature:
            guard let image = state.pendingSignatureImage else {
                state.present(title: "Choose a Signature Image", message: "Use the annotation toolbar to choose a PNG or JPEG signature image before placing it.")
                return
            }
            let aspect = max(0.2, image.size.width / max(1, image.size.height))
            annotation = SignatureImageAnnotation.make(
                bounds: CGRect(x: point.x, y: point.y - 54, width: 54 * aspect, height: 54),
                image: image,
                name: state.pendingSignatureName
            )
        default:
            annotation = nil
        }
        guard let annotation else { return }
        annotation.color = state.annotationColor.withAlphaComponent(state.annotationOpacity)
        annotation.shouldPrint = true
        page.addAnnotation(annotation)
        state.select(annotation: annotation)
        state.registerAnnotationChange(actionName: "Add \(tool.title)", beforeData: before)
    }

    private func addMarkupAnnotations(
        tool: AnnotationTool,
        state: DocumentState,
        beforeData: Data?
    ) {
        guard let selection = currentSelection else { return }
        let subtype: PDFAnnotationSubtype
        switch tool {
        case .highlight: subtype = .highlight
        case .underline: subtype = .underline
        case .strikethrough: subtype = .strikeOut
        default: return
        }

        var lastAnnotation: PDFAnnotation?
        for line in selection.selectionsByLine() {
            guard let page = line.pages.first else { continue }
            let bounds = line.bounds(for: page)
            guard !bounds.isEmpty else { continue }
            let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
            annotation.color = state.annotationColor.withAlphaComponent(state.annotationOpacity)
            annotation.shouldPrint = true
            page.addAnnotation(annotation)
            lastAnnotation = annotation
        }
        if let lastAnnotation {
            state.select(annotation: lastAnnotation)
            state.registerAnnotationChange(actionName: "Add \(tool.title)", beforeData: beforeData)
            clearSelection()
        }
    }

    private func makeInkAnnotation(points: [CGPoint], state: DocumentState) -> PDFAnnotation? {
        guard points.count > 1 else { return nil }
        var bounds = CGRect(origin: points[0], size: .zero)
        for point in points.dropFirst() { bounds = bounds.union(CGRect(origin: point, size: .zero)) }
        bounds = bounds.insetBy(dx: -6, dy: -6)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let path = NSBezierPath()
        path.move(to: CGPoint(x: points[0].x - bounds.minX, y: points[0].y - bounds.minY))
        for point in points.dropFirst() {
            path.line(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
        }
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.add(path)
        annotation.color = state.annotationColor.withAlphaComponent(state.annotationOpacity)
        let border = PDFBorder()
        border.lineWidth = state.annotationLineWidth
        annotation.border = border
        annotation.shouldPrint = true
        return annotation
    }

    private func makeShapeAnnotation(
        tool: AnnotationTool,
        start: CGPoint,
        end: CGPoint,
        state: DocumentState
    ) -> PDFAnnotation? {
        var bounds = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        if bounds.width < 4 { bounds.size.width = 4 }
        if bounds.height < 4 { bounds.size.height = 4 }

        let subtype: PDFAnnotationSubtype = (tool == .rectangle) ? .square : (tool == .oval ? .circle : .line)
        let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
        annotation.color = state.annotationColor.withAlphaComponent(state.annotationOpacity)
        let border = PDFBorder()
        border.lineWidth = state.annotationLineWidth
        annotation.border = border
        if tool == .line || tool == .arrow {
            annotation.startPoint = CGPoint(x: 0, y: 0)
            annotation.endPoint = CGPoint(x: bounds.width, y: bounds.height)
            if tool == .arrow { annotation.endLineStyle = .closedArrow }
        }
        annotation.shouldPrint = true
        return annotation
    }

    private func annotation(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        page.annotations.reversed().first { annotation in
            isEditable(annotation) && annotation.bounds.insetBy(dx: -5, dy: -5).contains(point)
        }
    }

    private func isEditable(_ annotation: PDFAnnotation) -> Bool {
        annotation.type != PDFAnnotationSubtype.widget.rawValue &&
            annotation.type != PDFAnnotationSubtype.link.rawValue
    }

    private func draggedPDFURL(from sender: NSDraggingInfo) -> URL? {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return nil }
        return items.first { $0.pathExtension.lowercased() == "pdf" }
    }
}

struct PDFKitView: NSViewRepresentable {
    @ObservedObject var state: DocumentState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> InteractivePDFView {
        let view = InteractivePDFView()
        view.displayDirection = .vertical
        view.displaysAsBook = false
        view.displaysRTL = false
        view.delegate = context.coordinator
        state.attach(pdfView: view)
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: InteractivePDFView, context: Context) {
        if view.document !== state.pdfDocument {
            view.document = state.pdfDocument
            view.layoutDocumentView()
        }
        if view.displayMode != state.viewerMode.pdfDisplayMode {
            view.displayMode = state.viewerMode.pdfDisplayMode
        }
        view.updateSelectionOverlay()
    }

    final class Coordinator: NSObject, PDFViewDelegate {
        private weak var state: DocumentState?
        private var observers: [NSObjectProtocol] = []

        init(state: DocumentState) {
            self.state = state
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        func observe(_ view: PDFView) {
            let center = NotificationCenter.default
            for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged] {
                observers.append(center.addObserver(forName: name, object: view, queue: .main) { [weak self, weak view] _ in
                    guard let self, let view else { return }
                    Task { @MainActor in
                        self.state?.updateFromPDFView(page: view.currentPage, scaleFactor: view.scaleFactor)
                    }
                })
            }
        }
    }
}
