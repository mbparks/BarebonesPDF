import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailSidebar: View {
    @ObservedObject var state: DocumentState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("THUMBNAILS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(state.pageCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            List(selection: $state.selectedPageIndexes) {
                ForEach(0..<state.pageCount, id: \.self) { index in
                    ThumbnailRow(document: state.pdfDocument, index: index)
                        .tag(index)
                        .onDrag {
                            if !state.selectedPageIndexes.contains(index) {
                                state.selectedPageIndexes = IndexSet(integer: index)
                            }
                            return NSItemProvider(object: NSString(string: "barebones-page-drag"))
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PageDropDelegate(state: state, destination: index)
                        )
                }

                Color.clear
                    .frame(height: 18)
                    .listRowSeparator(.hidden)
                    .onDrop(
                        of: [UTType.text],
                        delegate: PageDropDelegate(state: state, destination: state.pageCount)
                    )
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Page thumbnails")
            .contextMenu {
                Button("Rotate Left") { state.rotateSelectedPages(degrees: -90) }
                Button("Rotate Right") { state.rotateSelectedPages(degrees: 90) }
                Divider()
                Button("Duplicate") { state.duplicateSelectedPages() }
                Button("Insert Pages from PDF…") { state.insertPagesFromPDF() }
                Button("Insert Blank Page") { state.insertBlankPage() }
                Divider()
                Button("Extract Selected Pages…") { state.extractSelectedPages() }
                Menu("Export Page as Image") {
                    Button("PNG…") { state.exportSelectedPageImage(format: .png) }
                    Button("JPEG…") { state.exportSelectedPageImage(format: .jpeg) }
                }
                Divider()
                Button("Delete", role: .destructive) { state.deleteSelectedPages() }
                    .disabled(state.selectedPageIndexes.isEmpty)
            }

            Divider()

            HStack(spacing: 12) {
                Button { state.insertPagesFromPDF() } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .help("Insert pages from another PDF")
                .accessibilityLabel("Insert pages from PDF")

                Button { state.insertBlankPage() } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                }
                .help("Insert a blank page")
                .accessibilityLabel("Insert blank page")

                Spacer()

                Button { state.deleteSelectedPages() } label: {
                    Image(systemName: "trash")
                }
                .disabled(state.selectedPageIndexes.isEmpty)
                .help("Delete selected pages")
                .accessibilityLabel("Delete selected pages")
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(minWidth: 150, idealWidth: 190, maxWidth: 280)
        .background(.regularMaterial)
        .onChange(of: state.selectedPageIndexes) { selection in
            state.select(annotation: nil)
            if selection.count == 1, let page = selection.first {
                state.goToPage(page + 1)
            }
        }
    }
}

private struct ThumbnailRow: View {
    let document: PDFDocument
    let index: Int

    var body: some View {
        VStack(spacing: 6) {
            if let page = document.page(at: index) {
                Image(nsImage: page.thumbnail(of: CGSize(width: 130, height: 170), for: .cropBox))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 130, maxHeight: 170)
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            }
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1)")
    }
}

private struct PageDropDelegate: DropDelegate {
    let state: DocumentState
    let destination: Int

    func validateDrop(info: DropInfo) -> Bool {
        !state.selectedPageIndexes.isEmpty
    }

    func performDrop(info: DropInfo) -> Bool {
        guard !state.selectedPageIndexes.isEmpty else { return false }
        state.moveSelectedPages(to: destination)
        return true
    }
}
