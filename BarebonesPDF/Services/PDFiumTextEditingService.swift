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

struct PDFTextEditDiagnostics {
    let originalFontNames: [String]
    let replacementFontNames: [String]
    let originalBounds: [CGRect]
    let replacementBounds: [CGRect]
    let usedStandardFontSubstitution: Bool
}

struct PDFTextEditResult {
    let data: Data
    let diagnostics: PDFTextEditDiagnostics
}

enum PDFTextEditingError: LocalizedError {
    case unreadableDocument
    case pageUnavailable
    case noEditableText
    case textChanged
    case emptyReplacement
    case unsupportedReplacement
    case unsafeLayout(String)
    case validationFailed(String)
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
        case .unsafeLayout(let reason):
            return "The edit was blocked because it could damage the page layout. \(reason)"
        case .validationFailed(let reason):
            return "The edited PDF did not pass validation. \(reason) The original document was not changed."
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

    private struct TextObjectStyle {
        let matrix: FS_MATRIX
        let fontSize: Float
        let fill: (UInt32, UInt32, UInt32, UInt32)
        let stroke: (UInt32, UInt32, UInt32, UInt32)
        let renderMode: FPDF_TEXT_RENDERMODE
        let standardFontName: String
    }

    private static func replaceWithStandardFonts(
        document: FPDF_DOCUMENT,
        page: FPDF_PAGE,
        oldObjects: [FPDF_PAGEOBJECT],
        segments: [String]
    ) throws -> (bounds: [CGRect], originalFonts: [String], replacementFonts: [String]) {
        var replacements: [FPDF_PAGEOBJECT] = []
        var replacementBounds: [CGRect] = []
        var originalFonts: [String] = []
        var replacementFonts: [String] = []
        defer { replacements.forEach(FPDFPageObj_Destroy) }

        for (oldObject, segment) in zip(oldObjects, segments) {
            let style = try textStyle(of: oldObject)
            originalFonts.append(baseFontName(for: oldObject))
            replacementFonts.append(style.standardFontName)
            let font = style.standardFontName.withCString { name in
                FPDFText_LoadStandardFont(document, name)
            }
            guard let font else { throw PDFTextEditingError.unsupportedReplacement }
            guard let replacement = FPDFPageObj_CreateTextObj(document, font, style.fontSize) else {
                FPDFFont_Close(font)
                throw PDFTextEditingError.unsupportedReplacement
            }
            FPDFFont_Close(font)
            var matrix = style.matrix
            guard setText(segment, on: replacement),
                  FPDFPageObj_SetMatrix(replacement, &matrix) != 0,
                  FPDFPageObj_SetFillColor(replacement, style.fill.0, style.fill.1, style.fill.2, style.fill.3) != 0,
                  FPDFPageObj_SetStrokeColor(replacement, style.stroke.0, style.stroke.1, style.stroke.2, style.stroke.3) != 0,
                  FPDFTextObj_SetTextRenderMode(replacement, style.renderMode) != 0 else {
                FPDFPageObj_Destroy(replacement)
                throw PDFTextEditingError.unsupportedReplacement
            }
            replacementBounds.append(pageObjectBounds(replacement) ?? .null)
            replacements.append(replacement)
        }

        for oldObject in oldObjects {
            guard FPDFPage_RemoveObject(page, oldObject) != 0 else {
                throw PDFTextEditingError.saveFailed
            }
            FPDFPageObj_Destroy(oldObject)
        }
        while !replacements.isEmpty {
            let replacement = replacements.removeFirst()
            guard FPDFPage_InsertObject(page, replacement) != 0 else {
                throw PDFTextEditingError.saveFailed
            }
        }
        return (replacementBounds, originalFonts, replacementFonts)
    }

    private static func textStyle(of object: FPDF_PAGEOBJECT) throws -> TextObjectStyle {
        var matrix = FS_MATRIX(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)
        var size: Float = 12
        var fillR: UInt32 = 0, fillG: UInt32 = 0, fillB: UInt32 = 0, fillA: UInt32 = 255
        var strokeR: UInt32 = 0, strokeG: UInt32 = 0, strokeB: UInt32 = 0, strokeA: UInt32 = 255
        guard FPDFPageObj_GetMatrix(object, &matrix) != 0,
              FPDFTextObj_GetFontSize(object, &size) != 0 else {
            throw PDFTextEditingError.unsupportedReplacement
        }
        _ = FPDFPageObj_GetFillColor(object, &fillR, &fillG, &fillB, &fillA)
        _ = FPDFPageObj_GetStrokeColor(object, &strokeR, &strokeG, &strokeB, &strokeA)
        return TextObjectStyle(
            matrix: matrix,
            fontSize: size,
            fill: (fillR, fillG, fillB, fillA),
            stroke: (strokeR, strokeG, strokeB, strokeA),
            renderMode: FPDFTextObj_GetTextRenderMode(object),
            standardFontName: standardFontName(for: object)
        )
    }

    private static func standardFontName(for object: FPDF_PAGEOBJECT) -> String {
        let sourceName = baseFontName(for: object).lowercased()
        guard !sourceName.isEmpty else { return "Helvetica" }
        let isBold = sourceName.contains("bold") || sourceName.contains("black") || sourceName.contains("demi")
        let isItalic = sourceName.contains("italic") || sourceName.contains("oblique")
        let family = sourceName.contains("times") ? "Times" : (sourceName.contains("courier") ? "Courier" : "Helvetica")
        if family == "Times" {
            if isBold && isItalic { return "Times-BoldItalic" }
            if isBold { return "Times-Bold" }
            if isItalic { return "Times-Italic" }
            return "Times-Roman"
        }
        if isBold && isItalic { return "\(family)-BoldOblique" }
        if isBold { return "\(family)-Bold" }
        if isItalic { return "\(family)-Oblique" }
        return family
    }

    private static func baseFontName(for object: FPDF_PAGEOBJECT) -> String {
        guard let font = FPDFTextObj_GetFont(object) else { return "" }
        let length = FPDFFont_GetBaseFontName(font, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(1, length))
        if length > 0 { _ = FPDFFont_GetBaseFontName(font, &buffer, length) }
        return String(cString: buffer)
    }

    private static func setText(_ text: String, on object: FPDF_PAGEOBJECT) -> Bool {
        var utf16 = Array(text.utf16)
        utf16.append(0)
        return utf16.withUnsafeBufferPointer { buffer in
            FPDFText_SetText(object, buffer.baseAddress) != 0
        }
    }

    static func replaceText(in data: Data, draft: PDFTextEditDraft, with replacement: String) throws -> PDFTextEditResult {
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
            var textPageIsOpen = true
            defer { if textPageIsOpen { FPDFText_ClosePage(textPage) } }

            var pageObjects: [FPDF_PAGEOBJECT] = []
            for item in draft.objects {
                guard let object = FPDFPage_GetObject(page, Int32(item.objectIndex)),
                      FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_TEXT,
                      objectText(object, textPage: textPage) == item.originalText else {
                    throw PDFTextEditingError.textChanged
                }
                pageObjects.append(object)
            }
            FPDFText_ClosePage(textPage)
            textPageIsOpen = false

            let segments = replacementSegments(
                replacement,
                capacities: draft.objects.map { max(1, $0.originalText.count) }
            )
            let isBasicLatin = replacement.unicodeScalars.allSatisfy {
                $0.value == 9 || $0.value == 10 || $0.value == 13 || (32...126).contains($0.value)
            }
            let replacementBounds: [CGRect]
            let originalFonts: [String]
            let replacementFonts: [String]
            if isBasicLatin {
                let details = try replaceWithStandardFonts(
                    document: document,
                    page: page,
                    oldObjects: pageObjects,
                    segments: segments
                )
                replacementBounds = details.bounds
                originalFonts = details.originalFonts
                replacementFonts = details.replacementFonts
            } else {
                originalFonts = pageObjects.map(baseFontName)
                replacementFonts = originalFonts
                for (object, segment) in zip(pageObjects, segments) {
                    guard setText(segment, on: object) else {
                        throw PDFTextEditingError.unsupportedReplacement
                    }
                }
                replacementBounds = pageObjects.map { pageObjectBounds($0) ?? .null }
            }
            try validateGeometry(original: draft.objects.map(\.bounds), replacement: replacementBounds)
            guard FPDFPage_GenerateContent(page) != 0 else { throw PDFTextEditingError.saveFailed }
            return PDFTextEditResult(
                data: try save(document),
                diagnostics: PDFTextEditDiagnostics(
                    originalFontNames: originalFonts,
                    replacementFontNames: replacementFonts,
                    originalBounds: draft.objects.map(\.bounds),
                    replacementBounds: replacementBounds,
                    usedStandardFontSubstitution: isBasicLatin
                )
            )
        }
    }

    private static func pageObjectBounds(_ object: FPDF_PAGEOBJECT) -> CGRect? {
        var left: Float = 0, bottom: Float = 0, right: Float = 0, top: Float = 0
        guard FPDFPageObj_GetBounds(object, &left, &bottom, &right, &top) != 0 else { return nil }
        return CGRect(x: CGFloat(left), y: CGFloat(bottom), width: CGFloat(right - left), height: CGFloat(top - bottom))
    }

    private static func validateGeometry(original: [CGRect], replacement: [CGRect]) throws {
        guard original.count == replacement.count else {
            throw PDFTextEditingError.unsafeLayout("The generated line count changed unexpectedly.")
        }
        for (index, pair) in zip(original, replacement).enumerated() {
            let old = pair.0
            let new = pair.1
            if new.isNull || new.isEmpty { continue }
            let horizontalTolerance = max(4, old.width * 0.05)
            let verticalTolerance = max(2, old.height * 0.20)
            let permitted = old.insetBy(dx: -horizontalTolerance, dy: -verticalTolerance)
            guard permitted.contains(new) else {
                throw PDFTextEditingError.unsafeLayout("Replacement line \(index + 1) extends beyond its original text region.")
            }
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
