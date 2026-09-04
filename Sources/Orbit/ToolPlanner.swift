import Foundation

public struct PlannedToolCall: Equatable, Sendable {
    public var name: String
    public var arguments: [String: String]

    public init(name: String, arguments: [String: String] = [:]) {
        self.name = name
        self.arguments = arguments
    }
}

public protocol ToolPlanning: Sendable {
    func plan(model: String, messages: [[String: String]], screenshotPaths: [String], apiKey: String) async -> [PlannedToolCall]
}

public struct OpenRouterToolPlanner: ToolPlanning {
    public init() {}

    public static func tools(screenshotPaths: [String]) -> [[String: Any]] {
        var tools: [[String: Any]] = [
            function(
                name: "capture_screen",
                description: "Capture the user's current display when seeing the current screen is necessary.",
                properties: [:], required: []),
            function(
                name: "read_clipboard",
                description: "Read the user's clipboard once when its contents are necessary.",
                properties: [:], required: []),
        ]
        if !screenshotPaths.isEmpty {
            tools.append(function(
                name: "load_screenshot",
                description: "Load a screenshot previously attached in this conversation.",
                properties: [
                    "attachment_path": [
                        "type": "string",
                        "enum": screenshotPaths,
                        "description": "The stored screenshot attachment to load."
                    ]
                ],
                required: ["attachment_path"]))
        }
        return tools
    }

    private static func function(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": ["type": "object", "properties": properties, "required": required],
            ],
        ]
    }

    public func plan(model: String, messages: [[String: String]], screenshotPaths: [String], apiKey: String) async -> [PlannedToolCall] {
        var request = OpenRouterClient.buildRequest(model: model, messages: messages, apiKey: apiKey)
        var body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        body["tools"] = Self.tools(screenshotPaths: screenshotPaths)
        body["tool_choice"] = "auto"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            struct Function: Decodable { var name: String; var arguments: String }
            struct ToolCall: Decodable { var function: Function }
            struct Message: Decodable { var tool_calls: [ToolCall]? }
            struct Choice: Decodable { var message: Message? }
            struct Response: Decodable { var choices: [Choice]? }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.choices?.first?.message?.tool_calls?.map { call in
                let object = (try? JSONSerialization.jsonObject(with: Data(call.function.arguments.utf8))) as? [String: String]
                return PlannedToolCall(name: call.function.name, arguments: object ?? [:])
            } ?? []
        } catch {
            return []
        }
    }
}

public struct StubToolPlanner: ToolPlanning {
    public var calls: [PlannedToolCall]
    public init(calls: [PlannedToolCall]) { self.calls = calls }
    public func plan(model: String, messages: [[String: String]], screenshotPaths: [String], apiKey: String) async -> [PlannedToolCall] { calls }
}
