import AppKit
import PDFKit

struct PDFTextEditPreview {
    let sourceData: Data
    let editedData: Data
    let beforeImage: NSImage
    let afterImage: NSImage
    let diagnostics: PDFTextEditDiagnostics
    let validationSummary: [String]
    let validationWarnings: [String]
}

enum TextEditPreparationOutcome {
    case success(PDFTextEditPreview)
    case failure(String)
}

enum TextEditValidationService {
    static func preparePreview(
        before sourceData: Data,
        result: PDFTextEditResult,
        draft: PDFTextEditDraft,
        replacement: String
    ) throws -> PDFTextEditPreview {
        guard let beforeDocument = PDFDocument(data: sourceData),
              let afterDocument = PDFDocument(data: result.data) else {
            throw PDFTextEditingError.validationFailed("The generated file could not be reopened.")
        }
        try validateStructure(before: beforeDocument, after: afterDocument)
        guard let beforePage = beforeDocument.page(at: draft.pageIndex),
              let afterPage = afterDocument.page(at: draft.pageIndex) else {
            throw PDFTextEditingError.validationFailed("The edited page could not be reopened.")
        }

        let expected = normalizedText(replacement)
        let extracted = normalizedText(afterPage.string ?? "")
        guard !expected.isEmpty, extracted.contains(expected) else {
            throw PDFTextEditingError.validationFailed("Round-trip text extraction did not reproduce the requested replacement.")
        }

        let beforeRender = try render(beforePage)
        let afterRender = try render(afterPage, matching: beforeRender)
        let mediaBox = beforePage.bounds(for: .mediaBox)
        let permittedRegions = draft.objects.map {
            $0.bounds
                .offsetBy(dx: mediaBox.minX, dy: mediaBox.minY)
                .insetBy(dx: -10, dy: -6)
        }
        let unexpectedPixels = try changedPixelsOutside(
            permittedRegions,
            before: beforeRender,
            after: afterRender
        )
        let threshold = max(120, (beforeRender.width * beforeRender.height) / 20_000)
        var warnings = result.diagnostics.geometryWarnings
        if unexpectedPixels > threshold {
            warnings.append(
                "The render comparison found \(unexpectedPixels) changed pixels outside the expected edit mask. Inspect the before/after preview before applying."
            )
        }

        return PDFTextEditPreview(
            sourceData: sourceData,
            editedData: result.data,
            beforeImage: beforeRender.image,
            afterImage: afterRender.image,
            diagnostics: result.diagnostics,
            validationSummary: [
                "Page count, dimensions, rotation, and annotation counts are unchanged.",
                "Replacement text passed save-and-reopen extraction verification.",
                "Before/after rendered pages were generated for visual review."
            ],
            validationWarnings: warnings
        )
    }

    private static func validateStructure(before: PDFDocument, after: PDFDocument) throws {
        guard before.pageCount == after.pageCount else {
            throw PDFTextEditingError.validationFailed("The page count changed.")
        }
        for index in 0..<before.pageCount {
            guard let oldPage = before.page(at: index), let newPage = after.page(at: index) else {
                throw PDFTextEditingError.validationFailed("Page \(index + 1) became unavailable.")
            }
            let oldBounds = oldPage.bounds(for: .mediaBox)
            let newBounds = newPage.bounds(for: .mediaBox)
            guard abs(oldBounds.width - newBounds.width) < 0.01,
                  abs(oldBounds.height - newBounds.height) < 0.01,
                  oldPage.rotation == newPage.rotation else {
                throw PDFTextEditingError.validationFailed("Page \(index + 1) dimensions or rotation changed.")
            }
            guard oldPage.annotations.count == newPage.annotations.count else {
                throw PDFTextEditingError.validationFailed("Page \(index + 1) annotation count changed.")
            }
        }
    }

    private static func normalizedText(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private struct RenderedPage {
        let image: NSImage
        let context: CGContext
        let bounds: CGRect
        let scale: CGFloat
        let width: Int
        let height: Int
    }

    private static func render(_ page: PDFPage, matching other: RenderedPage? = nil) throws -> RenderedPage {
        let bounds = page.bounds(for: .mediaBox)
        let width = other?.width ?? 900
        let scale = other?.scale ?? (CGFloat(width) / max(1, bounds.width))
        let height = other?.height ?? max(1, Int((bounds.height * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PDFTextEditingError.validationFailed("The page preview could not be rendered.")
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        guard let cgImage = context.makeImage() else {
            throw PDFTextEditingError.validationFailed("The page preview could not be created.")
        }
        return RenderedPage(
            image: NSImage(cgImage: cgImage, size: bounds.size),
            context: context,
            bounds: bounds,
            scale: scale,
            width: width,
            height: height
        )
    }

    private static func changedPixelsOutside(
        _ permittedRegions: [CGRect],
        before: RenderedPage,
        after: RenderedPage
    ) throws -> Int {
        guard before.width == after.width, before.height == after.height,
              let beforeData = before.context.data,
              let afterData = after.context.data,
              let mask = CGContext(
                data: nil,
                width: before.width,
                height: before.height,
                bitsPerComponent: 8,
                bytesPerRow: before.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let maskData = mask.data else {
            throw PDFTextEditingError.validationFailed("The visual comparison could not be completed.")
        }
        mask.setFillColor(NSColor.white.cgColor)
        mask.saveGState()
        mask.scaleBy(x: before.scale, y: before.scale)
        mask.translateBy(x: -before.bounds.minX, y: -before.bounds.minY)
        permittedRegions.forEach(mask.fill)
        mask.restoreGState()

        let oldBytes = beforeData.assumingMemoryBound(to: UInt8.self)
        let newBytes = afterData.assumingMemoryBound(to: UInt8.self)
        let maskBytes = maskData.assumingMemoryBound(to: UInt8.self)
        var changed = 0
        for pixel in 0..<(before.width * before.height) where maskBytes[pixel * 4] == 0 {
            let offset = pixel * 4
            let delta = max(
                abs(Int(oldBytes[offset]) - Int(newBytes[offset])),
                abs(Int(oldBytes[offset + 1]) - Int(newBytes[offset + 1])),
                abs(Int(oldBytes[offset + 2]) - Int(newBytes[offset + 2]))
            )
            if delta > 16 { changed += 1 }
        }
        return changed
    }
}
