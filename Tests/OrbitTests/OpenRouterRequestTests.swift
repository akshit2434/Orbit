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
        XCTAssertEqual(out, "Heard: hello | app: Safari | screenshot: no | paste: 2 chars.")
    }

    func testCompleteStubScreenshotYes() async {
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let context = ContextBundle(app: nil, pastedText: nil, clipboard: nil, screenshotPNG: Data([0, 1]))
        let out = await client.complete(transcript: "t", context: context)
        XCTAssertTrue(out.contains("screenshot: yes"))
        XCTAssertTrue(out.contains("app: none"))
    }
}
