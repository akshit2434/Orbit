import AVFoundation
import Foundation
import SwiftUI

private final class AudioRecordingSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?

    func setFile(_ file: AVAudioFile?) { lock.withLock { self.file = file } }
    func write(_ buffer: AVAudioPCMBuffer) { lock.withLock { try? file?.write(from: buffer) } }
}

@MainActor
final class MicrophoneMonitor: ObservableObject {
    @Published private(set) var levels = Array(repeating: CGFloat(0.04), count: 28)

    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private let recordingSink = AudioRecordingSink()
    private var recordingURL: URL?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            Task { @MainActor [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                guard granted else { return }
                self?.startEngine()
            }
        default:
            break
        }
    }

    func stop() {
        engine.pause()
        levels = Array(repeating: CGFloat(0.04), count: levels.count)
    }

    func finishRecording() -> Data? {
        engine.pause()
        recordingSink.setFile(nil)
        guard let url = recordingURL else { return nil }
        recordingURL = nil
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }

    private func startEngine() {
        guard !engine.isRunning else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        recordingURL = url
        recordingSink.setFile(try? AVAudioFile(forWriting: url, settings: format.settings))

        if !tapInstalled {
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: format,
                block: Self.makeTapBlock(monitor: self, recordingSink: recordingSink)
            )
            tapInstalled = true
        }

        engine.prepare()

        do {
            try engine.start()
        } catch {
            engine.pause()
        }
    }

    private func append(_ level: CGFloat) {
        let smoothedLevel = (levels.last ?? level) * 0.34 + level * 0.66

        withAnimation(.linear(duration: 0.045)) {
            levels.removeFirst()
            levels.append(smoothedLevel)
        }
    }

    nonisolated private static func makeTapBlock(
        monitor: MicrophoneMonitor,
        recordingSink: AudioRecordingSink
    ) -> AVAudioNodeTapBlock {
        { [weak monitor] buffer, _ in
            guard let samples = buffer.floatChannelData?.pointee else { return }
            let level = normalizedLevel(samples: samples, count: Int(buffer.frameLength))

            recordingSink.write(buffer)
            Task { @MainActor [weak monitor] in
                monitor?.append(level)
            }
        }
    }

    nonisolated private static func normalizedLevel(
        samples: UnsafePointer<Float>,
        count: Int
    ) -> CGFloat {
        guard count > 0 else { return 0.04 }

        var sum: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = max(0, min(1, (decibels + 52) / 52))
        return CGFloat(max(0.04, normalized))
    }
}
