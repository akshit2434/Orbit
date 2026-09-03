import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class MicrophoneMonitor: ObservableObject {
    @Published private(set) var levels = Array(repeating: CGFloat(0.04), count: 28)

    private let engine = AVAudioEngine()
    private var tapInstalled = false

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

    private func startEngine() {
        guard !engine.isRunning else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        if !tapInstalled {
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: format,
                block: Self.makeTapBlock(monitor: self)
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
        monitor: MicrophoneMonitor
    ) -> AVAudioNodeTapBlock {
        { [weak monitor] buffer, _ in
            guard let samples = buffer.floatChannelData?.pointee else { return }
            let level = normalizedLevel(samples: samples, count: Int(buffer.frameLength))

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
