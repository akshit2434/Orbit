import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum ContextTool: String, CaseIterable, Hashable, Sendable { case screenshot, activeAppWindow, pastedText, clipboard }

public struct ActiveAppInfo: Equatable, Sendable {
    public var appName: String; public var bundleID: String?; public var windowTitle: String?
}

public enum ScreenshotStatus: String, Equatable, Sendable {
    case notRequested, captured, permissionDenied, unavailable
}

public struct ContextBundle: Equatable, Sendable {
    public var app: ActiveAppInfo?; public var pastedText: String?; public var clipboard: String?; public var screenshotPNG: Data?; public var screenshotStatus: ScreenshotStatus = .notRequested; public var notes: [String] = []
}

@MainActor
public final class ContextService {
    public typealias ScreenshotProvider = @MainActor @Sendable () async -> (Data?, ScreenshotStatus)
    public var pastedText: String = ""
    public var clipboardAllowed: Bool = false
    private let screenshotProvider: ScreenshotProvider?
    public init(screenshotProvider: ScreenshotProvider? = nil) {
        self.screenshotProvider = screenshotProvider
    }
    public func activeApp() -> ActiveAppInfo {
        let app = NSWorkspace.shared.frontmostApplication
        return ActiveAppInfo(appName: app?.localizedName ?? "Unknown", bundleID: app?.bundleIdentifier, windowTitle: nil)
    }
    public func collect(tools: Set<ContextTool>) -> ContextBundle {
        var b = ContextBundle()
        if tools.contains(.activeAppWindow) { b.app = activeApp() }
        if tools.contains(.pastedText), !pastedText.isEmpty { b.pastedText = pastedText }
        if tools.contains(.clipboard), clipboardAllowed { b.clipboard = NSPasteboard.general.string(forType: .string) }
        if tools.contains(.screenshot) { b.notes.append("screenshot-requested") }
        return b
    }
    public func collectForRequest(tools: Set<ContextTool>) async -> ContextBundle {
        var bundle = collect(tools: tools)
        guard tools.contains(.screenshot) else { return bundle }
        let result = if let screenshotProvider {
            await screenshotProvider()
        } else {
            await captureScreenshotResult()
        }
        bundle.screenshotPNG = result.0
        bundle.screenshotStatus = result.1
        bundle.notes.removeAll(where: { $0 == "screenshot-requested" })
        bundle.notes.append("screenshot-\(result.1.rawValue)")
        return bundle
    }
    public func captureScreenshot() async -> Data? {
        await captureScreenshotResult().0
    }

    private func captureScreenshotResult() async -> (Data?, ScreenshotStatus) {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            return (nil, .permissionDenied)
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
            let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID })
                    ?? content.displays.first else { return (nil, .unavailable) }
            let ownBundleID = Bundle.main.bundleIdentifier
            let ownWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == ownBundleID }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let cfg = SCStreamConfiguration(); cfg.width = 1280; cfg.height = 800
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            let rep = NSBitmapImageRep(cgImage: img)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                return (nil, .unavailable)
            }
            return (png, .captured)
        } catch { return (nil, .unavailable) }
    }
}
