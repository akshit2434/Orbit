import AppKit
import Combine
import SwiftUI

@MainActor
final class OrbitPanelModel: ObservableObject {
    @Published var state: OrbitState = .idle
    @Published var mode: SurfaceMode = .orb
    var isExpanded: Bool { mode == .voice }
    @Published var mockText = ""
    @Published var askText = ""
    @Published var streamText = ""
    @Published var currentTranscript = ""
    @Published var hintText: String?
    @Published var workStart: Date?
    @Published var completedWorkDuration: TimeInterval?
    @Published var side: ExpansionSide = .left
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
    var movePanelToCursor: ((NSPoint) -> Void)?
    var snapPanel: (() -> Void)?
    var reassertPanel: (() -> Void)?
    var dragSamples: [DragSample] = []
    private var lastDragTranslation: CGSize?
    private var reassertWorkItem: DispatchWorkItem?
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

    func drag(to translation: CGSize, withVelocity velocity: CGVector = .zero) {
        dragResetWorkItem?.cancel()
        reassertWorkItem?.cancel()
        reassertWorkItem = nil
        isDragging = true
        let last = lastDragTranslation ?? .zero
        let delta = CGSize(
            width: translation.width - last.width, height: translation.height - last.height)
        lastDragTranslation = translation
        _ = velocity  // Reserved: edge hysteresis + clamp live in movePanel(by:).
        movePanelBy?(delta)
    }

    func drag(to translation: CGSize, at timestamp: TimeInterval) {
        if lastDragTranslation == nil {
            dragSamples.removeAll(keepingCapacity: true)
        }
        dragSamples.append(
            DragSample(
                point: CGPoint(x: translation.width, y: translation.height), at: timestamp))
        if dragSamples.count > 10 {
            dragSamples.removeFirst(dragSamples.count - 10)
        }
        drag(to: translation)
    }

    func drag(cursor: NSPoint, at timestamp: TimeInterval) {
        dragResetWorkItem?.cancel()
        reassertWorkItem?.cancel()
        reassertWorkItem = nil
        isDragging = true
        dragSamples.append(DragSample(point: cursor, at: timestamp))
        if dragSamples.count > 10 { dragSamples.removeFirst(dragSamples.count - 10) }
        movePanelToCursor?(cursor)
    }

    func endDrag(velocity: CGVector = .zero) {
        lastDragTranslation = nil
        let v: CGVector = velocity == .zero ? flingVelocity(dragSamples) : velocity
        if v != .zero {
            let projected = boundedThrow(v)
            movePanelBy?(CGSize(width: projected.dx, height: projected.dy))
        }
        dragSamples.removeAll(keepingCapacity: true)
        // Persist happens only in snapPanelToEdge's completion handler (post-snap
        // frame); persisting here would write the pre-snap frame and a quit
        // during the 0.35s animation would keep the stale position.
        snapPanel?()

        dragResetWorkItem?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            self?.isDragging = false
        }
        dragResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: reset)

        reassertWorkItem?.cancel()
        let reassert = DispatchWorkItem { [weak self] in
            self?.reassertPanel?()
        }
        reassertWorkItem = reassert
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: reassert)
    }

    func endCursorDrag() {
        let screenVelocity = flingVelocity(dragSamples)
        endDrag(velocity: CGVector(dx: screenVelocity.dx, dy: -screenVelocity.dy))
    }

    func cancel() {
        answerTask?.cancel()
        answerTask = nil
        voice.stop()
        microphone.stop()
        streamText = ""
        hintText = nil
        workStart = nil
        completedWorkDuration = nil
        currentTranscript = ""
        selectedTurn = nil
        state = .idle
        mode = .orb
    }

    func openHistory() {
        mode = .history
        workStart = nil
        completedWorkDuration = nil
        selectedTurn = nil
        state = .idle
    }

    func closeChat() {
        answerTask?.cancel()
        answerTask = nil
        streamText = ""
        hintText = nil
        workStart = nil
        completedWorkDuration = nil
        currentTranscript = ""
        mode = .orb
        selectedTurn = nil
        state = .idle
    }

    func expandToCard() {
        mode = .card
    }

    func send() {
        let isChatMode =
            mode == .card || mode == .history || mode == .output || mode == .thinking
        let source = isChatMode ? askText : mockText
        let pending = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else {
            if isChatMode { return }
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
        completedWorkDuration = nil
        currentTranscript = text
        state = .thinking
        mode = .thinking
        selectedTurn = nil
        askText = ""
        mockText = ""
        final class Accumulator: @unchecked Sendable {
            private let lock = NSLock()
            private var chunks: [String] = []
            func append(_ s: String) { lock.withLock { chunks.append(s) } }
            var value: String { lock.withLock { chunks.joined() } }
        }
        let accumulator = Accumulator()
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
                    accumulator.append(token)
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
            let reply = accumulator.value
            self.streamText = reply
            if self.workStart == nil, !reply.isEmpty {
                self.workStart = Date()
            }
            self.hintText = nil
            self.completedWorkDuration = self.workStart.map { Date().timeIntervalSince($0) } ?? 0
            let fired = TalkController.selectTools(
                transcript: text,
                hasPaste: !self.context.pastedText.isEmpty,
                clipboardAllowed: self.context.clipboardAllowed
            )
            let tools = fired.map(\.rawValue).sorted()
            self.store.append(ChatTurn(transcript: text, reply: reply, tools: tools))
            self.answerTask = nil
            self.mode = .output
            self.state = .idle
        }
    }
}

private final class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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
    private var pointerGrabOffset: NSPoint?

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
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
        ]
        panel.contentView = NSHostingView(rootView: OrbitOverlayView(model: model))

        self.panel = panel
        model.persistPosition = { [weak self] in
            self?.persistPanelAnchor()
        }
        model.movePanelBy = { [weak self] delta in
            self?.movePanel(by: delta)
        }
        model.movePanelToCursor = { [weak self] point in
            self?.movePanel(toCursor: point)
        }
        model.snapPanel = { [weak self] in
            self?.snapPanelToEdge()
        }
        model.reassertPanel = { [weak self] in
            self?.reassertPanelToSnap()
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
        model.side = side
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: collapse)
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
        let screenFrame =
            panel.screen?.visibleFrame ?? preferredScreen()?.visibleFrame ?? panel.frame
        let left = panel.frame.minX - screenFrame.minX
        let right = screenFrame.maxX - panel.frame.maxX
        let bottom = panel.frame.minY - screenFrame.minY
        let top = screenFrame.maxY - panel.frame.maxY
        let damped = hysteresisDamped(
            delta: CGVector(dx: delta.width, dy: delta.height),
            left: Double(left), right: Double(right), bottom: Double(bottom),
            top: Double(top))
        var frame = panel.frame
        frame.origin.x += damped.dx
        frame.origin.y -= damped.dy
        frame = clampedDragFrame(frame, screen: screenFrame)
        panel.setFrame(frame, display: true)
    }

    private func movePanel(toCursor cursor: NSPoint) {
        guard let panel else { return }
        if pointerGrabOffset == nil {
            pointerGrabOffset = NSPoint(
                x: cursor.x - panel.frame.origin.x,
                y: cursor.y - panel.frame.origin.y)
        }
        guard let offset = pointerGrabOffset else { return }
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(cursor) })?.visibleFrame
            ?? panel.screen?.visibleFrame ?? preferredScreen()?.visibleFrame ?? panel.frame
        var frame = panel.frame
        frame.origin = NSPoint(x: cursor.x - offset.x, y: cursor.y - offset.y)
        panel.setFrame(clampedDragFrame(frame, screen: screenFrame), display: true)
    }

    private func snapPanelToEdge() {
        guard let panel else { return }
        pointerGrabOffset = nil
        let screenFrame =
            panel.screen?.visibleFrame ?? preferredScreen()?.visibleFrame ?? panel.frame
        let target = snapTarget(current: panel.frame, screen: screenFrame)
        let targetFrame = NSRect(origin: target, size: panel.frame.size)
        // A single continuous release trajectory. The throw projection has
        // already moved the target selection; this animation supplies the
        // magnetic settle without handing the window to macOS window dragging.
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

    private func reassertPanelToSnap() {
        guard let panel else { return }
        let screenFrame =
            panel.screen?.visibleFrame ?? preferredScreen()?.visibleFrame ?? panel.frame
        let target = snapTarget(current: panel.frame, screen: screenFrame)
        let drift = hypot(target.x - panel.frame.origin.x, target.y - panel.frame.origin.y)
        guard drift > 2 else { return }
        panel.setFrame(NSRect(origin: target, size: panel.frame.size), display: true)
        persistPanelAnchor()
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
