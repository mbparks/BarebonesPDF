import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AnnotationToolbar: View {
    @ObservedObject var state: DocumentState
    @State private var choosingSignature = false

    private let primaryTools: [AnnotationTool] = [
        .select, .editText, .highlight, .underline, .strikethrough, .ink,
        .textBox, .note, .rectangle, .oval, .line, .arrow, .eraser
    ]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(primaryTools) { tool in
                Button {
                    state.activeTool = tool
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: tool.symbolName)
                        if state.activeTool == tool {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8, weight: .bold))
                                .offset(x: 4, y: 4)
                                .accessibilityHidden(true)
                        }
                    }
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.bordered)
                .tint(state.activeTool == tool ? .accentColor : nil)
                .help(tool.title)
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(state.activeTool == tool ? .isSelected : [])
            }

            Divider().frame(height: 20)

            Button {
                choosingSignature = true
            } label: {
                Label(
                    state.activeTool == .signature
                        ? "Placing Signature"
                        : (state.pendingSignatureImage == nil ? "Choose Signature" : "Place Signature"),
                    systemImage: state.activeTool == .signature ? "checkmark.circle.fill" : "signature"
                )
            }
            .buttonStyle(.bordered)
            .tint(state.activeTool == .signature ? .accentColor : nil)
            .help("Choose a local PNG or JPEG, then click the page to place it")

            Divider().frame(height: 20)

            Button {
                state.inspectorVisible.toggle()
            } label: {
                Label("Properties", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .help("Show annotation properties")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        .fileImporter(
            isPresented: $choosingSignature,
            allowedContentTypes: [.png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            do {
                let url = try result.get().first!
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard let image = NSImage(contentsOf: url) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                state.pendingSignatureImage = image
                state.pendingSignatureName = url.deletingPathExtension().lastPathComponent
                state.activeTool = .signature
            } catch {
                state.present(title: "Could Not Load Signature", message: "Choose a readable PNG or JPEG image.")
            }
        }
    }
}
