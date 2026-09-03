import XCTest
@testable import Orbit

final class ContextRulesTests: XCTestCase {
    func testToolRawValues() {
        XCTAssertEqual(ContextTool.screenshot.rawValue, "screenshot")
    }

    @MainActor
    func testCollectEmptyToolsYieldsEmptyBundle() {
        let svc = ContextService()
        let bundle = svc.collect(tools: [])
        XCTAssertNil(bundle.app)
        XCTAssertNil(bundle.pastedText)
        XCTAssertNil(bundle.clipboard)
        XCTAssertNil(bundle.screenshotPNG)
        XCTAssertEqual(bundle.notes, [])
    }

    @MainActor
    func testCollectPastedTextOnlyWhenProvided() {
        let svc = ContextService()
        svc.pastedText = "hello paste"
        XCTAssertEqual(svc.collect(tools: [.pastedText]).pastedText, "hello paste")
        let empty = ContextService()
        XCTAssertNil(empty.collect(tools: [.pastedText]).pastedText)
    }

    @MainActor
    func testCollectClipboardGatedByFlag() {
        let svc = ContextService()
        svc.clipboardAllowed = false
        XCTAssertNil(svc.collect(tools: [.clipboard]).clipboard)
    }

    @MainActor
    func testCollectScreenshotAppendsNoteOnly() {
        let svc = ContextService()
        let bundle = svc.collect(tools: [.screenshot])
        XCTAssertEqual(bundle.notes, ["screenshot-requested"])
        XCTAssertNil(bundle.screenshotPNG)
    }
}
