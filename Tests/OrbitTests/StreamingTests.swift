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
        var got: [StreamEvent] = []
        for await t in s.stream(model: "m", messages: [], imagePNG: nil, apiKey: "") { got.append(t) }
        XCTAssertEqual(got, [.token("abc")])
    }
    func testStubYieldsChunksInOrder() async {
        let s = StubTokenStreamer(texts: ["a", "b", "c"])
        var got: [StreamEvent] = []
        for await t in s.stream(model: "m", messages: [], imagePNG: nil, apiKey: "") { got.append(t) }
        XCTAssertEqual(got, [.token("a"), .token("b"), .token("c")])
    }
    func testHintStringsFollowTools() {
        XCTAssertEqual(TalkController.hintStrings(for: [.screenshot, .activeAppWindow]),
                       ["glancing at your screen… noting the front app…"])
        XCTAssertEqual(TalkController.hintStrings(for: []), [])
    }
    @MainActor func testAnswerStreamYieldsStubAsOneToken() async {
        let svc = ContextService()
        let stub = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let s = TalkSession(context: svc, client: stub)
        final class Box: @unchecked Sendable { var v: [String] = [] }
        let hintsBox = Box()
        let tokensBox = Box()
        await s.answerStream(transcript: "what am I looking at?", history: [],
                             onHint: { hintsBox.v.append($0) }, onToken: { tokensBox.v.append($0) })
        XCTAssertEqual(hintsBox.v.count, 1)
        XCTAssertTrue(hintsBox.v[0].contains("glancing"))
        XCTAssertEqual(tokensBox.v.count, 1)
        XCTAssertTrue(tokensBox.v[0].contains("what am I looking at?"))
    }
    @MainActor func testHistoryBecomesPriorMessages() {
        let msgs = TalkController.messages(transcript: "and it?", context: ContextBundle(), history: [
            ChatTurn(transcript: "what am I looking at?", reply: "A browser.", tools: ["screenshot"])
        ])
        let joined = msgs.map { $0["content"] ?? "" }.joined(separator: "\n")
        XCTAssertTrue(joined.contains("what am I looking at?"))
        XCTAssertTrue(joined.contains("A browser."))
    }
}
