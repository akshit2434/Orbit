import XCTest
@testable import Orbit

@MainActor
final class ChatModelTests: XCTestCase {
    private struct SlowStreamer: TokenStreamer {
        func stream(model: String, messages: [[String: String]], imagePNG: Data?, apiKey: String) -> AsyncStream<String> {
            AsyncStream { continuation in
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    continuation.yield("done")
                    continuation.finish()
                }
            }
        }
    }

    func testDuplicateSendIsBlockedAndStopMarksTurnCancelled() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: "key", openRouterModel: "m"))
        let model = OrbitPanelModel(
            isMockVoice: true,
            context: svc,
            talk: TalkSession(context: svc, client: client, streamer: SlowStreamer()),
            voice: MockVoiceSession())
        model.submit(transcript: "first", keepCard: true)
        model.submit(transcript: "second", keepCard: true)
        XCTAssertTrue(model.isGenerating)
        XCTAssertEqual(model.store.turns.count, 1)
        XCTAssertEqual(model.store.turns.first?.transcript, "first")

        model.stopGenerating()
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.store.turns.first?.status, .cancelled)
    }

    func testActivateDuringGenerationOpensCardWithoutCancelling() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: "key", openRouterModel: "m"))
        let model = OrbitPanelModel(
            isMockVoice: true,
            context: svc,
            talk: TalkSession(context: svc, client: client, streamer: SlowStreamer()),
            voice: MockVoiceSession())
        model.submit(transcript: "first")
        model.closeChat()
        model.activate()
        XCTAssertEqual(model.mode, .card)
        XCTAssertTrue(model.isGenerating)
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(model.store.turns.first?.status, .completed)
    }
    func testEmptySendKeepsSurfaceOpen() {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.activate()
        model.mockText = "   "
        model.send()
        XCTAssertEqual(model.mode, .voice)
        XCTAssertTrue(model.isExpanded)
        XCTAssertFalse(model.chatOpen)
        XCTAssertEqual(model.state, .listening)
    }
    func testEmptySendInCardStaysCard() {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.mode = .card
        model.askText = "   "
        model.send()
        XCTAssertEqual(model.mode, .card)
        model.mode = .history
        model.askText = ""
        model.send()
        XCTAssertEqual(model.mode, .history)
        model.mode = .output
        model.askText = "  "
        model.send()
        XCTAssertEqual(model.mode, .output)
        model.mode = .thinking
        model.askText = ""
        model.send()
        XCTAssertEqual(model.mode, .thinking)
    }
    func testSendClearsAskText() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.mode = .card
        model.askText = "hello"
        model.send()
        XCTAssertEqual(model.askText, "")
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(model.askText, "")
    }
    func testMultiTokenOrderingWithStubStreamer() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: "key", openRouterModel: "m"))
        let streamer = StubTokenStreamer(texts: ["a", "b", "c"])
        let talk = TalkSession(context: svc, client: client, streamer: streamer)
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: talk, voice: MockVoiceSession())
        model.submit(transcript: "ping")
        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(model.streamText, "abc")
        XCTAssertEqual(model.store.turns.first?.reply, "abc")
        XCTAssertEqual(model.mode, .output)
    }
    func testModeTransitions() {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        XCTAssertEqual(model.mode, .orb)
        model.activate()
        XCTAssertEqual(model.mode, .voice)
        model.openHistory()
        XCTAssertEqual(model.mode, .history)
        XCTAssertNil(model.workStart)
        model.closeChat()
        XCTAssertEqual(model.mode, .orb)
        model.mode = .output
        model.expandToCard()
        XCTAssertEqual(model.mode, .card)
        model.cancel()
        XCTAssertEqual(model.mode, .orb)
    }
    func testSubmitStreamsStubToCompletion() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.submit(transcript: "ping")
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(model.streamText.contains("ping"))
        XCTAssertEqual(model.currentTranscript, "ping")
        XCTAssertNotNil(model.completedWorkDuration)
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
    func testCloseChatCollapsesWithoutCancellingInflightStream() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.submit(transcript: "ping")
        model.closeChat()
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(model.chatOpen)
        XCTAssertTrue(model.streamText.contains("ping"))
        XCTAssertEqual(model.store.turns.first?.transcript, "ping")
    }
    func testCardSendStaysInCardAndUsesSelectedThread() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        let first = model.store.selectedThreadID
        model.mode = .card
        model.askText = "first message"
        model.send()
        XCTAssertEqual(model.mode, .card)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(model.mode, .card)
        XCTAssertEqual(model.store.turns.first?.transcript, "first message")
        let second = model.store.newThread()
        model.askText = "second message"
        model.send()
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(model.store.selectedThreadID, second)
        XCTAssertEqual(model.store.turns.first?.transcript, "second message")
        model.store.selectThread(first)
        XCTAssertEqual(model.store.turns.first?.transcript, "first message")
    }
    func testOpenHistoryShowsNoStaleTimer() {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.workStart = Date()
        model.openHistory()
        XCTAssertEqual(model.mode, .history)
        XCTAssertNil(model.workStart)
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
