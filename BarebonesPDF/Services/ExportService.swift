import AppKit
import PDFKit
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case noPagesSelected
    case pageUnavailable
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .noPagesSelected: return "Select one or more pages to export."
        case .pageUnavailable: return "A selected page is no longer available."
        case .imageEncodingFailed: return "The page image could not be created."
        }
    }
}

enum PageImageFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var contentType: UTType { self == .png ? .png : .jpeg }
    var fileExtension: String { self == .png ? "png" : "jpg" }
}

enum ExportService {
    static func document(from source: PDFDocument, indexes: IndexSet) throws -> PDFDocument {
        guard !indexes.isEmpty else { throw ExportError.noPagesSelected }
        let result = PDFDocument()
        for index in indexes {
            guard let page = source.page(at: index) else { throw ExportError.pageUnavailable }
            result.insert(try PageEditingEngine.copy(page: page), at: result.pageCount)
        }
        return result
    }

    static func writeSelectedPages(from source: PDFDocument, indexes: IndexSet, to url: URL) throws {
        let result = try document(from: source, indexes: indexes)
        try SafeSaveService.write(document: result, to: url)
    }

    static func imageData(for page: PDFPage, format: PageImageFormat, scale: CGFloat = 2) throws -> Data {
        let pageBounds = page.bounds(for: .mediaBox)
        let pixelSize = CGSize(width: max(1, pageBounds.width * scale), height: max(1, pageBounds.height * scale))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width.rounded(.up)),
            pixelsHigh: Int(pixelSize.height.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
            throw ExportError.imageEncodingFailed
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: pixelSize))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        let data: Data?
        switch format {
        case .png:
            data = bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
        guard let data else { throw ExportError.imageEncodingFailed }
        return data
    }
}
