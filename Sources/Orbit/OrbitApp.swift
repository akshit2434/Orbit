import AppKit
import Combine
import SwiftUI

@MainActor
final class OrbitPanelModel: ObservableObject {
    @Published var state: OrbitState = .idle
    @Published var isExpanded = false
    @Published var resultText: String?
    @Published var debugText = ""
    @Published var streamText = ""
    @Published var hintText: String?
    @Published var chatOpen = false
    @Published var historyOpen = false
    @Published var selectedTurn: ChatTurn?
    let store = ChatStore()

    let microphone = MicrophoneMonitor()
    let context: ContextService
    let isMockVoice: Bool
    var persistPosition: (() -> Void)?
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
        resultText = nil
        state = .listening
        isExpanded = true
        microphone.start()
        voice.start()
    }

    func beganDragging() {
        dragResetWorkItem?.cancel()
        isDragging = true
    }

    func endedDragging() {
        persistPosition?()

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
        resultText = nil
        streamText = ""
        hintText = nil
        chatOpen = false
        historyOpen = false
        selectedTurn = nil
        state = .idle
        isExpanded = false
    }

    func openHistory() {
        historyOpen = true
        chatOpen = true
        isExpanded = false
        selectedTurn = nil
        state = .idle
    }

    func closeChat() {
        answerTask?.cancel()
        answerTask = nil
        streamText = ""
        hintText = nil
        chatOpen = false
        historyOpen = false
        selectedTurn = nil
        state = .idle
    }

    func send() {
        let pending = debugText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else {
            isExpanded = true
            chatOpen = true
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
        resultText = nil
        streamText = ""
        hintText = nil
        state = .thinking
        isExpanded = false
        chatOpen = true
        historyOpen = false
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
            self.chatOpen = true
            self.state = .idle
        }
    }
}

private final class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Pure panel-sizing rule: the chat card (~190pt content + 20pt close-cross
// pad + 12pt root pad) must never render inside the 80pt collapsed frame.
func orbitPanelSize(expanded: Bool, chatOpen: Bool) -> NSSize {
    if expanded { return NSSize(width: 218, height: 76) }
    if chatOpen { return NSSize(width: 234, height: 168) }
    return NSSize(width: 80, height: 92)
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

        model.$isExpanded
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resizePanelForModel()
            }
            .store(in: &cancellables)

        model.$chatOpen
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
        let size = panelSize(expanded: false, chatOpen: false)
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
        resizePanel(expanded: model.isExpanded, chatOpen: model.chatOpen)
    }

    private func resizePanel(expanded: Bool, chatOpen: Bool) {
        guard let panel else { return }

        pendingCollapse?.cancel()

        let size = panelSize(expanded: expanded, chatOpen: chatOpen)
        let maxX = panel.frame.maxX
        let midY = panel.frame.midY
        let frame = NSRect(
            x: maxX - size.width,
            y: midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        if expanded || chatOpen {
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

    private func panelSize(expanded: Bool, chatOpen: Bool) -> NSSize {
        orbitPanelSize(expanded: expanded, chatOpen: chatOpen)
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    private func savedOrigin(for size: NSSize) -> NSPoint? {
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

    private func persistPanelAnchor() {
        guard let panel else { return }

        UserDefaults.standard.set(panel.frame.maxX, forKey: PositionKey.anchorX)
        UserDefaults.standard.set(panel.frame.midY, forKey: PositionKey.centerY)
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
