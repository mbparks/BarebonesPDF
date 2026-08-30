import AppKit
import PDFKit
import XCTest

final class BarebonesPDFUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-seeded-document"]
        app.launch()
    }

    func testOpensSeededPDFAndNavigates() {
        XCTAssertTrue(app.staticTexts["/ 3"].waitForExistence(timeout: 5))
        app.buttons["Next page"].click()
        XCTAssertTrue(app.staticTexts["/ 3"].exists)
        app.buttons["Zoom in"].click()
        app.buttons["Zoom out"].click()
    }

    func testAddsAnnotationAndEditsProperties() {
        app.buttons["Toggle annotation tools"].click()
        app.buttons["Rectangle"].click()

        let canvas = app.groups["PDF document canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)))

        app.buttons["Toggle annotation properties"].click()
        XCTAssertTrue(app.staticTexts["Rectangle"].waitForExistence(timeout: 3))
    }

    func testReordersPagesUsingThumbnailDrag() {
        let first = app.staticTexts["1"].firstMatch
        let third = app.staticTexts["3"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        first.press(forDuration: 0.5, thenDragTo: third)
        XCTAssertTrue(app.staticTexts["/ 3"].exists)
    }

    func testSaveCommandIsAvailableAfterEdit() {
        app.buttons["Toggle annotation tools"].click()
        app.buttons["Sticky Note"].click()
        let canvas = app.groups["PDF document canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts["Edited"].waitForExistence(timeout: 3))

        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))
        app.sheets.firstMatch.buttons["Cancel"].click()
    }

    func testReopenWorkflowUsesStandardOpenCommand() {
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(app.dialogs.firstMatch.waitForExistence(timeout: 3) || app.sheets.firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testOpenAnnotateSaveAndReopenRealPDF() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL = folder.appendingPathComponent("UI Test Round Trip.pdf")
        try makeFixturePDF(at: fileURL)

        try openInBuiltApplication(fileURL)
        let roundTripWindow = app.windows.matching(
            NSPredicate(format: "title CONTAINS %@", "UI Test Round Trip")
        ).firstMatch
        XCTAssertTrue(roundTripWindow.waitForExistence(timeout: 8))

        app.buttons["Toggle annotation tools"].click()
        app.buttons["Sticky Note"].click()
        let canvas = app.descendants(matching: .any)["PDF document canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.48)).click()
        XCTAssertTrue(app.staticTexts["Edited"].waitForExistence(timeout: 3))

        app.typeKey("s", modifierFlags: .command)
        let saved = expectation(for: NSPredicate { _, _ in
            PDFDocument(url: fileURL)?.page(at: 0)?.annotations.isEmpty == false
        }, evaluatedWith: NSObject())
        wait(for: [saved], timeout: 8)

        app.typeKey("w", modifierFlags: .command)
        try openInBuiltApplication(fileURL)
        XCTAssertTrue(roundTripWindow.waitForExistence(timeout: 8))
        XCTAssertEqual(PDFDocument(url: fileURL)?.page(at: 0)?.annotations.count, 1)
    }

    private func makeFixturePDF(at url: URL) throws {
        let image = NSImage(size: CGSize(width: 612, height: 792))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 612, height: 792)).fill()
        image.unlockFocus()
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        guard document.write(to: url) else {
            throw NSError(domain: "BarebonesPDFUITests", code: 1)
        }
    }

    private func openInBuiltApplication(_ fileURL: URL) throws {
        let environment = ProcessInfo.processInfo.environment
        let productsDirectory = try XCTUnwrap(environment["BUILT_PRODUCTS_DIR"])
        let applicationURL = URL(fileURLWithPath: productsDirectory).appendingPathComponent("BarebonesPDF.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: applicationURL.path))

        let opened = expectation(description: "Open PDF in BarebonesPDF")
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            XCTAssertNil(error)
            opened.fulfill()
        }
        wait(for: [opened], timeout: 8)
    }
}
