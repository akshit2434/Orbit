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
            threads = snapshot.threads.map { thread in
                var restored = thread
                restored.turns = restored.turns.map { turn in
                    guard turn.status == .generating else { return turn }
                    var interrupted = turn
                    interrupted.status = .interrupted
                    interrupted.reply = "Generation interrupted when Orbit closed."
                    return interrupted
                }
                return restored
            }
            selectedThreadID = snapshot.selectedThreadID
            if threads != snapshot.threads { save() }
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

    public func updateTurn(id: UUID, in threadID: UUID, mutate: (inout ChatTurn) -> Void) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
              let turnIndex = threads[threadIndex].turns.firstIndex(where: { $0.id == id }) else { return }
        mutate(&threads[threadIndex].turns[turnIndex])
        objectWillChange.send()
        save()
    }

    public func removeTurn(id: UUID, from threadID: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let paths = threads[index].turns.first(where: { $0.id == id })?.toolResults.compactMap(\.attachmentPath) ?? []
        threads[index].turns.removeAll(where: { $0.id == id })
        removeAttachments(paths)
        objectWillChange.send()
        save()
    }

    public func saveAttachment(_ data: Data, threadID: UUID, turnID: UUID) -> String? {
        guard let root = storageURL?.deletingLastPathComponent() else { return nil }
        let relative = "attachments/\(threadID.uuidString)/\(turnID.uuidString).png"
        let url = root.appendingPathComponent(relative)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return relative
        } catch {
            return nil
        }
    }

    public func attachmentData(at relativePath: String) -> Data? {
        guard let root = storageURL?.deletingLastPathComponent(),
              !relativePath.hasPrefix("/"), !relativePath.contains("..") else { return nil }
        return try? Data(contentsOf: root.appendingPathComponent(relativePath))
    }
    public func clear() {
        guard let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else { return }
        let paths = threads[index].turns.flatMap(\.toolResults).compactMap(\.attachmentPath)
        threads[index].turns.removeAll()
        removeAttachments(paths)
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

    private func removeAttachments(_ paths: [String]) {
        guard let root = storageURL?.deletingLastPathComponent() else { return }
        for path in paths where !path.hasPrefix("/") && !path.contains("..") {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(path))
        }
    }
}
