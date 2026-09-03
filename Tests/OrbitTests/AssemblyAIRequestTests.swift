import XCTest
@testable import Orbit

final class AssemblyAIRequestTests: XCTestCase {
    func testUploadRequestHasAuth() {
        let r = AssemblyAI.buildUploadRequest(data: Data([0, 1, 2]), apiKey: "k123")
        XCTAssertEqual(r.value(forHTTPHeaderField: "authorization"), "k123")
        XCTAssertEqual(r.url?.host, "api.assemblyai.com")
    }

    func testUploadRequestHasNoDuplicateBody() {
        let r = AssemblyAI.buildUploadRequest(data: Data([0, 1, 2]), apiKey: "k123")
        XCTAssertNil(r.httpBody, "upload(for:from:) supplies the body; httpBody must be nil")
    }

    func testPollStepNon200Throws() {
        XCTAssertThrowsError(try AssemblyAISTTSession.pollStep(statusCode: 401, data: Data("{\"status\":\"queued\"}".utf8)))
    }

    func testPollStepCompletedNilTextThrowsDecodingFailed() {
        let data = Data("{\"status\":\"completed\"}".utf8)
        XCTAssertThrowsError(try AssemblyAISTTSession.pollStep(statusCode: 200, data: data)) { error in
            XCTAssertEqual(error as? AssemblyAIError, .decodingFailed)
        }
    }

    func testPollStepCompletedText() throws {
        let data = Data("{\"status\":\"completed\",\"text\":\"hi\"}".utf8)
        XCTAssertEqual(try AssemblyAISTTSession.pollStep(statusCode: 200, data: data), "hi")
    }
}
