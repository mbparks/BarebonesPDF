import SwiftUI

struct TextContentEditor: View {
    let draft: PDFTextEditDraft
    let apply: (String) -> Void
    let cancel: () -> Void
    @State private var replacement: String

    init(draft: PDFTextEditDraft, apply: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.draft = draft
        self.apply = apply
        self.cancel = cancel
        _replacement = State(initialValue: draft.originalText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rewrite PDF Text").font(.headline)
            TextEditor(text: $replacement)
                .font(.body)
                .frame(minWidth: 420, minHeight: 110)
                .border(Color.secondary.opacity(0.35))
                .accessibilityLabel("Replacement text")
            Text("The selected PDF text objects are rewritten in place with approximate line reflow. Position, size, weight, style, and color are retained; a matching standard PDF font is used when an embedded subset cannot safely encode the replacement.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Replace", action: { apply(replacement) })
                    .keyboardShortcut(.defaultAction)
                    .disabled(replacement.isEmpty || replacement == draft.originalText)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}
