import SwiftUI

@main
struct BarebonesPDFApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: BarebonesDocument()) { configuration in
            MainDocumentView(
                document: configuration.$document,
                fileURL: configuration.fileURL
            )
        }
        .commands {
            BarebonesCommands()
        }
        .defaultSize(width: 1120, height: 760)
    }
}
