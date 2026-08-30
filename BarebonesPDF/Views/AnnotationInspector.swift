import AppKit
import PDFKit
import SwiftUI

struct AnnotationInspector: View {
    @ObservedObject var state: DocumentState
    @State private var contents = ""
    @State private var fontSize = 13.0

    private var swiftUIColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: state.annotationColor) },
            set: { state.annotationColor = NSColor($0); state.applyAnnotationAppearance() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PROPERTIES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { state.inspectorVisible = false } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close properties")
                .accessibilityLabel("Close annotation properties")
            }
            .padding(12)

            Divider()

            Form {
                if let annotation = state.selectedAnnotation {
                    Text(annotationDisplayName(annotation))
                        .font(.headline)
                        .accessibilityLabel("Selected annotation: \(annotationDisplayName(annotation))")

                    if annotation.type == PDFAnnotationSubtype.freeText.rawValue ||
                        annotation.type == PDFAnnotationSubtype.text.rawValue {
                        Section("Text") {
                            TextEditor(text: $contents)
                                .font(.body)
                                .frame(minHeight: 72)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                                .accessibilityLabel("Annotation text")

                            Button("Apply Text") {
                                state.updateSelectedAnnotation(actionName: "Edit Annotation Text") {
                                    $0.contents = contents
                                }
                            }
                        }
                    }

                    Section("Appearance") {
                        ColorPicker("Color", selection: swiftUIColor, supportsOpacity: false)

                        LabeledContent("Opacity") {
                            HStack {
                                Slider(value: $state.annotationOpacity, in: 0.1...1, step: 0.05) { editing in
                                    if !editing { state.applyAnnotationAppearance() }
                                }
                                Text("\(Int(state.annotationOpacity * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }

                        LabeledContent("Line Width") {
                            HStack {
                                Slider(value: $state.annotationLineWidth, in: 0.5...12, step: 0.5) { editing in
                                    if !editing { state.applyAnnotationAppearance() }
                                }
                                Text(String(format: "%.1f", state.annotationLineWidth))
                                    .monospacedDigit()
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }

                    if annotation.type == PDFAnnotationSubtype.freeText.rawValue {
                        Section("Font") {
                            Picker("Family", selection: fontFamily) {
                                ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                                    Text(family).tag(family)
                                }
                            }
                            TextField("Size", value: $fontSize, format: .number)
                                .onSubmit { applyFont() }
                            Button("Apply Font") { applyFont() }
                        }
                    }

                    Section {
                        Button("Delete Annotation", role: .destructive) {
                            state.deleteSelectedAnnotation()
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "cursorarrow.click")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No Annotation Selected")
                            .font(.headline)
                        Text("Choose Select, then click an annotation on the page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 230, idealWidth: 260, maxWidth: 340)
        .background(.regularMaterial)
        .onAppear(perform: synchronizeFields)
        .onReceive(state.$selectedAnnotation) { _ in synchronizeFields() }
    }

    private var fontFamily: Binding<String> {
        Binding(
            get: { state.annotationFont.familyName ?? "Helvetica" },
            set: { family in
                state.annotationFont = NSFontManager.shared.convert(state.annotationFont, toFamily: family)
                applyFont()
            }
        )
    }

    private func synchronizeFields() {
        contents = state.selectedAnnotation?.contents ?? ""
        if let selectedFontSize = state.selectedAnnotation?.font?.pointSize {
            fontSize = Double(selectedFontSize)
        } else {
            fontSize = Double(state.annotationFont.pointSize)
        }
    }

    private func applyFont() {
        let size = min(max(fontSize, 6), 144)
        let family = state.annotationFont.familyName ?? "Helvetica"
        state.annotationFont = NSFont(name: family, size: size) ?? .systemFont(ofSize: size)
        state.applyAnnotationAppearance()
    }

    private func annotationDisplayName(_ annotation: PDFAnnotation) -> String {
        switch annotation.type {
        case PDFAnnotationSubtype.highlight.rawValue: return "Highlight"
        case PDFAnnotationSubtype.underline.rawValue: return "Underline"
        case PDFAnnotationSubtype.strikeOut.rawValue: return "Strikethrough"
        case PDFAnnotationSubtype.ink.rawValue: return "Drawing"
        case PDFAnnotationSubtype.freeText.rawValue: return "Text Box"
        case PDFAnnotationSubtype.text.rawValue: return "Sticky Note"
        case PDFAnnotationSubtype.square.rawValue: return "Rectangle"
        case PDFAnnotationSubtype.circle.rawValue: return "Oval"
        case PDFAnnotationSubtype.line.rawValue: return "Line or Arrow"
        case PDFAnnotationSubtype.stamp.rawValue: return "Signature Image"
        default: return "Annotation"
        }
    }
}
