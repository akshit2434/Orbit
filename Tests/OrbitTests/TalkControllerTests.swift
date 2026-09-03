import XCTest
@testable import Orbit

final class TalkControllerTests: XCTestCase {
    func testDefaultToolsAreEmpty() {
        XCTAssertEqual(TalkController.selectTools(transcript: "hello", hasPaste: false, clipboardAllowed: false), [])
    }

    func testLookingAtRequestsScreenshot() {
        let tools = TalkController.selectTools(transcript: "what am I looking at?", hasPaste: false, clipboardAllowed: false)
        XCTAssertTrue(tools.contains(.screenshot))
        XCTAssertTrue(tools.contains(.activeAppWindow))
    }

    func testScreenKeywordRequestsScreenshot() {
        let tools = TalkController.selectTools(transcript: "what is on my screen?", hasPaste: false, clipboardAllowed: false)
        XCTAssertEqual(tools, [.screenshot, .activeAppWindow])
    }

    func testSeeingKeywordRequestsScreenshot() {
        let tools = TalkController.selectTools(transcript: "seeing this window?", hasPaste: false, clipboardAllowed: false)
        XCTAssertEqual(tools, [.screenshot, .activeAppWindow])
    }

    func testHasPasteAddsPastedText() {
        let tools = TalkController.selectTools(transcript: "hello", hasPaste: true, clipboardAllowed: false)
        XCTAssertEqual(tools, [.pastedText])
    }

    func testClipboardAllowedAddsClipboard() {
        let tools = TalkController.selectTools(transcript: "hello", hasPaste: false, clipboardAllowed: true)
        XCTAssertEqual(tools, [.clipboard])
    }

    func testCombinedTools() {
        let tools = TalkController.selectTools(transcript: "look at my screen", hasPaste: true, clipboardAllowed: true)
        XCTAssertEqual(tools, [.screenshot, .activeAppWindow, .pastedText, .clipboard])
    }

    @MainActor
    func testStubReplyMentionsApp() async {
        let svc = ContextService()
        svc.pastedText = "hi"
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let s = TalkSession(context: svc, client: client)
        let out = await s.answer(transcript: "hello")
        XCTAssertTrue(out.contains("hello"))
    }
}
