import Foundation

public enum AssemblyAI {
    public static func uploadURL() -> URL {
        URL(string: "https://api.assemblyai.com/v2/upload")!
    }

    public static func transcriptURL() -> URL {
        URL(string: "https://api.assemblyai.com/v2/transcript")!
    }

    public static func buildUploadRequest(data: Data, apiKey: String) -> URLRequest {
        var r = URLRequest(url: uploadURL())
        r.httpMethod = "POST"
        r.setValue(apiKey, forHTTPHeaderField: "authorization")
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        r.httpBody = data
        return r
    }

    public static func buildTranscriptRequest(audioURL: String, apiKey: String) -> URLRequest {
        var r = URLRequest(url: transcriptURL())
        r.httpMethod = "POST"
        r.setValue(apiKey, forHTTPHeaderField: "authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["audio_url": audioURL]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return r
    }

    static func buildPollRequest(transcriptID: String, apiKey: String) -> URLRequest {
        var r = URLRequest(url: transcriptURL().appendingPathComponent(transcriptID))
        r.httpMethod = "GET"
        r.setValue(apiKey, forHTTPHeaderField: "authorization")
        return r
    }
}

public enum AssemblyAIError: Error, Equatable {
    case missingKey
    case uploadFailed
    case transcriptRequestFailed
    case transcriptFailed(String)
    case timedOut
    case decodingFailed
}

private struct UploadResponse: Decodable {
    var upload_url: String
}

private struct TranscriptCreateResponse: Decodable {
    var id: String
}

private struct TranscriptPollResponse: Decodable {
    var status: String
    var text: String?
    var error: String?
}

public final class AssemblyAISTTSession: VoiceSession {
    public var onLevel: ((Double) -> Void)?
    public var onFinalTranscript: ((String) -> Void)?
    public var onError: ((String) -> Void)?

    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func start() {}
    public func stop() {}

    public func transcribeWAV(_ wav: Data) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            onError?("missing AssemblyAI key")
            throw AssemblyAIError.missingKey
        }

        let audioURL = try await upload(wav: wav, key: key)
        let transcriptID = try await requestTranscript(audioURL: audioURL, key: key)
        return try await poll(transcriptID: transcriptID, key: key)
    }

    private func upload(wav: Data, key: String) async throws -> String {
        let request = AssemblyAI.buildUploadRequest(data: wav, apiKey: key)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: wav)
        } catch {
            throw AssemblyAIError.uploadFailed
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AssemblyAIError.uploadFailed
        }
        guard let decoded = try? JSONDecoder().decode(UploadResponse.self, from: data) else {
            throw AssemblyAIError.decodingFailed
        }
        return decoded.upload_url
    }

    private func requestTranscript(audioURL: String, key: String) async throws -> String {
        let request = AssemblyAI.buildTranscriptRequest(audioURL: audioURL, apiKey: key)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AssemblyAIError.transcriptRequestFailed
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AssemblyAIError.transcriptRequestFailed
        }
        guard let decoded = try? JSONDecoder().decode(TranscriptCreateResponse.self, from: data) else {
            throw AssemblyAIError.decodingFailed
        }
        return decoded.id
    }

    private func poll(transcriptID: String, key: String) async throws -> String {
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let request = AssemblyAI.buildPollRequest(transcriptID: transcriptID, apiKey: key)
            let (data, _): (Data, URLResponse)
            do {
                (data, _) = try await URLSession.shared.data(for: request)
            } catch {
                continue
            }
            guard let decoded = try? JSONDecoder().decode(TranscriptPollResponse.self, from: data) else {
                continue
            }
            switch decoded.status {
            case "completed":
                return decoded.text ?? ""
            case "error":
                throw AssemblyAIError.transcriptFailed(decoded.error ?? "transcription failed")
            default:
                continue
            }
        }
        throw AssemblyAIError.timedOut
    }
}
