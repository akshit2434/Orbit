import AppKit
import Combine
import SwiftUI

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class FloatingSurfaceCoordinator {
    private enum PositionKey {
        static let anchorX = "orbit.panel.anchorX"
        static let centerY = "orbit.panel.centerY"
    }

    private let model: OrbitPanelModel
    private(set) var orbPanel: OrbitPanel
    private(set) var surfacePanel: OrbitPanel
    private(set) var historyPanel: OrbitPanel
    private var cancellables = Set<AnyCancellable>()
    private var pointerGrabOffset: NSPoint?
    private var snapFrame: NSRect?
    private var hoverTimer: Timer?
    private var lastHistoryHoverAt: Date?
    private var historyAnimationProgress: CGFloat = 0
    private var lastHistoryAnimationTick = Date()

    init(model: OrbitPanelModel) {
        self.model = model
        orbPanel = Self.makePanel(size: surfaceSize(.orb), keyCapable: false)
        surfacePanel = Self.makePanel(size: surfaceSize(.voice))
        historyPanel = Self.makePanel(size: NSSize(width: 36, height: 36), keyCapable: false)

        let orbView = FirstMouseHostingView(
            rootView: OrbitOverlayView(model: model, role: .orb))
        orbPanel.contentView = orbView
        surfacePanel.contentView = FirstMouseHostingView(
            rootView: OrbitOverlayView(model: model, role: .attached))
        let historyView = FirstMouseHostingView(
            rootView: OrbitOverlayView(model: model, role: .history))
        historyPanel.contentView = historyView

        wireModel()
        restoreOrbPosition()
        observeMode()
        observeScreens()
        orbPanel.orderFrontRegardless()
        historyPanel.orderOut(nil)
        updateAttachedSurface(for: model.mode)
        startHoverTracking()
    }

    private static func makePanel(size: NSSize, keyCapable: Bool = true) -> OrbitPanel {
        let panel = OrbitPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.permitsKey = keyCapable
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
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
        ]
        return panel
    }

    private func wireModel() {
        model.movePanelToCursor = { [weak self] point in self?.move(toCursor: point) }
        model.movePanelBy = { [weak self] delta in self?.move(by: delta) }
        model.snapPanel = { [weak self] in self?.snapToEdge() }
        model.reassertPanel = { [weak self] in self?.reassertSnap() }
        model.persistPosition = { [weak self] in self?.persistAnchor() }
    }

    private func observeMode() {
        model.$mode.removeDuplicates().sink { [weak self] mode in
            if mode != .orb {
                self?.model.hideHistoryButton()
                self?.historyPanel.orderOut(nil)
                self?.historyPanel.alphaValue = 1
            }
            self?.updateAttachedSurface(for: mode)
            self?.updateHistoryPanel()
        }.store(in: &cancellables)
    }

    private func observeScreens() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screenConfigurationChanged() }
            .store(in: &cancellables)
    }

    private func startHoverTracking() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcileHistoryHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func reconcileHistoryHover(now: Date = Date()) {
        guard model.permitsHistoryHover else {
            lastHistoryHoverAt = nil
            model.hideHistoryButton()
            updateHistoryPanel()
            return
        }

        let pointer = NSEvent.mouseLocation
        let orbHitFrame = orbPanel.frame.insetBy(dx: 6, dy: 6)
        let screen = preferredScreen(for: pointer)?.visibleFrame ?? orbPanel.frame
        let anchor = OrbAnchor(center: NSPoint(x: orbPanel.frame.midX, y: orbPanel.frame.midY))
        let side = expansionSide(anchorX: anchor.center.x, anchorY: anchor.center.y, screen: screen)
        let historyHitFrame = historyButtonFrame(anchor: anchor, side: side, screen: screen)
            .insetBy(dx: -3, dy: -3)
        let isHovering = orbHitFrame.contains(pointer)
            || (model.historyVisible && historyHitFrame.contains(pointer))

        if isHovering {
            lastHistoryHoverAt = now
            setHistoryVisible(true)
        } else if let lastHistoryHoverAt,
                  now.timeIntervalSince(lastHistoryHoverAt) >= 0.5 {
            self.lastHistoryHoverAt = nil
            setHistoryVisible(false)
        }
        updateHistoryPanel(now: now)
    }

    private func setHistoryVisible(_ visible: Bool) {
        guard model.historyVisible != visible else { return }
        model.historyVisible = visible
    }

    private func preferredScreen(for point: NSPoint? = nil) -> NSScreen? {
        let p = point ?? NSPoint(x: orbPanel.frame.midX, y: orbPanel.frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(p) }) ?? NSScreen.main
    }

    private func restoreOrbPosition() {
        let size = surfaceSize(.orb)
        let screen = preferredScreen(for: NSEvent.mouseLocation)?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = AnchorStore.load()
            ?? PanelAnchor(
                maxX: screen.maxX - 20,
                midY: screen.midY)
        let proposed = NSRect(
            x: anchor.maxX - size.width,
            y: anchor.midY - size.height / 2,
            width: size.width,
            height: size.height)
        orbPanel.setFrame(containedPanelFrame(proposed, screen: screen), display: false)
        persistAnchor()
    }

    private func updateAttachedSurface(for mode: SurfaceMode) {
        guard mode != .orb else {
            surfacePanel.orderOut(nil)
            return
        }
        let screen = preferredScreen()?.visibleFrame ?? orbPanel.frame
        let anchor = OrbAnchor(center: NSPoint(x: orbPanel.frame.midX, y: orbPanel.frame.midY))
        let preferred = expansionSide(
            anchorX: anchor.center.x, anchorY: anchor.center.y, screen: screen)
        let placement = attachedSurfacePlacement(
            mode: mode, anchor: anchor, preferredSide: preferred, screen: screen)
        model.side = placement.side
        surfacePanel.setFrame(placement.frame, display: true)
        surfacePanel.contentView?.needsLayout = true
        surfacePanel.contentView?.layoutSubtreeIfNeeded()
        surfacePanel.orderFrontRegardless()
        surfacePanel.makeKey()
    }

    private func move(toCursor cursor: NSPoint) {
        if pointerGrabOffset == nil {
            pointerGrabOffset = NSPoint(
                x: cursor.x - orbPanel.frame.minX,
                y: cursor.y - orbPanel.frame.minY)
        }
        guard let offset = pointerGrabOffset else { return }
        let screen = preferredScreen(for: cursor)?.visibleFrame ?? orbPanel.frame
        let frame = NSRect(
            x: cursor.x - offset.x,
            y: cursor.y - offset.y,
            width: orbPanel.frame.width,
            height: orbPanel.frame.height)
        orbPanel.setFrame(containedPanelFrame(frame, screen: screen, margin: 2), display: true)
        updateAttachedSurface(for: model.mode)
        updateHistoryPanel()
    }

    private func move(by delta: CGSize) {
        let screen = preferredScreen()?.visibleFrame ?? orbPanel.frame
        var frame = orbPanel.frame
        frame.origin.x += delta.width
        frame.origin.y -= delta.height
        orbPanel.setFrame(containedPanelFrame(frame, screen: screen, margin: 2), display: true)
        updateAttachedSurface(for: model.mode)
        updateHistoryPanel()
    }

    private func snapToEdge() {
        pointerGrabOffset = nil
        let screen = preferredScreen()?.visibleFrame ?? orbPanel.frame
        let target = snapTarget(current: orbPanel.frame, screen: screen)
        let frame = containedPanelFrame(
            NSRect(origin: target, size: surfaceSize(.orb)), screen: screen)
        snapFrame = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.2, 0.9, 0.25, 1.0)
            context.allowsImplicitAnimation = true
            orbPanel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateAttachedSurface(for: self?.model.mode ?? .orb)
                self?.updateHistoryPanel()
                self?.persistAnchor()
            }
        }
    }

    private func reassertSnap() {
        guard let target = snapFrame else { return }
        let drift = hypot(target.minX - orbPanel.frame.minX, target.minY - orbPanel.frame.minY)
        guard drift > 2 else { return }
        orbPanel.setFrame(target, display: true)
        updateAttachedSurface(for: model.mode)
        updateHistoryPanel()
        persistAnchor()
    }

    private func screenConfigurationChanged() {
        let screen = preferredScreen()?.visibleFrame ?? NSScreen.main?.visibleFrame ?? orbPanel.frame
        orbPanel.setFrame(containedPanelFrame(orbPanel.frame, screen: screen), display: true)
        updateAttachedSurface(for: model.mode)
        updateHistoryPanel()
        persistAnchor()
    }

    private func persistAnchor() {
        let anchor = PanelAnchor(maxX: orbPanel.frame.maxX, midY: orbPanel.frame.midY)
        UserDefaults.standard.set(anchor.maxX, forKey: PositionKey.anchorX)
        UserDefaults.standard.set(anchor.midY, forKey: PositionKey.centerY)
        AnchorStore.save(anchor)
    }

    private func updateHistoryPanel(now: Date = Date()) {
        let shouldShow = model.mode == .orb && model.historyVisible
        let duration = shouldShow ? 0.22 : 0.18
        let elapsed = max(0, now.timeIntervalSince(lastHistoryAnimationTick))
        lastHistoryAnimationTick = now
        let step = CGFloat(elapsed / duration)
        historyAnimationProgress = shouldShow
            ? min(1, historyAnimationProgress + step)
            : max(0, historyAnimationProgress - step)

        guard historyAnimationProgress > 0 else {
            historyPanel.orderOut(nil)
            return
        }
        let screen = preferredScreen()?.visibleFrame ?? orbPanel.frame
        let anchor = OrbAnchor(center: NSPoint(x: orbPanel.frame.midX, y: orbPanel.frame.midY))
        let side = expansionSide(anchorX: anchor.center.x, anchorY: anchor.center.y, screen: screen)
        let frame = historyButtonFrame(anchor: anchor, side: side, screen: screen)
        let eased = historyAnimationProgress * historyAnimationProgress
            * (3 - 2 * historyAnimationProgress)
        let scale = 0.86 + 0.14 * eased
        let animatedSize = NSSize(width: frame.width * scale, height: frame.height * scale)
        let animatedFrame = NSRect(
            x: frame.midX - animatedSize.width / 2,
            y: frame.midY - animatedSize.height / 2,
            width: animatedSize.width,
            height: animatedSize.height)
        historyPanel.alphaValue = eased
        historyPanel.setFrame(animatedFrame, display: true)
        if !historyPanel.isVisible { historyPanel.orderFrontRegardless() }
    }
}
