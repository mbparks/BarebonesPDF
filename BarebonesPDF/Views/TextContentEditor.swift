import AppKit
import SwiftUI

struct TextContentEditor: View {
    let draft: PDFTextEditDraft
    let prepare: (String) -> PDFTextEditPreview?
    let apply: (PDFTextEditPreview) -> Void
    let cancel: () -> Void
    @State private var replacement: String
    @State private var preview: PDFTextEditPreview?

    init(
        draft: PDFTextEditDraft,
        prepare: @escaping (String) -> PDFTextEditPreview?,
        apply: @escaping (PDFTextEditPreview) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.prepare = prepare
        self.apply = apply
        self.cancel = cancel
        _replacement = State(initialValue: draft.originalText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let preview {
                previewView(preview)
            } else {
                editorView
            }
        }
        .padding(20)
        .frame(width: preview == nil ? 540 : 820)
        .frame(minHeight: preview == nil ? 320 : 650)
    }

    private var editorView: some View {
        Group {
            Text("Rewrite PDF Text").font(.headline)
            TextEditor(text: $replacement)
                .font(.body)
                .frame(minWidth: 460, minHeight: 150)
                .border(Color.secondary.opacity(0.35))
                .accessibilityLabel("Replacement text")
            Text("The edit is generated in memory and must pass geometry, structure, text-extraction, and rendered-page checks before a mandatory preview is shown. The open document is not changed during validation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Validate & Preview") {
                    preview = prepare(replacement)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(replacement.isEmpty || replacement == draft.originalText)
            }
        }
    }

    @ViewBuilder
    private func previewView(_ preview: PDFTextEditPreview) -> some View {
        Text("Review Text Edit").font(.headline)
        HStack(alignment: .top, spacing: 16) {
            previewImage(preview.beforeImage, label: "Before")
            previewImage(preview.afterImage, label: "After")
        }
        .frame(maxWidth: .infinity)

        if preview.diagnostics.usedStandardFontSubstitution {
            let originals = uniqueFontNames(preview.diagnostics.originalFontNames)
            let replacements = uniqueFontNames(preview.diagnostics.replacementFontNames)
            Label("Font substitution: \(originals) → \(replacements)", systemImage: "textformat")
                .font(.callout)
                .accessibilityLabel("Font substitution from \(originals) to \(replacements)")
        }

        VStack(alignment: .leading, spacing: 5) {
            ForEach(preview.validationSummary, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Text("Inspect the edited paragraph closely. Apply commits the validated in-memory copy and creates an Undo checkpoint; Cancel leaves the document unchanged.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        HStack {
            Button("Back") { self.preview = nil }
            Spacer()
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("Apply Validated Edit") { apply(preview) }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func previewImage(_ image: NSImage, label: String) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold))
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 370, height: 430)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.secondary.opacity(0.35)))
                .accessibilityLabel("\(label) page preview")
        }
    }

    private func uniqueFontNames(_ names: [String]) -> String {
        let cleaned = names.filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted().joined(separator: ", ")
    }
}
