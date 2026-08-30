import AppKit
import SwiftUI

struct BarebonesCommands: Commands {
    @FocusedValue(\.documentState) private var state

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print…") { state?.printDocument() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(state?.hasDocument != true)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                NSDocumentController.shared.currentDocument?.save(nil)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(state?.hasDocument != true)

            Button("Save As…") {
                NSDocumentController.shared.currentDocument?.saveAs(nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(state?.hasDocument != true)

            Button("Duplicate") {
                NSDocumentController.shared.currentDocument?.duplicate(nil)
            }
            .disabled(state?.hasDocument != true)

            Divider()

            Button("Revert to Saved") {
                NSDocumentController.shared.currentDocument?.revertToSaved(nil)
            }
            .disabled(state?.fileURL == nil)
        }

        CommandGroup(after: .importExport) {
            Divider()
            Button("Extract Selected Pages…") { state?.extractSelectedPages() }
                .disabled(state?.selectedPageIndexes.isEmpty != false)
            Menu("Export Selected Page as Image") {
                Button("PNG…") { state?.exportSelectedPageImage(format: .png) }
                Button("JPEG…") { state?.exportSelectedPageImage(format: .jpeg) }
            }
            .disabled(state?.hasDocument != true)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Delete Selected Annotation or Pages") { state?.deleteActiveContext() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(state?.selectedAnnotation == nil && state?.selectedPageIndexes.isEmpty != false)
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") {
                state?.searchVisible = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(state?.hasDocument != true)

            Button("Find Next") { state?.nextSearchResult() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(state?.searchResults.isEmpty != false)
            Button("Find Previous") { state?.previousSearchResult() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(state?.searchResults.isEmpty != false)
        }

        CommandGroup(after: .sidebar) {
            Button(state?.sidebarVisible == true ? "Hide Thumbnails" : "Show Thumbnails") {
                state?.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(state?.hasDocument != true)

            Button(state?.annotationBarVisible == true ? "Hide Annotation Tools" : "Show Annotation Tools") {
                state?.annotationBarVisible.toggle()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(state?.hasDocument != true)

            Button(state?.inspectorVisible == true ? "Hide Annotation Properties" : "Show Annotation Properties") {
                state?.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(state?.hasDocument != true)

            Divider()

            Picker("Page Display", selection: viewerModeBinding) {
                ForEach(ViewerMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .disabled(state?.hasDocument != true)

            Divider()

            Button("Zoom In") { state?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(state?.hasDocument != true)
            Button("Zoom Out") { state?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(state?.hasDocument != true)
            Button("Actual Size") { state?.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(state?.hasDocument != true)
            Button("Fit Page") { state?.fitPage() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(state?.hasDocument != true)
            Button("Fit Width") { state?.fitWidth() }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(state?.hasDocument != true)

            Divider()

            Button("Previous Page") { state?.previousPage() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(state?.canNavigateBackward != true)
            Button("Next Page") { state?.nextPage() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(state?.canNavigateForward != true)

            Divider()

            Button("Enter Full Screen") { state?.toggleFullScreen() }
                .keyboardShortcut("f", modifiers: [.command, .control])
        }

        CommandMenu("Annotate") {
            ForEach(AnnotationTool.allCases) { tool in
                Button(tool.title) {
                    state?.annotationBarVisible = true
                    state?.activeTool = tool
                }
                .disabled(state?.hasDocument != true || (tool == .signature && state?.pendingSignatureImage == nil))
            }
            Divider()
            Button("Delete Selected Annotation") { state?.deleteSelectedAnnotation() }
                .disabled(state?.selectedAnnotation == nil)
        }

        CommandMenu("Pages") {
            Button("Rotate Left") { state?.rotateSelectedPages(degrees: -90) }
                .disabled(state?.hasDocument != true)
            Button("Rotate Right") { state?.rotateSelectedPages(degrees: 90) }
                .disabled(state?.hasDocument != true)
            Divider()
            Button("Duplicate Selected Pages") { state?.duplicateSelectedPages() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(state?.hasDocument != true)
            Button("Insert Pages from PDF…") { state?.insertPagesFromPDF() }
                .disabled(state?.hasDocument != true)
            Button("Insert Blank Page") { state?.insertBlankPage() }
                .disabled(state?.hasDocument != true)
            Divider()
            Button("Extract Selected Pages…") { state?.extractSelectedPages() }
                .disabled(state?.selectedPageIndexes.isEmpty != false)
            Divider()
            Button("Delete Selected Pages") { state?.deleteSelectedPages() }
                .disabled(state?.selectedPageIndexes.isEmpty != false)
        }

        CommandGroup(after: .appInfo) {
            Button("Document Information…") {
                state?.metadataVisible = true
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(state?.hasDocument != true)
        }
    }

    private var viewerModeBinding: Binding<ViewerMode> {
        Binding(
            get: { state?.viewerMode ?? .continuous },
            set: { state?.viewerMode = $0 }
        )
    }
}
