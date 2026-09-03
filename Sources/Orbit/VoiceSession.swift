import Foundation

public protocol VoiceSession: AnyObject {
    func start()
    func stop()
    var onLevel: ((Double) -> Void)? { get set }
    var onFinalTranscript: ((String) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
}

public final class MockVoiceSession: VoiceSession {
    public var onLevel: ((Double) -> Void)?
    public var onFinalTranscript: ((String) -> Void)?
    public var onError: ((String) -> Void)?
    public private(set) var started = false
    public init() {}
    public func start() { started = true }
    public func stop() { started = false }
    public func inject(transcript: String) {
        guard started else { return }
        onFinalTranscript?(transcript)
    }
}
