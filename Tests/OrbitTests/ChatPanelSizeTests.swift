import XCTest
@testable import Orbit

final class ChatPanelSizeTests: XCTestCase {
    func testCollapsedOrbStaysSmall() {
        let size = orbitPanelSize(expanded: false, chatOpen: false)
        XCTAssertEqual(size.width, 80)
        XCTAssertEqual(size.height, 92)
    }

    func testExpandedCapsuleUnchanged() {
        let size = orbitPanelSize(expanded: true, chatOpen: false)
        XCTAssertEqual(size.width, 218)
        XCTAssertEqual(size.height, 76)
    }

    func testCollapsedChatFitsCard() {
        let size = orbitPanelSize(expanded: false, chatOpen: true)
        XCTAssertGreaterThanOrEqual(size.width, 222)
        XCTAssertGreaterThanOrEqual(size.height, 150)
    }
}
