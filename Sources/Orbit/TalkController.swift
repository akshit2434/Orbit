import Foundation

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
}

@MainActor
public final class TalkSession {
    private let context: ContextService
    private let client: OpenRouterClient

    public init(context: ContextService, client: OpenRouterClient) {
        self.context = context
        self.client = client
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
}
