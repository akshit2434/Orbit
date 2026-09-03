import XCTest
@testable import Orbit

final class StreamingTests: XCTestCase {
    func testParsesDeltaContent() {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        XCTAssertEqual(StreamParse.tokenDeltas(fromSSELine: line), ["Hello"])
    }
    func testIgnoresDoneAndBlanks() {
        XCTAssertEqual(StreamParse.tokenDeltas(fromSSELine: "data: [DONE]"), [])
        XCTAssertEqual(StreamParse.tokenDeltas(fromSSELine: ""), [])
        XCTAssertEqual(StreamParse.tokenDeltas(fromSSELine: ": keep-alive"), [])
    }
    func testStubYieldsWholeTextOnce() async {
        let s = StubTokenStreamer(text: "abc")
        var got: [String] = []
        for await t in s.stream(model: "m", messages: [], apiKey: "") { got.append(t) }
        XCTAssertEqual(got, ["abc"])
    }
}
