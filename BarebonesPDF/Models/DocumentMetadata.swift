import Foundation
import PDFKit

struct EditableMetadata: Equatable {
    var title = ""
    var author = ""
    var subject = ""
    var keywords = ""

    init() {}

    init(document: PDFDocument) {
        let attributes = document.documentAttributes ?? [:]
        title = attributes[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        author = attributes[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
        if let values = attributes[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            keywords = values.joined(separator: ", ")
        } else {
            keywords = attributes[PDFDocumentAttribute.keywordsAttribute] as? String ?? ""
        }
    }
}

struct ReadOnlyMetadata {
    let fileName: String
    let fileSize: String
    let pageCount: Int
    let pageDimensions: String
    let pdfVersion: String
    let creationDate: String
    let modificationDate: String
    let encryptionStatus: String

    init(document: PDFDocument, fileURL: URL?) {
        let attributes = document.documentAttributes ?? [:]
        fileName = fileURL?.lastPathComponent ?? "Unsaved document"
        if let url = fileURL,
           let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize {
            fileSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        } else {
            fileSize = "—"
        }
        pageCount = document.pageCount
        if let page = document.page(at: 0) {
            let size = page.bounds(for: .mediaBox).size
            pageDimensions = String(format: "%.1f × %.1f pt", size.width, size.height)
        } else {
            pageDimensions = "—"
        }
        pdfVersion = "PDF \(document.majorVersion).\(document.minorVersion)"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        creationDate = (attributes[PDFDocumentAttribute.creationDateAttribute] as? Date).map(formatter.string) ?? "—"
        modificationDate = (attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date).map(formatter.string) ?? "—"
        if document.isLocked {
            encryptionStatus = "Encrypted and locked"
        } else if document.isEncrypted {
            encryptionStatus = "Encrypted and unlocked"
        } else {
            encryptionStatus = "Not encrypted"
        }
    }
}
