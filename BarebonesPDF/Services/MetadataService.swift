import Foundation
import PDFKit

enum MetadataService {
    static func apply(_ metadata: EditableMetadata, to document: PDFDocument) {
        var attributes = document.documentAttributes ?? [:]
        set(metadata.title, key: .titleAttribute, in: &attributes)
        set(metadata.author, key: .authorAttribute, in: &attributes)
        set(metadata.subject, key: .subjectAttribute, in: &attributes)
        let keywords = metadata.keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if keywords.isEmpty {
            attributes.removeValue(forKey: PDFDocumentAttribute.keywordsAttribute)
        } else {
            attributes[PDFDocumentAttribute.keywordsAttribute] = keywords
        }
        attributes[PDFDocumentAttribute.modificationDateAttribute] = Date()
        document.documentAttributes = attributes
    }

    private static func set(
        _ value: String,
        key: PDFDocumentAttribute,
        in attributes: inout [PDFDocumentAttribute: Any]
    ) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            attributes.removeValue(forKey: key)
        } else {
            attributes[key] = trimmed
        }
    }
}
