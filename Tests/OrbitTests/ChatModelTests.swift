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
        XCTAssertEqual(model.mode, .voice)
        XCTAssertTrue(model.isExpanded)
        XCTAssertFalse(model.chatOpen)
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
    func testSubmitAppendsTurnToStore() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        XCTAssertTrue(model.store.turns.isEmpty)
        model.submit(transcript: "what am I looking at?")
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(model.store.turns.count, 1)
        XCTAssertEqual(model.store.turns.first?.transcript, "what am I looking at?")
        XCTAssertTrue(model.store.turns.first?.tools.contains("screenshot") ?? false)
    }
    func testCloseChatCancelsInflightStream() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.submit(transcript: "ping")
        model.closeChat()
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(model.chatOpen)
        XCTAssertTrue(model.streamText.isEmpty)
    }
    func testExpandToCardSetsCardMode() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.submit(transcript: "ping")
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(model.mode, .output)
        model.expandToCard()
        XCTAssertEqual(model.mode, .card)
    }
}
