import XCTest
@testable import Orbit

final class OpenRouterRequestTests: XCTestCase {
    func testOpenRouterRequestHasBearer() {
        let r = OpenRouterClient.buildRequest(model: "m", messages: [["role": "user", "content": "hi"]], apiKey: "k")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }

    func testBuildRequestTargetsOpenRouter() throws {
        let r = OpenRouterClient.buildRequest(model: "m", messages: [["role": "user", "content": "hi"]], apiKey: "k")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(r.timeoutInterval, 30)
        let body = try XCTUnwrap(r.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "m")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "hi"]])
    }

    func testCompleteStubWhenKeyMissing() async {
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let context = ContextBundle(app: ActiveAppInfo(appName: "Safari", bundleID: nil, windowTitle: nil), pastedText: "hi", clipboard: nil, screenshotPNG: nil)
        let out = await client.complete(transcript: "hello", context: context)
        XCTAssertEqual(out, "Heard: hello | app: Safari | screenshot: notRequested | paste: 2 chars.")
    }

    func testFailureStubHasStatusMarker() {
        let context = ContextBundle(app: nil, pastedText: nil, clipboard: nil, screenshotPNG: nil)
        let out = OpenRouterClient.stubForFailure(status: 401, transcript: "hello", context: context)
        XCTAssertTrue(out.hasPrefix("[openrouter 401] "))
        XCTAssertTrue(out.contains("Heard: hello"))
        XCTAssertNotEqual(out, OpenRouterClient.stub(transcript: "hello", context: context))
    }

    func testCompleteStubScreenshotYes() async {
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let context = ContextBundle(app: nil, pastedText: nil, clipboard: nil, screenshotPNG: Data([0, 1]), screenshotStatus: .captured)
        let out = await client.complete(transcript: "t", context: context)
        XCTAssertTrue(out.contains("screenshot: captured"))
        XCTAssertTrue(out.contains("app: none"))
    }

    func testBuildRequestEncodesScreenshotAsMultimodalDataURL() throws {
        let png = Data([0, 1, 2])
        let request = OpenRouterClient.buildRequest(
            model: "m",
            messages: [["role": "user", "content": "describe this"]],
            imagePNG: png,
            apiKey: "k")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "describe this")
        XCTAssertEqual(content.last?["type"] as? String, "image_url")
        let image = try XCTUnwrap(content.last?["image_url"] as? [String: String])
        XCTAssertEqual(image["url"], "data:image/png;base64,AAEC")
    }

    func testPermissionDenialIsExplicitInModelContext() {
        let context = ContextBundle(
            app: nil,
            pastedText: nil,
            clipboard: nil,
            screenshotPNG: nil,
            screenshotStatus: .permissionDenied)
        let messages = TalkController.messages(transcript: "what do you see?", context: context, history: [])
        XCTAssertTrue(messages.last?["content"]?.contains("Screen Recording permission was denied") == true)
    }
}
