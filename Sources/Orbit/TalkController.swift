import Foundation

public struct ChatTurn: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var transcript: String
    public var reply: String
    public var tools: [String]
    public init(id: UUID = UUID(), transcript: String, reply: String, tools: [String]) {
        self.id = id; self.transcript = transcript; self.reply = reply; self.tools = tools
    }

    public static func == (lhs: ChatTurn, rhs: ChatTurn) -> Bool {
        lhs.transcript == rhs.transcript && lhs.reply == rhs.reply && lhs.tools == rhs.tools
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(transcript)
        hasher.combine(reply)
        hasher.combine(tools)
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
        for turn in history.suffix(6) {
            msgs.append(["role": "user", "content": turn.transcript])
            msgs.append(["role": "assistant", "content": turn.reply])
        }
        var parts = ["User said: \(transcript)"]
        if let app = context.app?.appName { parts.append("Front app: \(app)") }
        if let pasted = context.pastedText, !pasted.isEmpty { parts.append("Pasted text: \(pasted)") }
        if let clipboard = context.clipboard, !clipboard.isEmpty { parts.append("Clipboard: \(clipboard)") }
        if context.screenshotPNG != nil { parts.append("Screenshot attached: yes") }
        msgs.append(["role": "user", "content": parts.joined(separator: "\n")])
        return msgs
    }
}

@MainActor
public final class TalkSession {
    private let context: ContextService
    private let client: OpenRouterClient
    private let streamer: any TokenStreamer

    public init(context: ContextService, client: OpenRouterClient, streamer: any TokenStreamer = OpenRouterTokenStreamer()) {
        self.context = context
        self.client = client
        self.streamer = streamer
    }

    public func answer(transcript: String) async -> String {
        let tools = TalkController.selectTools(
            transcript: transcript,
            hasPaste: !context.pastedText.isEmpty,
            clipboardAllowed: context.clipboardAllowed
        )
        let bundle = context.collect(tools: tools)
        return await client.complete(transcript: transcript, context: bundle)
    }

    public func answerStream(transcript: String, history: [ChatTurn] = [],
                             onHint: @Sendable @escaping (String) -> Void,
                             onToken: @Sendable @escaping (String) -> Void) async {
        let tools = TalkController.selectTools(transcript: transcript,
            hasPaste: !context.pastedText.isEmpty, clipboardAllowed: context.clipboardAllowed)
        for hint in TalkController.hintStrings(for: tools) { onHint(hint) }
        let bundle = context.collect(tools: tools)
        if client.config.openRouterKey?.isEmpty != false {
            onToken(OpenRouterClient.stub(transcript: transcript, context: bundle))
            return
        }
        let msgs = TalkController.messages(transcript: transcript, context: bundle, history: history)
        for await token in streamer.stream(model: client.config.openRouterModel, messages: msgs, apiKey: client.config.openRouterKey ?? "") {
            onToken(token)
        }
    }
}
