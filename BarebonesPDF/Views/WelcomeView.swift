import AppKit
import SwiftUI

struct WelcomeView: View {
    @ObservedObject var state: DocumentState

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("BarebonesPDF")
                    .font(.title2.weight(.semibold))
                Text("Read PDFs and make the small edits that matter.")
                    .foregroundStyle(.secondary)
            }

            Button("Open PDF…") {
                NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityHint("Opens a file selection dialog")

            Button("Create Blank PDF") {
                state.insertBlankPage()
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Creates a new letter-size PDF with one blank page")

            Text("You can also drag a PDF here or choose BarebonesPDF from Finder’s Open With menu.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            return true
        }
    }
}
