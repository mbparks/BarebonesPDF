import AppKit
import PDFKit

enum PageEditingError: LocalizedError {
    case noPagesSelected
    case copyFailed
    case blankPageFailed
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .noPagesSelected: return "Select at least one page first."
        case .copyFailed: return "One or more pages could not be copied. The document was not changed."
        case .blankPageFailed: return "A blank page could not be created."
        case .invalidDestination: return "The requested page position is no longer available."
        }
    }
}

enum PageEditingEngine {
    static func rotate(document: PDFDocument, indexes: IndexSet, degrees: Int) throws {
        guard !indexes.isEmpty else { throw PageEditingError.noPagesSelected }
        for index in indexes where index < document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let rotation = (page.rotation + degrees) % 360
            page.rotation = rotation < 0 ? rotation + 360 : rotation
        }
    }

    @discardableResult
    static func duplicate(document: PDFDocument, indexes: IndexSet) throws -> IndexSet {
        guard !indexes.isEmpty else { throw PageEditingError.noPagesSelected }
        let copies = try indexes.compactMap { index -> PDFPage? in
            guard let page = document.page(at: index) else { return nil }
            return try copy(page: page)
        }
        guard copies.count == indexes.count else { throw PageEditingError.copyFailed }

        let insertionIndex = min((indexes.last ?? document.pageCount - 1) + 1, document.pageCount)
        for (offset, page) in copies.enumerated() {
            document.insert(page, at: insertionIndex + offset)
        }
        return IndexSet(integersIn: insertionIndex..<(insertionIndex + copies.count))
    }

    static func delete(document: PDFDocument, indexes: IndexSet) throws {
        guard !indexes.isEmpty else { throw PageEditingError.noPagesSelected }
        for index in indexes.sorted(by: >) where index < document.pageCount {
            document.removePage(at: index)
        }
    }

    @discardableResult
    static func insert(document: PDFDocument, pages: [PDFPage], at requestedIndex: Int) throws -> IndexSet {
        let index = min(max(0, requestedIndex), document.pageCount)
        for (offset, page) in pages.enumerated() {
            document.insert(page, at: index + offset)
        }
        return IndexSet(integersIn: index..<(index + pages.count))
    }

    @discardableResult
    static func insertBlank(document: PDFDocument, at index: Int, size: CGSize) throws -> IndexSet {
        guard let page = makeBlankPage(size: size) else { throw PageEditingError.blankPageFailed }
        return try insert(document: document, pages: [page], at: index)
    }

    @discardableResult
    static func move(document: PDFDocument, indexes: IndexSet, to requestedDestination: Int) throws -> IndexSet {
        guard !indexes.isEmpty else { throw PageEditingError.noPagesSelected }
        guard requestedDestination >= 0 && requestedDestination <= document.pageCount else {
            throw PageEditingError.invalidDestination
        }

        let pages = indexes.compactMap { document.page(at: $0) }
        guard pages.count == indexes.count else { throw PageEditingError.copyFailed }
        let removedBeforeDestination = indexes.filter { $0 < requestedDestination }.count
        let adjustedDestination = requestedDestination - removedBeforeDestination

        for index in indexes.sorted(by: >) {
            document.removePage(at: index)
        }
        for (offset, page) in pages.enumerated() {
            document.insert(page, at: adjustedDestination + offset)
        }
        return IndexSet(integersIn: adjustedDestination..<(adjustedDestination + pages.count))
    }

    static func makeBlankPage(size: CGSize) -> PDFPage? {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return PDFPage(image: image)
    }

    static func copy(page: PDFPage) throws -> PDFPage {
        guard let copiedPage = page.copy() as? PDFPage else {
            throw PageEditingError.copyFailed
        }
        return copiedPage
    }
}
