import XCTest
@testable import Orbit

final class MockVoiceTests: XCTestCase {
    func testInjectDeliversTranscript() {
        let m = MockVoiceSession()
        var got: String?
        m.onFinalTranscript = { got = $0 }
        m.start(); m.inject(transcript: "hello orbit")
        XCTAssertEqual(got, "hello orbit")
    }
}
