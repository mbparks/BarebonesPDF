import SwiftUI
import UniformTypeIdentifiers
import PDFKit

enum BarebonesDocumentError: LocalizedError {
    case unreadablePDF
    case unableToEncode

    var errorDescription: String? {
        switch self {
        case .unreadablePDF:
            return "This PDF could not be opened. It may be damaged or use features this version of macOS does not support."
        case .unableToEncode:
            return "The PDF could not be prepared for saving. Your open document has not been changed."
        }
    }
}

struct BarebonesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    var pdfDocument: PDFDocument
    var changeToken = UUID()
    var identityToken = UUID()

    init() {
        pdfDocument = PDFDocument()
        if ProcessInfo.processInfo.arguments.contains("--uitest-seeded-document") {
            for _ in 0..<3 {
                if let page = PageEditingEngine.makeBlankPage(size: CGSize(width: 612, height: 792)) {
                    pdfDocument.insert(page, at: pdfDocument.pageCount)
                }
            }
        }
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let document = PDFDocument(data: data) else {
            throw BarebonesDocumentError.unreadablePDF
        }
        pdfDocument = document
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = pdfDocument.dataRepresentation() else {
            throw BarebonesDocumentError.unableToEncode
        }
        return FileWrapper(regularFileWithContents: data)
    }

    mutating func touch() {
        changeToken = UUID()
    }

    mutating func replacePDF(with document: PDFDocument) {
        pdfDocument = document
        identityToken = UUID()
        touch()
    }
}
