import AppKit
import Combine
import SwiftUI

@MainActor
final class OrbitPanelModel: ObservableObject {
    @Published var state: OrbitState = .idle
    @Published var mode: SurfaceMode = .orb
    var isExpanded: Bool { mode == .voice }
    @Published var debugText = ""
    @Published var streamText = ""
    @Published var hintText: String?
    @Published var workStart: Date?
    var chatOpen: Bool {
        mode == .thinking || mode == .output || mode == .card || mode == .history
    }
    @Published var selectedTurn: ChatTurn?
    let store = ChatStore()

    let microphone = MicrophoneMonitor()
    let context: ContextService
    let isMockVoice: Bool
    var persistPosition: (() -> Void)?
    var movePanelBy: ((CGSize) -> Void)?
    var snapPanel: (() -> Void)?
    private var lastDragTranslation: CGSize?
    private let talk: TalkSession
    private var voice: any VoiceSession
    private var answerTask: Task<Void, Never>?
    private var isDragging = false
    private var dragResetWorkItem: DispatchWorkItem?

    init(
        isMockVoice: Bool? = nil,
        context: ContextService? = nil,
        talk: TalkSession? = nil,
        voice: (any VoiceSession)? = nil
    ) {
        let mockFlag = isMockVoice ?? CommandLine.arguments.contains("--mock-voice")
        self.isMockVoice = mockFlag
        let contextService = context ?? ContextService()
        self.context = contextService
        let config = EnvLoader.config(
            processEnv: ProcessInfo.processInfo.environment,
            fileEnv: EnvLoader.repoRootEnv()
        )
        self.talk = talk ?? TalkSession(context: contextService, client: OpenRouterClient(config: config))
        if let voice {
            self.voice = voice
        } else if mockFlag {
            self.voice = MockVoiceSession()
        } else {
            self.voice = AssemblyAISTTSession(apiKey: config.assemblyAIKey ?? "")
        }
        self.voice.onFinalTranscript = { [weak self] transcript in
            Task { @MainActor [weak self] in
                self?.submit(transcript: transcript)
            }
        }
    }

    func activate() {
        guard !isDragging else { return }

        answerTask?.cancel()
        answerTask = nil
        state = .listening
        mode = .voice
        workStart = nil
        microphone.start()
        voice.start()
    }

    func drag(to translation: CGSize) {
        dragResetWorkItem?.cancel()
        isDragging = true
        let last = lastDragTranslation ?? .zero
        let delta = CGSize(
            width: translation.width - last.width, height: translation.height - last.height)
        lastDragTranslation = translation
        movePanelBy?(delta)
    }

    func endDrag() {
        lastDragTranslation = nil
        // Persist happens only in snapPanelToEdge's completion handler (post-snap
        // frame); persisting here would write the pre-snap frame and a quit
        // during the 0.35s animation would keep the stale position.
        snapPanel?()

        let reset = DispatchWorkItem { [weak self] in
            self?.isDragging = false
        }
        dragResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: reset)
    }

    func cancel() {
        answerTask?.cancel()
        answerTask = nil
        voice.stop()
        microphone.stop()
        streamText = ""
        hintText = nil
        workStart = nil
        selectedTurn = nil
        state = .idle
        mode = .orb
    }

    func openHistory() {
        mode = .history
        workStart = nil
        selectedTurn = nil
        state = .idle
    }

    func closeChat() {
        answerTask?.cancel()
        answerTask = nil
        streamText = ""
        hintText = nil
        workStart = nil
        mode = .orb
        selectedTurn = nil
        state = .idle
    }

    func expandToCard() {
        mode = .card
    }

    func send() {
        let pending = debugText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else {
            mode = .voice
            return
        }
        submit(transcript: pending)
    }

    func submit(transcript: String) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        answerTask?.cancel()
        microphone.stop()
        voice.stop()
        streamText = ""
        hintText = nil
        workStart = nil
        state = .thinking
        mode = .thinking
        selectedTurn = nil
        answerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.talk.answerStream(
                transcript: text,
                onHint: { hint in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.answerTask != nil else { return }
                        self.hintText = hint
                    }
                },
                onToken: { token in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.answerTask != nil else { return }
                        if self.workStart == nil {
                            self.workStart = Date()
                        }
                        self.hintText = nil
                        self.streamText += token
                    }
                }
            )
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard self.answerTask != nil else { return }
            let fired = TalkController.selectTools(
                transcript: text,
                hasPaste: !self.context.pastedText.isEmpty,
                clipboardAllowed: self.context.clipboardAllowed
            )
            let tools = fired.map(\.rawValue).sorted()
            self.store.append(ChatTurn(transcript: text, reply: self.streamText, tools: tools))
            self.mode = .output
            self.state = .idle
        }
    }
}

private final class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OrbitAppDelegate: NSObject, NSApplicationDelegate {
    private enum PositionKey {
        static let anchorX = "orbit.panel.anchorX"
        static let centerY = "orbit.panel.centerY"
    }

    private let model = OrbitPanelModel()
    private var panel: OrbitPanel?
    private var cancellables = Set<AnyCancellable>()
    private var pendingCollapse: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panel = OrbitPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OrbitOverlayView(model: model))

        self.panel = panel
        model.persistPosition = { [weak self] in
            self?.persistPanelAnchor()
        }
        model.movePanelBy = { [weak self] delta in
            self?.movePanel(by: delta)
        }
        model.snapPanel = { [weak self] in
            self?.snapPanelToEdge()
        }

        model.$mode
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resizePanelForModel()
            }
            .store(in: &cancellables)

        positionPanel()
        panel.orderFrontRegardless()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func positionPanel() {
        let size = surfaceSize(.orb)
        guard let panel else { return }

        let origin: NSPoint
        if let savedOrigin = savedOrigin(for: size) {
            origin = savedOrigin
        } else if let screen = preferredScreen() {
            let visibleFrame = screen.visibleFrame
            origin = NSPoint(
                x: visibleFrame.maxX - size.width - 20,
                y: visibleFrame.midY - size.height / 2
            )
        } else {
            origin = .zero
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        persistPanelAnchor()
    }

    private func resizePanelForModel() {
        resizePanel(mode: model.mode)
    }

    private func resizePanel(mode: SurfaceMode) {
        guard let panel else { return }

        pendingCollapse?.cancel()

        let size = surfaceSize(mode)
        NSLog("orbit: mode=%@", String(describing: mode))
        let screenFrame =
            panel.screen?.visibleFrame ?? preferredScreen()?.visibleFrame ?? panel.frame
        let side = expansionSide(
            anchorX: panel.frame.maxX, anchorY: panel.frame.midY, screen: screenFrame)
        let origin = resizeOrigin(current: panel.frame, newSize: size, side: side, screen: screenFrame)
        let frame = NSRect(origin: origin, size: size)

        if mode != .orb {
            panel.setFrame(frame, display: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let collapse = DispatchWorkItem { [weak panel] in
            panel?.setFrame(frame, display: true)
        }
        pendingCollapse = collapse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: collapse)
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    private func savedOrigin(for size: NSSize) -> NSPoint? {
        if let fileAnchor = AnchorStore.load() {
            let screenFrame =
                preferredScreen()?.visibleFrame ?? NSScreen.main?.visibleFrame
            if let screenFrame {
                let side = expansionSide(
                    anchorX: fileAnchor.maxX, anchorY: fileAnchor.midY, screen: screenFrame)
                let origin = placementOrigin(
                    anchor: fileAnchor, size: size, side: side, screen: screenFrame)
                let frame = NSRect(origin: origin, size: size)
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                    return origin
                }
            } else {
                let origin = NSPoint(
                    x: fileAnchor.maxX - size.width, y: fileAnchor.midY - size.height / 2)
                return origin
            }
        }

        let defaults = UserDefaults.standard
        guard defaults.object(forKey: PositionKey.anchorX) != nil,
              defaults.object(forKey: PositionKey.centerY) != nil else {
            return nil
        }

        let anchorX = defaults.double(forKey: PositionKey.anchorX)
        let centerY = defaults.double(forKey: PositionKey.centerY)
        let origin = NSPoint(x: anchorX - size.width, y: centerY - size.height / 2)
        let frame = NSRect(origin: origin, size: size)

        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else {
            return nil
        }

        return origin
    }

    private func movePanel(by delta: CGSize) {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin.x += delta.width
        frame.origin.y -= delta.height
        panel.setFrame(frame, display: true)
    }

    private func snapPanelToEdge() {
        guard let panel else { return }
        let screenFrame =
            panel.screen?.visibleFrame ?? preferredScreen()?.visibleFrame ?? panel.frame
        let target = snapTarget(current: panel.frame, screen: screenFrame)
        let targetFrame = NSRect(origin: target, size: panel.frame.size)
        // Magnetic snap: ease-out cubic approx of a spring (damping ~0.8,
        // duration 0.35s). Note: AppKit NSAnimationContext has no damping
        // parameter — this is not a true CASpring.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.2, 0.9, 0.25, 1.0)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.persistPanelAnchor()
            }
        }
    }

    private func persistPanelAnchor() {
        guard let panel else { return }

        UserDefaults.standard.set(panel.frame.maxX, forKey: PositionKey.anchorX)
        UserDefaults.standard.set(panel.frame.midY, forKey: PositionKey.centerY)
        AnchorStore.save(PanelAnchor(maxX: panel.frame.maxX, midY: panel.frame.midY))
    }
}

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(OrbitAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
