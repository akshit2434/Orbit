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
        XCTAssertEqual(workedString(elapsed: 60), "Worked for 1m 0s")
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
    func testPlacementClampsYTopBottom() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 320, height: 400)
        // Anchor near bottom: above placement would go off-screen without clamp.
        let lowAnchor = PanelAnchor(maxX: 900, midY: 30)
        for side: ExpansionSide in [.left, .right, .above, .below] {
            let p = placementOrigin(anchor: lowAnchor, size: size, side: side, screen: screen)
            XCTAssertGreaterThanOrEqual(p.y, 12 - 0.5, "side \(side) must clamp y >= margin")
            XCTAssertLessThanOrEqual(p.y + size.height, screen.maxY - 12 + 0.5)
        }
        // Anchor near top: below placement would go off-screen without clamp.
        let highAnchor = PanelAnchor(maxX: 900, midY: 770)
        for side: ExpansionSide in [.left, .right, .above, .below] {
            let p = placementOrigin(anchor: highAnchor, size: size, side: side, screen: screen)
            XCTAssertGreaterThanOrEqual(p.y, 12 - 0.5, "side \(side) must clamp y >= margin")
            XCTAssertLessThanOrEqual(p.y + size.height, screen.maxY - 12 + 0.5)
        }
    }
    func testResizeClampsYTopBottom() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let newSize = NSSize(width: 320, height: 400)
        let low = NSRect(x: 900, y: 0, width: 80, height: 92)
        let high = NSRect(x: 900, y: 708, width: 80, height: 92)
        for current in [low, high] {
            for side: ExpansionSide in [.left, .right, .above, .below] {
                let p = resizeOrigin(current: current, newSize: newSize, side: side, screen: screen)
                XCTAssertGreaterThanOrEqual(p.y, 12 - 0.5, "side \(side) must clamp y >= margin")
                XCTAssertLessThanOrEqual(p.y + newSize.height, screen.maxY - 12 + 0.5)
            }
        }
    }
    func testSideTieBreak() {
        // Square screen center: horizontal and left/right both tie.
        // Horizontal wins ties, and .left wins left/right ties.
        let square = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        XCTAssertEqual(expansionSide(anchorX: 500, anchorY: 500, screen: square), .left)
        // Wide screen center: vertical wins, top/bottom tie goes .below.
        let wide = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(expansionSide(anchorX: 500, anchorY: 400, screen: wide), .below)
    }
    func testRightPlacementKeepsOrbLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let anchor = PanelAnchor(maxX: 92, midY: 400)
        let size = NSSize(width: 320, height: 400)
        let p = placementOrigin(anchor: anchor, size: size, side: .right, screen: screen)
        // Orb 80 wide: orbLeft = 92 - 80 = 12, panel extends right toward center.
        XCTAssertEqual(p.x, 12, accuracy: 0.5)
        XCTAssertEqual(p.y, 200, accuracy: 0.5)
    }
    func testBubbleLeadingOnlyOnLeft() {
        XCTAssertTrue(bubbleLeading(for: .left))
        XCTAssertFalse(bubbleLeading(for: .right))
        XCTAssertFalse(bubbleLeading(for: .above))
        XCTAssertFalse(bubbleLeading(for: .below))
    }
    func testCorruptAnchorLoadReturnsNil() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("anchor.json")
        try "not json".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(AnchorStore.load(base: base))
    }
    func testFlingVelocityFromSamples() {
        let v = flingVelocity([
            DragSample(point: CGPoint(x: 0, y: 0), at: 0),
            DragSample(point: CGPoint(x: 60, y: 0), at: 0.06),
            DragSample(point: CGPoint(x: 120, y: 0), at: 0.12),
        ])
        XCTAssertEqual(v.dx, 1000, accuracy: 1)
        XCTAssertEqual(flingVelocity([]).dx, 0)
    }
    func testBoundedThrowPreservesSmallVelocityAndCapsLargeVelocity() {
        let small = boundedThrow(CGVector(dx: 500, dy: 0))
        XCTAssertEqual(small.dx, 80, accuracy: 0.01)
        let large = boundedThrow(CGVector(dx: 3000, dy: 4000))
        XCTAssertEqual(hypot(large.dx, large.dy), 180, accuracy: 0.01)
    }
    func testHysteresisDampsNearEdge() {
        let d = hysteresisDamped(delta: CGVector(dx: 10, dy: 0), distanceToEdge: 10)
        XCTAssertEqual(d.dx, 3.5, accuracy: 0.01)
        let far = hysteresisDamped(delta: CGVector(dx: 10, dy: 0), distanceToEdge: 200)
        XCTAssertEqual(far.dx, 10, accuracy: 0.01)
    }
    func testHysteresisDampsOnlyTowardNearestEdge() {
        // Nearest = left (10pt): toward (dx<0) damps, away bypasses.
        let towardLeft = hysteresisDamped(
            delta: CGVector(dx: -10, dy: 0),
            left: 10, right: 500, bottom: 500, top: 500)
        XCTAssertEqual(towardLeft.dx, -3.5, accuracy: 0.01)
        let awayLeft = hysteresisDamped(
            delta: CGVector(dx: 10, dy: 0),
            left: 10, right: 500, bottom: 500, top: 500)
        XCTAssertEqual(awayLeft.dx, 10, accuracy: 0.01)
        // Nearest = right: toward (dx>0) damps.
        let towardRight = hysteresisDamped(
            delta: CGVector(dx: 10, dy: 0),
            left: 500, right: 10, bottom: 500, top: 500)
        XCTAssertEqual(towardRight.dx, 3.5, accuracy: 0.01)
        // Nearest = bottom: gesture-space +dy moves down (origin.y -= dy).
        let towardBottom = hysteresisDamped(
            delta: CGVector(dx: 0, dy: 10),
            left: 500, right: 500, bottom: 10, top: 500)
        XCTAssertEqual(towardBottom.dy, 3.5, accuracy: 0.01)
        let awayBottom = hysteresisDamped(
            delta: CGVector(dx: 0, dy: -10),
            left: 500, right: 500, bottom: 10, top: 500)
        XCTAssertEqual(awayBottom.dy, -10, accuracy: 0.01)
        // Nearest = top: gesture-space -dy moves up.
        let towardTop = hysteresisDamped(
            delta: CGVector(dx: 0, dy: -10),
            left: 500, right: 500, bottom: 500, top: 10)
        XCTAssertEqual(towardTop.dy, -3.5, accuracy: 0.01)
        // Along-edge bypass: nearest left but purely vertical motion.
        let along = hysteresisDamped(
            delta: CGVector(dx: 0, dy: 10),
            left: 10, right: 500, bottom: 500, top: 500)
        XCTAssertEqual(along.dy, 10, accuracy: 0.01)
        XCTAssertEqual(along.dx, 0, accuracy: 0.01)
        // Far from all edges: no damping even when moving toward nearest.
        let far = hysteresisDamped(
            delta: CGVector(dx: -10, dy: 0),
            left: 200, right: 500, bottom: 500, top: 500)
        XCTAssertEqual(far.dx, -10, accuracy: 0.01)
    }
    func testClampedDragFrameKeepsTwoPtInside() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let off = clampedDragFrame(NSRect(x: -50, y: -50, width: 80, height: 92), screen: screen)
        XCTAssertEqual(off.origin.x, 2, accuracy: 0.01)
        XCTAssertEqual(off.origin.y, 2, accuracy: 0.01)
        let over = clampedDragFrame(NSRect(x: 990, y: 780, width: 80, height: 92), screen: screen)
        XCTAssertEqual(over.maxX, 998, accuracy: 0.01)
        XCTAssertEqual(over.maxY, 798, accuracy: 0.01)
    }
    @MainActor
    func testEndDragProjectsVelocityBeforeSnap() {
        let svc = ContextService()
        let client = OpenRouterClient(
            config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(
            isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        var moves: [CGSize] = []
        var snaps = 0
        model.movePanelBy = { moves.append($0) }
        model.snapPanel = { snaps += 1 }
        model.endDrag(velocity: CGVector(dx: 1000, dy: 0))
        XCTAssertEqual(snaps, 1)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves[0].width, 160, accuracy: 0.01)
    }
}
