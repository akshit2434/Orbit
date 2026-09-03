import XCTest
@testable import Orbit

final class SurfaceTests: XCTestCase {
    func testSizeTable() {
        XCTAssertEqual(surfaceSize(.orb), NSSize(width: 80, height: 92))
        XCTAssertEqual(surfaceSize(.voice), NSSize(width: 218, height: 76))
        XCTAssertEqual(surfaceSize(.thinking), NSSize(width: 250, height: 80))
        XCTAssertEqual(surfaceSize(.output), NSSize(width: 250, height: 120))
        XCTAssertEqual(surfaceSize(.card), NSSize(width: 320, height: 400))
        XCTAssertEqual(surfaceSize(.history), NSSize(width: 320, height: 400))
    }
    func testSideFollowsNearestEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(expansionSide(anchorX: 950, anchorY: 400, screen: screen), .left)
        XCTAssertEqual(expansionSide(anchorX: 50, anchorY: 400, screen: screen), .right)
        XCTAssertEqual(expansionSide(anchorX: 500, anchorY: 750, screen: screen), .below)
        XCTAssertEqual(expansionSide(anchorX: 500, anchorY: 50, screen: screen), .above)
    }
    func testAnchorRoundTrip() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        XCTAssertNil(AnchorStore.load(base: base))
        AnchorStore.save(PanelAnchor(maxX: 1236, midY: 554), base: base)
        XCTAssertEqual(AnchorStore.load(base: base), PanelAnchor(maxX: 1236, midY: 554))
    }
    func testWorkedString() {
        XCTAssertEqual(workedString(elapsed: 3), "Worked for 3s")
        XCTAssertEqual(workedString(elapsed: 64), "Worked for 1m 4s")
    }
    func testSnapTargetsNearestEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let near = NSRect(x: 900, y: 400, width: 80, height: 92)
        let p = snapTarget(current: near, screen: screen)
        XCTAssertEqual(p.x, 1000 - 80 - 12, accuracy: 0.5)
    }
    @MainActor
    func testEndDragDefersPersistToSnapCompletion() {
        let svc = ContextService()
        let client = OpenRouterClient(
            config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(
            isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        var snapCount = 0
        var persistCount = 0
        model.snapPanel = { snapCount += 1 }
        model.persistPosition = { persistCount += 1 }
        model.drag(to: CGSize(width: 10, height: 5))
        model.endDrag()
        XCTAssertEqual(snapCount, 1)
        XCTAssertEqual(
            persistCount, 0,
            "endDrag must not persist pre-snap frame; persist belongs in snap completion")
    }
    func testPlacementAboveBelowClampsXToScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let anchor = PanelAnchor(maxX: 92, midY: 400)
        let size = NSSize(width: 320, height: 400)
        for side: ExpansionSide in [.above, .below, .left] {
            let p = placementOrigin(anchor: anchor, size: size, side: side, screen: screen)
            XCTAssertEqual(p.x, 12, accuracy: 0.5, "side \(side) must clamp x on-screen")
        }
    }
    func testResizeAboveBelowClampsXToScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let current = NSRect(x: 12, y: 400, width: 80, height: 92)
        let newSize = NSSize(width: 320, height: 400)
        for side: ExpansionSide in [.above, .below] {
            let p = resizeOrigin(current: current, newSize: newSize, side: side, screen: screen)
            XCTAssertEqual(p.x, 12, accuracy: 0.5, "side \(side) must clamp x on-screen")
            XCTAssertLessThanOrEqual(p.x + newSize.width, screen.maxX - 12 + 0.5)
        }
    }
}
