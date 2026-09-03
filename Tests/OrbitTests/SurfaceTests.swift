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
}
