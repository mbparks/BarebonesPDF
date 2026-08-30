import CoreGraphics
import Foundation
import CPDFium

struct PDFTextEditDraft: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let objectIndex: Int
    let originalText: String
    let bounds: CGRect
}

enum PDFTextEditingError: LocalizedError {
    case unreadableDocument
    case pageUnavailable
    case noEditableText
    case textChanged
    case emptyReplacement
    case unsupportedReplacement
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unreadableDocument:
            return "This PDF could not be opened for text editing."
        case .pageUnavailable:
            return "That page is no longer available."
        case .noEditableText:
            return "No editable PDF text was found there. Scanned text, outlined letters, and text inside unsupported groups cannot be rewritten."
        case .textChanged:
            return "The selected text changed before it could be edited. Click it again and retry."
        case .emptyReplacement:
            return "Replacement text cannot be empty. This tool rewrites text; it does not remove content objects."
        case .unsupportedReplacement:
            return "The PDF's embedded font cannot encode part of the replacement. Try characters already used by that font."
        case .saveFailed:
            return "The rewritten PDF could not be generated. The original document was not changed."
        }
    }
}

private final class PDFiumRuntime {
    static let shared = PDFiumRuntime()
    private init() { FPDF_InitLibrary() }
}

private let pdfiumWriterLock = NSLock()
private var pdfiumWriterBuffers: [UInt: Data] = [:]

private let pdfiumWriteBlock: @convention(c) (
    UnsafeMutablePointer<FPDF_FILEWRITE_>?, UnsafeRawPointer?, UInt
) -> Int32 = { writer, bytes, count in
    guard let writer, let bytes else { return 0 }
    let key = UInt(bitPattern: writer)
    pdfiumWriterLock.lock()
    defer { pdfiumWriterLock.unlock() }
    guard pdfiumWriterBuffers[key] != nil else { return 0 }
    pdfiumWriterBuffers[key]!.append(bytes.assumingMemoryBound(to: UInt8.self), count: Int(count))
    return 1
}

enum PDFiumTextEditingService {
    static func textObject(
        in data: Data,
        pageIndex: Int,
        overlapping targetBounds: CGRect
    ) throws -> PDFTextEditDraft {
        _ = PDFiumRuntime.shared
        return try withDocument(data) { document in
            guard let page = FPDF_LoadPage(document, Int32(pageIndex)) else {
                throw PDFTextEditingError.pageUnavailable
            }
            defer { FPDF_ClosePage(page) }
            guard let textPage = FPDFText_LoadPage(page) else {
                throw PDFTextEditingError.noEditableText
            }
            defer { FPDFText_ClosePage(textPage) }

            var candidates: [(index: Int, text: String, bounds: CGRect)] = []
            for index in 0..<Int(FPDFPage_CountObjects(page)) {
                guard let object = FPDFPage_GetObject(page, Int32(index)),
                      FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_TEXT else { continue }
                var left: Float = 0
                var bottom: Float = 0
                var right: Float = 0
                var top: Float = 0
                guard FPDFPageObj_GetBounds(object, &left, &bottom, &right, &top) != 0 else { continue }
                let bounds = CGRect(x: CGFloat(left), y: CGFloat(bottom), width: CGFloat(right - left), height: CGFloat(top - bottom))
                let expandedTarget = targetBounds.insetBy(dx: -4, dy: -4)
                guard bounds.intersects(expandedTarget),
                      let text = objectText(object, textPage: textPage),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                candidates.append((index, text, bounds))
            }

            guard let match = candidates.max(by: {
                intersectionArea($0.bounds, targetBounds) < intersectionArea($1.bounds, targetBounds)
            }) else {
                throw PDFTextEditingError.noEditableText
            }
            return PDFTextEditDraft(pageIndex: pageIndex, objectIndex: match.index, originalText: match.text, bounds: match.bounds)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    static func replaceText(in data: Data, draft: PDFTextEditDraft, with replacement: String) throws -> Data {
        guard !replacement.isEmpty else { throw PDFTextEditingError.emptyReplacement }
        _ = PDFiumRuntime.shared
        return try withDocument(data) { document in
            guard let page = FPDF_LoadPage(document, Int32(draft.pageIndex)) else {
                throw PDFTextEditingError.pageUnavailable
            }
            defer { FPDF_ClosePage(page) }
            guard let object = FPDFPage_GetObject(page, Int32(draft.objectIndex)),
                  FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_TEXT,
                  let textPage = FPDFText_LoadPage(page) else {
                throw PDFTextEditingError.textChanged
            }
            defer { FPDFText_ClosePage(textPage) }
            guard objectText(object, textPage: textPage) == draft.originalText else {
                throw PDFTextEditingError.textChanged
            }

            var utf16 = Array(replacement.utf16)
            utf16.append(0)
            let changed = utf16.withUnsafeBufferPointer { buffer in
                FPDFText_SetText(object, buffer.baseAddress)
            }
            guard changed != 0 else { throw PDFTextEditingError.unsupportedReplacement }
            guard FPDFPage_GenerateContent(page) != 0 else { throw PDFTextEditingError.saveFailed }
            return try save(document)
        }
    }

    private static func withDocument<T>(_ data: Data, operation: (FPDF_DOCUMENT) throws -> T) throws -> T {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress,
                  let document = FPDF_LoadMemDocument64(base, data.count, nil) else {
                throw PDFTextEditingError.unreadableDocument
            }
            defer { FPDF_CloseDocument(document) }
            return try operation(document)
        }
    }

    private static func objectText(_ object: FPDF_PAGEOBJECT, textPage: FPDF_TEXTPAGE) -> String? {
        let byteCount = Int(FPDFTextObj_GetText(object, textPage, nil, 0))
        guard byteCount >= 2 else { return nil }
        var units = [UInt16](repeating: 0, count: byteCount / 2)
        let copied = units.withUnsafeMutableBufferPointer { buffer in
            FPDFTextObj_GetText(object, textPage, buffer.baseAddress, UInt(byteCount))
        }
        guard copied == byteCount else { return nil }
        if units.last == 0 { units.removeLast() }
        return String(decoding: units, as: UTF16.self)
    }

    private static func save(_ document: FPDF_DOCUMENT) throws -> Data {
        var writer = FPDF_FILEWRITE_(version: 1, WriteBlock: pdfiumWriteBlock)
        let key = withUnsafeMutablePointer(to: &writer) { UInt(bitPattern: $0) }
        pdfiumWriterLock.lock()
        pdfiumWriterBuffers[key] = Data()
        pdfiumWriterLock.unlock()
        defer {
            pdfiumWriterLock.lock()
            pdfiumWriterBuffers.removeValue(forKey: key)
            pdfiumWriterLock.unlock()
        }
        let succeeded = withUnsafeMutablePointer(to: &writer) {
            FPDF_SaveAsCopy(document, $0, FPDF_DWORD(FPDF_NO_INCREMENTAL))
        }
        guard succeeded != 0 else { throw PDFTextEditingError.saveFailed }
        pdfiumWriterLock.lock()
        let result = pdfiumWriterBuffers[key]
        pdfiumWriterLock.unlock()
        guard let result, !result.isEmpty else { throw PDFTextEditingError.saveFailed }
        return result
    }
}
