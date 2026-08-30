import PDFKit

enum ViewerMode: String, CaseIterable, Identifiable {
    case singlePage
    case continuous

    var id: String { rawValue }
    var title: String { self == .singlePage ? "Single Page" : "Continuous" }
    var pdfDisplayMode: PDFDisplayMode { self == .singlePage ? .singlePage : .singlePageContinuous }
}

enum ZoomBehavior: String, CaseIterable, Identifiable {
    case manual
    case fitPage
    case fitWidth

    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: return "Manual"
        case .fitPage: return "Fit Page"
        case .fitWidth: return "Fit Width"
        }
    }
}
