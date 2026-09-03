import Foundation

public struct OrbitConfig: Equatable {
    public var assemblyAIKey: String?
    public var openRouterKey: String?
    public var openRouterModel: String
    public init(assemblyAIKey: String?, openRouterKey: String?, openRouterModel: String) {
        self.assemblyAIKey = assemblyAIKey
        self.openRouterKey = openRouterKey
        self.openRouterModel = openRouterModel
    }
}

public enum EnvLoader {
    public static func loadEnvString(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in s.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
            let k = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
            let v = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            out[k] = v
        }
        return out
    }
    public static func loadEnvFile(at url: URL) -> [String: String] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return loadEnvString(s)
    }
    public static func config(processEnv: [String: String] = ProcessInfo.processInfo.environment, fileEnv: [String: String] = [:]) -> OrbitConfig {
        func pick(_ k: String) -> String? {
            let p = processEnv[k]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let p, !p.isEmpty { return p }
            let f = fileEnv[k]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (f?.isEmpty == false) ? f : nil
        }
        let model = pick("OPENROUTER_MODEL") ?? "openai/gpt-4o-mini"
        return OrbitConfig(assemblyAIKey: pick("ASSEMBLYAI_API_KEY"), openRouterKey: pick("OPENROUTER_API_KEY"), openRouterModel: model)
    }
    public static func repoRootEnv() -> [String: String] {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return loadEnvFile(at: cwd.appendingPathComponent(".env.local"))
    }
}
