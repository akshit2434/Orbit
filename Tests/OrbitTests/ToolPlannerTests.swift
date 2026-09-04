import XCTest
@testable import Orbit

final class ToolPlannerTests: XCTestCase {
    func testToolSchemaOffersCurrentScreenClipboardAndSavedScreenshots() throws {
        let tools = OpenRouterToolPlanner.tools(screenshotPaths: ["attachments/thread/shot.png"])
        let functions = try tools.map { tool -> [String: Any] in
            try XCTUnwrap(tool["function"] as? [String: Any])
        }
        XCTAssertEqual(functions.compactMap { $0["name"] as? String }, [
            "capture_screen", "read_clipboard", "load_screenshot"
        ])
        let load = try XCTUnwrap(functions.last)
        let parameters = try XCTUnwrap(load["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let path = try XCTUnwrap(properties["attachment_path"] as? [String: Any])
        XCTAssertEqual(path["enum"] as? [String], ["attachments/thread/shot.png"])
    }

    @MainActor
    func testModelChosenCaptureIsPersistedAsThreadToolResult() async throws {
        final class CapturingStreamer: TokenStreamer, @unchecked Sendable {
            private let lock = NSLock()
            private var captured: Data?
            var image: Data? { lock.withLock { captured } }
            func stream(model: String, messages: [[String: String]], imagePNG: Data?, apiKey: String) -> AsyncStream<StreamEvent> {
                lock.withLock { captured = imagePNG }
                return AsyncStream { continuation in
                    continuation.yield(.token("I can see it."))
                    continuation.finish()
                }
            }
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("chat-store.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let png = Data([1, 2, 3, 4])
        let context = ContextService(screenshotProvider: { (png, .captured) })
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: "key", openRouterModel: "m"))
        let streamer = CapturingStreamer()
        let talk = TalkSession(
            context: context,
            client: client,
            streamer: streamer,
            planner: StubToolPlanner(calls: [PlannedToolCall(name: "capture_screen")]))
        let store = ChatStore(storageURL: url)
        let model = OrbitPanelModel(isMockVoice: true, context: context, talk: talk, voice: MockVoiceSession(), store: store)

        model.submit(transcript: "anything", keepCard: true)
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(streamer.image, png)
        let result = try XCTUnwrap(store.turns.first?.toolResults.first)
        XCTAssertEqual(result.kind, .screenshot)
        XCTAssertEqual(result.status, .success)
        let path = result.attachmentPath
        XCTAssertEqual(path.flatMap { store.attachmentData(at: $0) }, png)
    }
}
