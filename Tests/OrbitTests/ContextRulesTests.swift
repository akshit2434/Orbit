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

    @MainActor
    func testAsyncCollectionDoesNotCaptureWithoutScreenshotTool() async {
        var captures = 0
        let svc = ContextService(screenshotProvider: {
            captures += 1
            return (Data([1]), .captured)
        })
        let bundle = await svc.collectForRequest(tools: [.activeAppWindow])
        XCTAssertEqual(captures, 0)
        XCTAssertNil(bundle.screenshotPNG)
        XCTAssertEqual(bundle.screenshotStatus, .notRequested)
    }

    @MainActor
    func testAsyncCollectionCapturesOnlyWhenRequested() async {
        var captures = 0
        let svc = ContextService(screenshotProvider: {
            captures += 1
            return (Data([1, 2]), .captured)
        })
        let bundle = await svc.collectForRequest(tools: [.screenshot])
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(bundle.screenshotPNG, Data([1, 2]))
        XCTAssertEqual(bundle.screenshotStatus, .captured)
        XCTAssertEqual(bundle.notes, ["screenshot-captured"])
    }

    @MainActor
    func testAsyncCollectionPreservesPermissionDeniedState() async {
        let svc = ContextService(screenshotProvider: { (nil, .permissionDenied) })
        let bundle = await svc.collectForRequest(tools: [.screenshot])
        XCTAssertNil(bundle.screenshotPNG)
        XCTAssertEqual(bundle.screenshotStatus, .permissionDenied)
        XCTAssertEqual(bundle.notes, ["screenshot-permissionDenied"])
    }
}
