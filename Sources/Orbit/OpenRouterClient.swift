import Foundation

public struct OpenRouterClient: Sendable {
    public let config: OrbitConfig

    public init(config: OrbitConfig) {
        self.config = config
    }

    public static let systemPrompt = "You are Orbit, a concise macOS voice companion. Answer in ≤3 sentences. Only reference screenshot/app/clipboard when present in context."

    public static func buildRequest(model: String, messages: [[String: String]], apiKey: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "messages": messages])
        return request
    }

    public func complete(transcript: String, context: ContextBundle) async -> String {
        guard let key = config.openRouterKey, !key.isEmpty else {
            return Self.stub(transcript: transcript, context: context)
        }
        var parts = ["User said: \(transcript)"]
        if let app = context.app?.appName { parts.append("Front app: \(app)") }
        if let pasted = context.pastedText, !pasted.isEmpty { parts.append("Pasted text: \(pasted)") }
        if let clipboard = context.clipboard, !clipboard.isEmpty { parts.append("Clipboard: \(clipboard)") }
        if context.screenshotPNG != nil { parts.append("Screenshot attached: yes") }
        let messages = [
            ["role": "system", "content": Self.systemPrompt],
            ["role": "user", "content": parts.joined(separator: "\n")],
        ]
        let request = Self.buildRequest(model: config.openRouterModel, messages: messages, apiKey: key)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return Self.stubForFailure(status: status, transcript: transcript, context: context) }
            struct ChoiceMessage: Decodable { var content: String? }
            struct Choice: Decodable { var message: ChoiceMessage? }
            struct Response: Decodable { var choices: [Choice]? }
            if let decoded = try? JSONDecoder().decode(Response.self, from: data),
               let text = decoded.choices?.first?.message?.content,
               !text.isEmpty {
                return text
            }
            return Self.stub(transcript: transcript, context: context)
        } catch {
            return Self.stub(transcript: transcript, context: context)
        }
    }

    static func stubForFailure(status: Int, transcript: String, context: ContextBundle) -> String {
        "[openrouter \(status)] " + stub(transcript: transcript, context: context)
    }

    static func stub(transcript: String, context: ContextBundle) -> String {
        let app = context.app?.appName ?? "none"
        let shot = context.screenshotPNG == nil ? "no" : "yes"
        let paste = context.pastedText?.count ?? 0
        return "Heard: \(transcript) | app: \(app) | screenshot: \(shot) | paste: \(paste) chars."
    }
}
