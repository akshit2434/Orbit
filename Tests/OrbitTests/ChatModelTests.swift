import XCTest
@testable import Orbit

@MainActor
final class ChatModelTests: XCTestCase {
    func testEmptySendKeepsSurfaceOpen() {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.activate()
        model.debugText = "   "
        model.send()
        XCTAssertTrue(model.isExpanded)
        XCTAssertTrue(model.chatOpen)
        XCTAssertEqual(model.state, .listening)
    }
    func testSubmitStreamsStubToCompletion() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.submit(transcript: "ping")
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(model.streamText.contains("ping"))
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.chatOpen)
    }
}
