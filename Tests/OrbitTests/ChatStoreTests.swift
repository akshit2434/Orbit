import XCTest
@testable import Orbit

@MainActor
final class ChatStoreTests: XCTestCase {
    func testAppendKeepsNewestFirst() {
        let s = ChatStore()
        s.append(ChatTurn(transcript: "a", reply: "b", tools: []))
        s.append(ChatTurn(transcript: "c", reply: "d", tools: ["screenshot"]))
        XCTAssertEqual(s.turns.map { $0.transcript }, ["c", "a"])
    }
    func testCapDropsOldest() {
        let s = ChatStore()
        for i in 0..<(ChatStore.cap + 5) {
            s.append(ChatTurn(transcript: "t\(i)", reply: "r", tools: []))
        }
        XCTAssertEqual(s.turns.count, ChatStore.cap)
        XCTAssertEqual(s.turns.first?.transcript, "t\(ChatStore.cap + 4)")
        XCTAssertNil(s.turns.first(where: { $0.transcript == "t0" }))
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
