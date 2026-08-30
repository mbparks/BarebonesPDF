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
            Text("The selected PDF text objects are rewritten in place. Paragraph text is distributed across the existing lines; fonts and placement are preserved, but this is approximate reflow and embedded fonts may not contain every character.")
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
