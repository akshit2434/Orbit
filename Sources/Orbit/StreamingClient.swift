import Foundation

public enum StreamEvent: Equatable, Sendable {
    case token(String)
    case failure(String)
}

public protocol TokenStreamer: Sendable {
    func stream(model: String, messages: [[String: String]], imagePNG: Data?, apiKey: String) -> AsyncStream<StreamEvent>
}

public enum StreamParse {
    public static func tokenDeltas(fromSSELine line: String) -> [String] {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("data:") else { return [] }
        let payload = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return [] }
        struct Delta: Decodable { var content: String? }
        struct Choice: Decodable { var delta: Delta? }
        struct Event: Decodable { var choices: [Choice]? }
        guard let data = payload.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: data) else { return [] }
        return event.choices?.compactMap { $0.delta?.content }.filter { !$0.isEmpty } ?? []
    }
}

public struct OpenRouterTokenStreamer: TokenStreamer {
    public init() {}
    public func stream(model: String, messages: [[String: String]], imagePNG: Data?, apiKey: String) -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            Task {
                var request = OpenRouterClient.buildRequest(model: model, messages: messages, imagePNG: imagePNG, apiKey: apiKey)
                var body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
                body["stream"] = true
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        continuation.yield(.failure("OpenRouter request failed (HTTP \(status))."))
                        continuation.finish()
                        return
                    }
                    for try await line in bytes.lines {
                        for token in StreamParse.tokenDeltas(fromSSELine: line) { continuation.yield(.token(token)) }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.failure("The response was interrupted. Retry to continue."))
                    continuation.finish()
                }
            }
        }
    }
}

public struct StubTokenStreamer: TokenStreamer {
    public var texts: [String]
    public init(text: String) { self.texts = [text] }
    public init(texts: [String]) { self.texts = texts }
    public func stream(model: String, messages: [[String: String]], imagePNG: Data?, apiKey: String) -> AsyncStream<StreamEvent> {
        let chunks = texts
        return AsyncStream { continuation in
            for chunk in chunks { continuation.yield(.token(chunk)) }
            continuation.finish()
        }
    }
}
