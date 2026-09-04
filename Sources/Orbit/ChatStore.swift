import Combine
import Foundation

@MainActor
public protocol ChatStoring: AnyObject {
    var turns: [ChatTurn] { get }
    func append(_ turn: ChatTurn)
    func clear()
}

public struct ChatThread: Identifiable, Equatable, Codable, Sendable {
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
    @Published public private(set) var threads: [ChatThread]
    @Published public private(set) var selectedThreadID: UUID
    private let storageURL: URL?
    public var turns: [ChatTurn] {
        threads.first(where: { $0.id == selectedThreadID })?.turns ?? []
    }

    private struct Snapshot: Codable {
        var threads: [ChatThread]
        var selectedThreadID: UUID
    }

    public static var defaultStorageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.akshit2434.orbit", isDirectory: true)
            .appendingPathComponent("chat-store.json")
    }

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL
        if let storageURL,
           let data = try? Data(contentsOf: storageURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
           !snapshot.threads.isEmpty,
           snapshot.threads.contains(where: { $0.id == snapshot.selectedThreadID }) {
            threads = snapshot.threads
            selectedThreadID = snapshot.selectedThreadID
        } else {
            let initial = ChatThread()
            threads = [initial]
            selectedThreadID = initial.id
        }
    }

    @discardableResult
    public func newThread() -> UUID {
        let thread = ChatThread()
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
        save()
        return thread.id
    }

    public func selectThread(_ id: UUID) {
        guard threads.contains(where: { $0.id == id }) else { return }
        selectedThreadID = id
        save()
    }

    public func append(_ turn: ChatTurn) {
        append(turn, to: selectedThreadID)
    }

    public func append(_ turn: ChatTurn, to threadID: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].turns.insert(turn, at: 0)
        if threads[index].title == "New chat" {
            threads[index].title = String(turn.transcript.prefix(42))
        }
        objectWillChange.send()
        save()
    }
    public func clear() {
        guard let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else { return }
        threads[index].turns.removeAll()
        objectWillChange.send()
        save()
    }

    private func save() {
        guard let storageURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(
                Snapshot(threads: threads, selectedThreadID: selectedThreadID))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("Orbit chat persistence failed: %@", error.localizedDescription)
        }
    }
}
