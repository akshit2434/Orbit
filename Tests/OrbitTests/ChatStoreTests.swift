import XCTest
@testable import Orbit

@MainActor
final class ChatStoreTests: XCTestCase {
    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("chat-store.json")
    }

    @MainActor
    func testPersistsThreadsSelectionAndUncappedHistory() {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ChatStore(storageURL: url)
        let firstID = store.selectedThreadID
        for index in 0..<75 {
            store.append(ChatTurn(transcript: "q\(index)", reply: "a\(index)", tools: []))
        }
        let secondID = store.newThread()
        store.append(ChatTurn(transcript: "second", reply: "answer", tools: []))
        store.selectThread(firstID)

        let restored = ChatStore(storageURL: url)
        XCTAssertEqual(restored.selectedThreadID, firstID)
        XCTAssertEqual(restored.turns.count, 75)
        XCTAssertTrue(restored.threads.contains(where: { $0.id == secondID }))
    }
    func testAppendKeepsNewestFirst() {
        let s = ChatStore()
        s.append(ChatTurn(transcript: "a", reply: "b", tools: []))
        s.append(ChatTurn(transcript: "c", reply: "d", tools: ["screenshot"]))
        XCTAssertEqual(s.turns.map { $0.transcript }, ["c", "a"])
    }
    func testHistoryIsUncapped() {
        let s = ChatStore()
        for i in 0..<75 {
            s.append(ChatTurn(transcript: "t\(i)", reply: "r", tools: []))
        }
        XCTAssertEqual(s.turns.count, 75)
        XCTAssertEqual(s.turns.first?.transcript, "t74")
        XCTAssertNotNil(s.turns.first(where: { $0.transcript == "t0" }))
    }
    func testClearEmpties() {
        let s = ChatStore()
        s.append(ChatTurn(transcript: "a", reply: "b", tools: []))
        s.clear()
        XCTAssertTrue(s.turns.isEmpty)
    }
    func testThreadsKeepIndependentHistoriesAndSelection() {
        let s = ChatStore()
        let first = s.selectedThreadID
        s.append(ChatTurn(transcript: "first", reply: "one", tools: []))
        let second = s.newThread()
        s.append(ChatTurn(transcript: "second", reply: "two", tools: []))
        XCTAssertEqual(s.turns.map(\.transcript), ["second"])
        s.selectThread(first)
        XCTAssertEqual(s.turns.map(\.transcript), ["first"])
        s.selectThread(second)
        XCTAssertEqual(s.threads.first(where: { $0.id == second })?.title, "second")
    }
}
