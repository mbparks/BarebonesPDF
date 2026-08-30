import CoreGraphics
import Foundation
import CPDFium

struct PDFTextEditDraft: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let objects: [PDFTextObjectDraft]
    let originalText: String
}

struct PDFTextObjectDraft {
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
        overlapping selectionRegions: [CGRect]
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
                guard selectionRegions.contains(where: { bounds.intersects($0.insetBy(dx: -4, dy: -3)) }),
                      let text = objectText(object, textPage: textPage),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                candidates.append((index, text, bounds))
            }

            let selected = candidates
                .filter { candidate in
                    selectionRegions.contains { intersectionArea(candidate.bounds, $0) > 0 }
                }
                .sorted(by: readingOrder)
            guard !selected.isEmpty else {
                throw PDFTextEditingError.noEditableText
            }
            let objects = selected.map {
                PDFTextObjectDraft(objectIndex: $0.index, originalText: $0.text, bounds: $0.bounds)
            }
            return PDFTextEditDraft(
                pageIndex: pageIndex,
                objects: objects,
                originalText: joinedText(from: objects)
            )
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func readingOrder(
        _ lhs: (index: Int, text: String, bounds: CGRect),
        _ rhs: (index: Int, text: String, bounds: CGRect)
    ) -> Bool {
        let tolerance = max(2, min(lhs.bounds.height, rhs.bounds.height) * 0.45)
        if abs(lhs.bounds.midY - rhs.bounds.midY) <= tolerance {
            return lhs.bounds.minX < rhs.bounds.minX
        }
        return lhs.bounds.midY > rhs.bounds.midY
    }

    private static func joinedText(from objects: [PDFTextObjectDraft]) -> String {
        var result = ""
        var previous: PDFTextObjectDraft?
        for object in objects {
            if let previous {
                let tolerance = max(2, min(previous.bounds.height, object.bounds.height) * 0.45)
                result += abs(previous.bounds.midY - object.bounds.midY) <= tolerance ? " " : "\n"
            }
            result += object.originalText
            previous = object
        }
        return result
    }

    private static func replacementSegments(_ text: String, capacities: [Int]) -> [String] {
        guard capacities.count > 1 else { return [text] }
        var words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var result: [String] = []
        for capacity in capacities.dropLast() {
            var line = ""
            while let word = words.first {
                let candidate = line.isEmpty ? word : "\(line) \(word)"
                if !line.isEmpty && candidate.count > capacity { break }
                line = candidate
                words.removeFirst()
                if line.count >= capacity { break }
            }
            result.append(line)
        }
        result.append(words.joined(separator: " "))
        return result
    }

    static func replaceText(in data: Data, draft: PDFTextEditDraft, with replacement: String) throws -> Data {
        guard !replacement.isEmpty else { throw PDFTextEditingError.emptyReplacement }
        _ = PDFiumRuntime.shared
        return try withDocument(data) { document in
            guard let page = FPDF_LoadPage(document, Int32(draft.pageIndex)) else {
                throw PDFTextEditingError.pageUnavailable
            }
            defer { FPDF_ClosePage(page) }
            guard let textPage = FPDFText_LoadPage(page) else {
                throw PDFTextEditingError.textChanged
            }
            defer { FPDFText_ClosePage(textPage) }

            var pageObjects: [FPDF_PAGEOBJECT] = []
            for item in draft.objects {
                guard let object = FPDFPage_GetObject(page, Int32(item.objectIndex)),
                      FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_TEXT,
                      objectText(object, textPage: textPage) == item.originalText else {
                    throw PDFTextEditingError.textChanged
                }
                pageObjects.append(object)
            }

            let segments = replacementSegments(
                replacement,
                capacities: draft.objects.map { max(1, $0.originalText.count) }
            )
            for (object, segment) in zip(pageObjects, segments) {
                var utf16 = Array(segment.utf16)
                utf16.append(0)
                let changed = utf16.withUnsafeBufferPointer { buffer in
                    FPDFText_SetText(object, buffer.baseAddress)
                }
                guard changed != 0 else { throw PDFTextEditingError.unsupportedReplacement }
            }
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
