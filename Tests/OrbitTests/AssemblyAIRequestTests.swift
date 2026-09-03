import XCTest
@testable import Orbit

final class AssemblyAIRequestTests: XCTestCase {
    func testUploadRequestHasAuth() {
        let r = AssemblyAI.buildUploadRequest(data: Data([0,1,2]), apiKey: "k123")
        XCTAssertEqual(r.value(forHTTPHeaderField: "authorization"), "k123")
        XCTAssertEqual(r.url?.host, "api.assemblyai.com")
    }
}
