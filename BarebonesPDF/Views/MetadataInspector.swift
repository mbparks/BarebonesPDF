import SwiftUI

struct MetadataInspector: View {
    @ObservedObject var state: DocumentState
    @Environment(\.dismiss) private var dismiss
    @State private var editable: EditableMetadata

    init(state: DocumentState) {
        self.state = state
        _editable = State(initialValue: EditableMetadata(document: state.pdfDocument))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Document Information")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            TabView {
                Form {
                    TextField("Title", text: $editable.title)
                    TextField("Author", text: $editable.author)
                    TextField("Subject", text: $editable.subject)
                    TextField("Keywords", text: $editable.keywords, axis: .vertical)
                    Text("Separate keywords with commas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
                .padding(.top, 8)
                .tabItem { Label("Description", systemImage: "text.alignleft") }

                InformationSummary(state: state)
                    .tabItem { Label("Details", systemImage: "info.circle") }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply") {
                    state.applyMetadata(editable)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 470)
    }
}

private struct InformationSummary: View {
    @ObservedObject var state: DocumentState

    var body: some View {
        let information = ReadOnlyMetadata(document: state.pdfDocument, fileURL: state.fileURL)
        Form {
            detail("File Name", information.fileName)
            detail("File Size", information.fileSize)
            detail("Pages", "\(information.pageCount)")
            detail("First Page Size", information.pageDimensions)
            detail("Version", information.pdfVersion)
            detail("Created", information.creationDate)
            detail("Modified", information.modificationDate)
            detail("Security", information.encryptionStatus)
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
