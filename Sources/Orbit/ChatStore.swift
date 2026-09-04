import Combine
import Foundation

@MainActor
public protocol ChatStoring: AnyObject {
    var turns: [ChatTurn] { get }
    func append(_ turn: ChatTurn)
    func clear()
}

public struct ChatThread: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var turns: [ChatTurn]

    public init(id: UUID = UUID(), title: String = "New chat", turns: [ChatTurn] = []) {
        self.id = id
        self.title = title
        self.turns = turns
    }
}

// Persistence seam: keep storage behind ChatStoring. The hard cap below is
// temporary; future improvement is compression (summarizing old turns)
// instead of dropping them.
@MainActor
public final class ChatStore: ObservableObject, ChatStoring {
    public static let cap = 50
    @Published public private(set) var threads: [ChatThread]
    @Published public private(set) var selectedThreadID: UUID
    public var turns: [ChatTurn] {
        threads.first(where: { $0.id == selectedThreadID })?.turns ?? []
    }

    public init() {
        let initial = ChatThread()
        threads = [initial]
        selectedThreadID = initial.id
    }

    @discardableResult
    public func newThread() -> UUID {
        let thread = ChatThread()
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
        return thread.id
    }

    public func selectThread(_ id: UUID) {
        guard threads.contains(where: { $0.id == id }) else { return }
        selectedThreadID = id
    }

    public func append(_ turn: ChatTurn) {
        append(turn, to: selectedThreadID)
    }

    public func append(_ turn: ChatTurn, to threadID: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].turns.insert(turn, at: 0)
        if threads[index].turns.count > Self.cap {
            threads[index].turns.removeLast(threads[index].turns.count - Self.cap)
        }
        if threads[index].title == "New chat" {
            threads[index].title = String(turn.transcript.prefix(42))
        }
        objectWillChange.send()
    }
    public func clear() {
        guard let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else { return }
        threads[index].turns.removeAll()
        objectWillChange.send()
    }
}
