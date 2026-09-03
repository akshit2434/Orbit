import AppKit
import Foundation
import ScreenCaptureKit

public enum ContextTool: String, CaseIterable, Hashable { case screenshot, activeAppWindow, pastedText, clipboard }

public struct ActiveAppInfo: Equatable {
    public var appName: String; public var bundleID: String?; public var windowTitle: String?
}

public struct ContextBundle: Equatable {
    public var app: ActiveAppInfo?; public var pastedText: String?; public var clipboard: String?; public var screenshotPNG: Data?; public var notes: [String] = []
}

@MainActor
public final class ContextService {
    public var pastedText: String = ""
    public var clipboardAllowed: Bool = false
    public init() {}
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
    public func captureScreenshot() async -> Data? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = SCStreamConfiguration(); cfg.width = 1280; cfg.height = 800
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            let rep = NSBitmapImageRep(cgImage: img)
            return rep.representation(using: .png, properties: [:])
        } catch { return nil }
    }
}
