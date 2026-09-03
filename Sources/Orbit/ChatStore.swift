import Combine
import Foundation

@MainActor
public protocol ChatStoring: AnyObject {
    var turns: [ChatTurn] { get }
    func append(_ turn: ChatTurn)
    func clear()
}

// Persistence seam: keep storage behind ChatStoring. The hard cap below is
// temporary; future improvement is compression (summarizing old turns)
// instead of dropping them.
@MainActor
public final class ChatStore: ObservableObject, ChatStoring {
    public static let cap = 50
    @Published public private(set) var turns: [ChatTurn] = []
    public init() {}
    public func append(_ turn: ChatTurn) {
        turns.insert(turn, at: 0)
        if turns.count > Self.cap { turns.removeLast(turns.count - Self.cap) }
    }
    public func clear() { turns.removeAll() }
}
