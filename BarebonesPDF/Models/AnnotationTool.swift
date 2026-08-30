import Foundation

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case highlight
    case underline
    case strikethrough
    case ink
    case textBox
    case note
    case rectangle
    case oval
    case line
    case arrow
    case signature
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .ink: return "Draw"
        case .textBox: return "Text Box"
        case .note: return "Sticky Note"
        case .rectangle: return "Rectangle"
        case .oval: return "Oval"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .signature: return "Signature Image"
        case .eraser: return "Delete Annotation"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        case .ink: return "pencil.tip"
        case .textBox: return "character.textbox"
        case .note: return "note.text"
        case .rectangle: return "rectangle"
        case .oval: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .signature: return "signature"
        case .eraser: return "eraser"
        }
    }

    var usesDragGesture: Bool {
        switch self {
        case .ink, .rectangle, .oval, .line, .arrow: return true
        default: return false
        }
    }
}
