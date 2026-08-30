import AppKit
import PDFKit
import XCTest
@testable import BarebonesPDF

final class PageEditingEngineTests: XCTestCase {
    func testInsertDuplicateMoveRotateAndDeletePages() throws {
        let document = makeDocument(pageCount: 3)
        XCTAssertEqual(document.pageCount, 3)

        let inserted = try PageEditingEngine.insertBlank(
            document: document,
            at: 1,
            size: CGSize(width: 400, height: 600)
        )
        XCTAssertEqual(inserted, IndexSet(integer: 1))
        XCTAssertEqual(document.pageCount, 4)

        let duplicates = try PageEditingEngine.duplicate(document: document, indexes: IndexSet([0, 2]))
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertEqual(document.pageCount, 6)

        try PageEditingEngine.rotate(document: document, indexes: IndexSet(integer: 0), degrees: 90)
        XCTAssertEqual(document.page(at: 0)?.rotation, 90)

        let moved = try PageEditingEngine.move(document: document, indexes: IndexSet([0, 1]), to: 6)
        XCTAssertEqual(moved, IndexSet(integersIn: 4..<6))
        XCTAssertEqual(document.pageCount, 6)

        try PageEditingEngine.delete(document: document, indexes: moved)
        XCTAssertEqual(document.pageCount, 4)
    }

    func testPageCopyPreservesAnnotations() throws {
        let page = try XCTUnwrap(PageEditingEngine.makeBlankPage(size: CGSize(width: 200, height: 300)))
        let note = PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 30, height: 30),
            forType: .text,
            withProperties: nil
        )
        note.contents = "Copied note"
        page.addAnnotation(note)

        let copy = try PageEditingEngine.copy(page: page)
        XCTAssertEqual(copy.annotations.count, 1)
        XCTAssertEqual(copy.annotations.first?.contents, "Copied note")
        XCTAssertFalse(copy === page)
    }

    func testExtractCreatesIndependentDocument() throws {
        let source = makeDocument(pageCount: 4)
        let result = try ExportService.document(from: source, indexes: IndexSet([1, 3]))
        XCTAssertEqual(result.pageCount, 2)

        result.removePage(at: 0)
        XCTAssertEqual(source.pageCount, 4)
        XCTAssertEqual(result.pageCount, 1)
    }

    private func makeDocument(pageCount: Int) -> PDFDocument {
        let document = PDFDocument()
        for _ in 0..<pageCount {
            let page = PageEditingEngine.makeBlankPage(size: CGSize(width: 612, height: 792))!
            document.insert(page, at: document.pageCount)
        }
        return document
    }
}
