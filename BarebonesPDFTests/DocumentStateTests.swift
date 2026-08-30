import PDFKit
import XCTest
@testable import BarebonesPDF

final class DocumentStateTests: XCTestCase {
    func testMetadataRoundTrip() throws {
        let document = makeDocument()
        var metadata = EditableMetadata()
        metadata.title = "Workshop Drawing"
        metadata.author = "Green Shoe Garage"
        metadata.subject = "Fixture"
        metadata.keywords = "fixture, test, drawing"

        MetadataService.apply(metadata, to: document)
        let encoded = try XCTUnwrap(document.dataRepresentation())
        let reopened = try XCTUnwrap(PDFDocument(data: encoded))
        let restored = EditableMetadata(document: reopened)

        XCTAssertEqual(restored.title, metadata.title)
        XCTAssertEqual(restored.author, metadata.author)
        XCTAssertEqual(restored.subject, metadata.subject)
        XCTAssertEqual(restored.keywords, metadata.keywords)
    }

    func testStateTracksPageMutationsAndUndo() throws {
        let document = makeDocument()
        let state = DocumentState(document: document, fileURL: nil)
        let undoManager = UndoManager()
        state.undoManager = undoManager
        state.selectedPageIndexes = IndexSet(integer: 0)

        state.duplicateSelectedPages()
        XCTAssertEqual(state.pageCount, 2)
        XCTAssertTrue(state.isEdited)

        undoManager.undo()
        XCTAssertEqual(state.pageCount, 1)

        undoManager.redo()
        XCTAssertEqual(state.pageCount, 2)
    }

    func testSafeSaveLeavesReadablePDF() throws {
        let document = makeDocument()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("saved.pdf")

        try SafeSaveService.write(document: document, to: destination)
        let reopened = PDFDocument(url: destination)
        XCTAssertEqual(reopened?.pageCount, 1)
    }

    private func makeDocument() -> PDFDocument {
        let document = PDFDocument()
        document.insert(PageEditingEngine.makeBlankPage(size: CGSize(width: 612, height: 792))!, at: 0)
        return document
    }
}
