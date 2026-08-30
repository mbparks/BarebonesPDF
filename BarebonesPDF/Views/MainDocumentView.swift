import AppKit
import PDFKit
import SwiftUI

struct MainDocumentView: View {
    @Binding private var document: BarebonesDocument
    @StateObject private var state: DocumentState
    @Environment(\.undoManager) private var undoManager
    @State private var password = ""
    @State private var pageEntry = "1"
    private let fileURL: URL?

    init(document: Binding<BarebonesDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
        _state = StateObject(wrappedValue: DocumentState(
            document: document.wrappedValue.pdfDocument,
            fileURL: fileURL
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.annotationBarVisible && state.hasDocument {
                AnnotationToolbar(state: state)
                Divider()
            }

            if state.searchVisible && state.hasDocument {
                SearchBar(state: state)
                Divider()
            }

            if state.hasDocument {
                HSplitView {
                    if state.sidebarVisible {
                        ThumbnailSidebar(state: state)
                    }

                    PDFKitView(state: state)
                        .frame(minWidth: 360, minHeight: 320)

                    if state.inspectorVisible {
                        AnnotationInspector(state: state)
                    }
                }
                StatusBar(state: state)
            } else {
                WelcomeView(state: state)
            }
        }
        .toolbar { toolbarContent }
        .focusedSceneValue(\.documentState, state)
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            configureStateConnections()
            state.fileURL = fileURL
            SignatureImageAnnotation.restoreCustomSignatures(in: state.pdfDocument)
        }
        .onChange(of: fileURL) { state.fileURL = $0 }
        .onChange(of: document.identityToken) { _ in
            state.synchronize(document: document.pdfDocument)
        }
        .onChange(of: state.currentPageIndex) { newValue in
            pageEntry = "\(newValue + 1)"
        }
        .sheet(isPresented: $state.metadataVisible) {
            MetadataInspector(state: state)
        }
        .sheet(item: $state.textEditDraft) { draft in
            TextContentEditor(
                draft: draft,
                apply: state.applyTextEdit,
                cancel: { state.textEditDraft = nil }
            )
        }
        .sheet(isPresented: $state.needsPassword) {
            passwordSheet
        }
        .alert(item: $state.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { state.sidebarVisible.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .disabled(!state.hasDocument)
            .help("Show or hide thumbnails")
            .accessibilityLabel("Toggle thumbnail sidebar")
        }

        ToolbarItemGroup {
            Button { state.previousPage() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!state.canNavigateBackward)
            .help("Previous page")
            .accessibilityLabel("Previous page")

            TextField("Page", text: $pageEntry)
                .frame(width: 38)
                .multilineTextAlignment(.trailing)
                .onSubmit {
                    if let page = Int(pageEntry) { state.goToPage(page) }
                    pageEntry = "\(state.currentPageIndex + 1)"
                }
                .disabled(!state.hasDocument)
                .accessibilityLabel("Page number")

            Text("/ \(state.pageCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button { state.nextPage() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!state.canNavigateForward)
            .help("Next page")
            .accessibilityLabel("Next page")
        }

        ToolbarItemGroup {
            Button { state.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(!state.hasDocument)
                .help("Zoom out")
                .accessibilityLabel("Zoom out")

            Menu {
                Button("Actual Size") { state.actualSize() }
                Button("Fit Page") { state.fitPage() }
                Button("Fit Width") { state.fitWidth() }
            } label: {
                Text("\(state.zoomPercent)%")
                    .monospacedDigit()
                    .frame(minWidth: 42)
            }
            .disabled(!state.hasDocument)
            .help("Zoom options")

            Button { state.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(!state.hasDocument)
                .help("Zoom in")
                .accessibilityLabel("Zoom in")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.searchVisible.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .disabled(!state.hasDocument)
            .help("Search")
            .accessibilityLabel("Search document")

            Button {
                state.annotationBarVisible.toggle()
                if state.annotationBarVisible { state.activeTool = .select }
            } label: {
                Image(systemName: "pencil.tip.crop.circle")
            }
            .disabled(!state.hasDocument)
            .help("Annotation tools")
            .accessibilityLabel("Toggle annotation tools")

            Button { state.inspectorVisible.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .disabled(!state.hasDocument)
            .help("Annotation properties")
            .accessibilityLabel("Toggle annotation properties")
        }
    }

    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This PDF Is Password Protected")
                .font(.headline)
            Text("Enter the document password to view it. The password is used only by PDFKit and is not stored.")
                .foregroundStyle(.secondary)
            SecureField("Password", text: $password)
                .onSubmit { state.unlock(with: password) }
            HStack {
                Spacer()
                Button("Unlock") { state.unlock(with: password) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func configureStateConnections() {
        state.undoManager = undoManager
        state.onDocumentChanged = { document.touch() }
        state.onDocumentReplaced = { replacement in document.replacePDF(with: replacement) }
    }
}

private struct DocumentStateFocusedKey: FocusedValueKey {
    typealias Value = DocumentState
}

extension FocusedValues {
    var documentState: DocumentState? {
        get { self[DocumentStateFocusedKey.self] }
        set { self[DocumentStateFocusedKey.self] = newValue }
    }
}
