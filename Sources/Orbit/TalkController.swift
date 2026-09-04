import Foundation

public enum TurnStatus: String, Codable, Hashable, Sendable {
    case generating, completed, failed, cancelled, interrupted
}

public struct ToolResult: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable { case screenshot, clipboard }
    public enum Status: String, Codable, Hashable, Sendable { case success, error }
    public var id: UUID
    public var kind: Kind
    public var status: Status
    public var text: String?
    public var attachmentPath: String?

    public init(id: UUID = UUID(), kind: Kind, status: Status, text: String? = nil, attachmentPath: String? = nil) {
        self.id = id
        self.kind = kind
        self.status = status
        self.text = text
        self.attachmentPath = attachmentPath
    }
}

public struct ChatTurn: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var transcript: String
    public var reply: String
    public var tools: [String]
    public var status: TurnStatus
    public var createdAt: Date
    public var duration: TimeInterval?
    public var toolResults: [ToolResult]
    public init(id: UUID = UUID(), transcript: String, reply: String, tools: [String], status: TurnStatus = .completed, createdAt: Date = Date(), duration: TimeInterval? = nil, toolResults: [ToolResult] = []) {
        self.id = id; self.transcript = transcript; self.reply = reply; self.tools = tools
        self.status = status; self.createdAt = createdAt; self.duration = duration; self.toolResults = toolResults
    }

    public static func == (lhs: ChatTurn, rhs: ChatTurn) -> Bool {
        lhs.transcript == rhs.transcript && lhs.reply == rhs.reply && lhs.tools == rhs.tools && lhs.status == rhs.status && lhs.duration == rhs.duration && lhs.toolResults == rhs.toolResults
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(transcript)
        hasher.combine(reply)
        hasher.combine(tools)
        hasher.combine(status)
        hasher.combine(duration)
        hasher.combine(toolResults)
    }
}

public enum TalkController {
    public static func selectTools(transcript: String, hasPaste: Bool, clipboardAllowed: Bool) -> Set<ContextTool> {
        var tools = Set<ContextTool>()
        let lower = transcript.lowercased()
        if lower.contains("looking at") || lower.contains("screen") || lower.contains("seeing") {
            tools.insert(.screenshot)
            tools.insert(.activeAppWindow)
        }
        if hasPaste { tools.insert(.pastedText) }
        if clipboardAllowed { tools.insert(.clipboard) }
        return tools
    }

    public static func hintStrings(for tools: Set<ContextTool>) -> [String] {
        var parts: [String] = []
        if tools.contains(.screenshot) { parts.append("glancing at your screen…") }
        if tools.contains(.activeAppWindow) { parts.append("noting the front app…") }
        if tools.contains(.pastedText) { parts.append("reading your pasted text…") }
        if tools.contains(.clipboard) { parts.append("reading the clipboard…") }
        return parts.isEmpty ? [] : [parts.joined(separator: " ")]
    }

    public static func messages(transcript: String, context: ContextBundle, history: [ChatTurn]) -> [[String: String]] {
        var msgs = [["role": "system", "content": OpenRouterClient.systemPrompt]]
        for turn in history where turn.status == .completed {
            msgs.append(["role": "user", "content": turn.transcript])
            msgs.append(["role": "assistant", "content": turn.reply])
        }
        var parts = ["User said: \(transcript)"]
        if let app = context.app?.appName { parts.append("Front app: \(app)") }
        if let pasted = context.pastedText, !pasted.isEmpty { parts.append("Pasted text: \(pasted)") }
        if let clipboard = context.clipboard, !clipboard.isEmpty { parts.append("Clipboard: \(clipboard)") }
        parts.append(contentsOf: OpenRouterClient.screenshotContext(context))
        msgs.append(["role": "user", "content": parts.joined(separator: "\n")])
        return msgs
    }
}

@MainActor
public final class TalkSession {
    private let context: ContextService
    private let client: OpenRouterClient
    private let streamer: any TokenStreamer
    private let planner: any ToolPlanning

    public init(context: ContextService, client: OpenRouterClient, streamer: any TokenStreamer = OpenRouterTokenStreamer(), planner: any ToolPlanning = OpenRouterToolPlanner()) {
        self.context = context
        self.client = client
        self.streamer = streamer
        self.planner = planner
    }

    public func answer(transcript: String) async -> String {
        let tools = TalkController.selectTools(
            transcript: transcript,
            hasPaste: !context.pastedText.isEmpty,
            clipboardAllowed: context.clipboardAllowed
        )
        let bundle = await context.collectForRequest(tools: tools)
        return await client.complete(transcript: transcript, context: bundle)
    }

    public func answerStream(transcript: String, history: [ChatTurn] = [],
                             attachmentData: @MainActor @Sendable (String) -> Data? = { _ in nil },
                             onHint: @Sendable @escaping (String) -> Void,
                             onTools: @Sendable @escaping (ContextBundle, [PlannedToolCall]) -> Void = { _, _ in },
                             onFailure: @Sendable @escaping (String) -> Void = { _ in },
                             onToken: @Sendable @escaping (String) -> Void) async {
        let baseMessages = TalkController.messages(
            transcript: transcript, context: ContextBundle(), history: history)
        let screenshotPaths = history.flatMap(\.toolResults).compactMap { result in
            result.kind == .screenshot && result.status == .success ? result.attachmentPath : nil
        }
        let planned: [PlannedToolCall]
        if client.config.openRouterKey?.isEmpty == false {
            planned = await planner.plan(
                model: client.config.openRouterModel,
                messages: baseMessages,
                screenshotPaths: screenshotPaths,
                apiKey: client.config.openRouterKey ?? "")
        } else {
            planned = TalkController.selectTools(
                transcript: transcript,
                hasPaste: !context.pastedText.isEmpty,
                clipboardAllowed: context.clipboardAllowed
            ).map { PlannedToolCall(name: $0 == .screenshot ? "capture_screen" : $0.rawValue) }
        }
        var tools = Set<ContextTool>()
        if planned.contains(where: { $0.name == "capture_screen" }) {
            tools.formUnion([.screenshot, .activeAppWindow])
        }
        if planned.contains(where: { $0.name == "read_clipboard" || $0.name == "clipboard" }) {
            tools.insert(.clipboard)
        }
        if !context.pastedText.isEmpty { tools.insert(.pastedText) }
        for hint in TalkController.hintStrings(for: tools) { onHint(hint) }
        var bundle = await context.collectForRequest(tools: tools)
        if bundle.screenshotPNG == nil,
           let load = planned.first(where: { $0.name == "load_screenshot" }),
           let path = load.arguments["attachment_path"],
           screenshotPaths.contains(path),
           screenshotPaths.contains(path) {
            if let data = attachmentData(path) {
                bundle.screenshotPNG = data
                bundle.screenshotStatus = .captured
                bundle.notes.append("screenshot-loaded")
            } else {
                bundle.screenshotStatus = .unavailable
                bundle.notes.append("saved-screenshot-unavailable")
            }
        }
        onTools(bundle, planned)
        if client.config.openRouterKey?.isEmpty != false {
            onToken(OpenRouterClient.stub(transcript: transcript, context: bundle))
            return
        }
        let msgs = TalkController.messages(transcript: transcript, context: bundle, history: history)
        for await event in streamer.stream(
            model: client.config.openRouterModel,
            messages: msgs,
            imagePNG: bundle.screenshotPNG,
            apiKey: client.config.openRouterKey ?? "") {
            switch event {
            case let .token(token): onToken(token)
            case let .failure(message): onFailure(message)
            }
        }
    }
}
