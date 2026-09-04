import Foundation

enum SurfaceMode: Equatable, Sendable {
    case orb
    case voice
    case thinking
    case output
    case card
    case history
}

func surfaceSize(_ mode: SurfaceMode) -> NSSize {
    switch mode {
    case .orb: NSSize(width: 56, height: 56)
    case .voice: NSSize(width: 218, height: 76)
    case .thinking: NSSize(width: 250, height: 80)
    case .output: NSSize(width: 250, height: 120)
    case .card: NSSize(width: 320, height: 400)
    case .history: NSSize(width: 320, height: 400)
    }
}

func historyButtonFrame(
    anchor: OrbAnchor,
    side: ExpansionSide,
    screen: CGRect,
    size: CGFloat = 36,
    gap: CGFloat = 4
) -> NSRect {
    let orb: CGFloat = 40
    let origin: CGPoint = switch side {
    case .left: CGPoint(x: anchor.center.x - orb / 2 - gap - size, y: anchor.center.y - size / 2)
    case .right: CGPoint(x: anchor.center.x + orb / 2 + gap, y: anchor.center.y - size / 2)
    case .above: CGPoint(x: anchor.center.x - size / 2, y: anchor.center.y + orb / 2 + gap)
    case .below: CGPoint(x: anchor.center.x - size / 2, y: anchor.center.y - orb / 2 - gap - size)
    }
    return containedPanelFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), screen: screen, margin: 2)
}

enum ExpansionSide: Equatable {
    case left
    case right
    case above
    case below
}

struct OrbAnchor: Equatable, Sendable {
    var center: CGPoint
}

struct SurfacePlacement: Equatable {
    var frame: NSRect
    var side: ExpansionSide
}

private func candidateSurfaceFrame(
    size: NSSize, orbFrame: NSRect, side: ExpansionSide, gap: CGFloat
) -> NSRect {
    switch side {
    case .left:
        NSRect(x: orbFrame.minX - gap - size.width,
               y: orbFrame.midY - size.height / 2, width: size.width, height: size.height)
    case .right:
        NSRect(x: orbFrame.maxX + gap,
               y: orbFrame.midY - size.height / 2, width: size.width, height: size.height)
    case .above:
        NSRect(x: orbFrame.midX - size.width / 2,
               y: orbFrame.maxY + gap, width: size.width, height: size.height)
    case .below:
        NSRect(x: orbFrame.midX - size.width / 2,
               y: orbFrame.minY - gap - size.height, width: size.width, height: size.height)
    }
}

private func frameOverflow(_ frame: NSRect, screen: CGRect, margin: CGFloat) -> CGFloat {
    max(0, screen.minX + margin - frame.minX)
        + max(0, frame.maxX - (screen.maxX - margin))
        + max(0, screen.minY + margin - frame.minY)
        + max(0, frame.maxY - (screen.maxY - margin))
}

/// Places an attached surface without ever changing the orb anchor. It first
/// honors the preferred side, then its opposite, then chooses the perpendicular
/// side with the least overflow before applying the final containment invariant.
func attachedSurfacePlacement(
    mode: SurfaceMode,
    anchor: OrbAnchor,
    preferredSide: ExpansionSide,
    screen: CGRect,
    gap: CGFloat = 4,
    margin: CGFloat = 12
) -> SurfacePlacement {
    // Placement follows the visible orb, not its larger transparent drag/hover panel.
    let orbSize = NSSize(width: 40, height: 40)
    let orbFrame = NSRect(
        x: anchor.center.x - orbSize.width / 2,
        y: anchor.center.y - orbSize.height / 2,
        width: orbSize.width,
        height: orbSize.height)
    let opposite: ExpansionSide = switch preferredSide {
    case .left: .right
    case .right: .left
    case .above: .below
    case .below: .above
    }
    let perpendicular: [ExpansionSide] = switch preferredSide {
    case .left, .right: [.above, .below]
    case .above, .below: [.left, .right]
    }
    let order = [preferredSide, opposite] + perpendicular.sorted {
        frameOverflow(candidateSurfaceFrame(size: surfaceSize(mode), orbFrame: orbFrame, side: $0, gap: gap), screen: screen, margin: margin)
            < frameOverflow(candidateSurfaceFrame(size: surfaceSize(mode), orbFrame: orbFrame, side: $1, gap: gap), screen: screen, margin: margin)
    }
    let size = surfaceSize(mode)
    let selected = order.min { lhs, rhs in
        let leftOverflow = frameOverflow(candidateSurfaceFrame(size: size, orbFrame: orbFrame, side: lhs, gap: gap), screen: screen, margin: margin)
        let rightOverflow = frameOverflow(candidateSurfaceFrame(size: size, orbFrame: orbFrame, side: rhs, gap: gap), screen: screen, margin: margin)
        if leftOverflow == rightOverflow {
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
        return leftOverflow < rightOverflow
    } ?? preferredSide
    let candidate = candidateSurfaceFrame(size: size, orbFrame: orbFrame, side: selected, gap: gap)
    return SurfacePlacement(
        frame: containedPanelFrame(candidate, screen: screen, margin: margin), side: selected)
}

func expansionSide(anchorX: Double, anchorY: Double, screen: CGRect) -> ExpansionSide {
    let toLeftEdge = anchorX - screen.minX
    let toRightEdge = screen.maxX - anchorX
    let toBottomEdge = anchorY - screen.minY
    let toTopEdge = screen.maxY - anchorY
    let horizontalMin = min(toLeftEdge, toRightEdge)
    let verticalMin = min(toBottomEdge, toTopEdge)
    if horizontalMin <= verticalMin {
        return toRightEdge <= toLeftEdge ? .left : .right
    }
    return toTopEdge <= toBottomEdge ? .below : .above
}

func snapTarget(current: NSRect, screen: CGRect) -> NSPoint {
    let margin: CGFloat = 12
    let leftDist = current.minX - screen.minX
    let rightDist = screen.maxX - current.maxX
    let bottomDist = current.minY - screen.minY
    let topDist = screen.maxY - current.maxY
    let minH = min(leftDist, rightDist)
    let minV = min(bottomDist, topDist)
    var origin = current.origin
    if minH <= minV {
        if rightDist <= leftDist {
            origin.x = screen.maxX - current.width - margin
        } else {
            origin.x = screen.minX + margin
        }
        let minY = screen.minY + margin
        let maxY = screen.maxY - current.height - margin
        origin.y = min(max(origin.y, minY), max(minY, maxY))
    } else {
        if topDist <= bottomDist {
            origin.y = screen.maxY - current.height - margin
        } else {
            origin.y = screen.minY + margin
        }
        let minX = screen.minX + margin
        let maxX = screen.maxX - current.width - margin
        origin.x = min(max(origin.x, minX), max(minX, maxX))
    }
    return origin
}

private func clampedX(_ x: CGFloat, sizeWidth: CGFloat, screen: CGRect) -> CGFloat {
    let margin: CGFloat = 12
    let minX = screen.minX + margin
    let maxX = screen.maxX - sizeWidth - margin
    return min(max(x, minX), max(minX, maxX))
}

private func clampedY(_ y: CGFloat, sizeHeight: CGFloat, screen: CGRect) -> CGFloat {
    let margin: CGFloat = 12
    let minY = screen.minY + margin
    let maxY = screen.maxY - sizeHeight - margin
    return min(max(y, minY), max(minY, maxY))
}

/// Bubble order for side-aware layout: only `.left` keeps bubble-left/orb-right.
/// `.right`/`.above`/`.below` mirror to orb-left/bubble-right so content
/// extends toward the screen center.
func bubbleLeading(for side: ExpansionSide) -> Bool {
    side == .left
}

func placementOrigin(
    anchor: PanelAnchor, size: NSSize, side: ExpansionSide, screen: CGRect? = nil
) -> NSPoint {
    let orb = surfaceSize(.orb)
    let origin: NSPoint
    switch side {
    case .left:
        origin = NSPoint(x: anchor.maxX - size.width, y: anchor.midY - size.height / 2)
    case .right:
        let orbLeft = anchor.maxX - orb.width
        origin = NSPoint(x: orbLeft, y: anchor.midY - size.height / 2)
    case .above:
        let orbBottom = anchor.midY - orb.height / 2
        origin = NSPoint(x: anchor.maxX - size.width, y: orbBottom)
    case .below:
        let orbTop = anchor.midY + orb.height / 2
        origin = NSPoint(x: anchor.maxX - size.width, y: orbTop - size.height)
    }
    guard let screen else { return origin }
    return NSPoint(
        x: clampedX(origin.x, sizeWidth: size.width, screen: screen),
        y: clampedY(origin.y, sizeHeight: size.height, screen: screen))
}

func resizeOrigin(
    current: NSRect, newSize: NSSize, side: ExpansionSide, screen: CGRect? = nil
) -> NSPoint {
    let origin: NSPoint
    switch side {
    case .left:
        origin = NSPoint(x: current.maxX - newSize.width, y: current.midY - newSize.height / 2)
    case .right:
        origin = NSPoint(x: current.minX, y: current.midY - newSize.height / 2)
    case .above:
        origin = NSPoint(x: current.maxX - newSize.width, y: current.minY)
    case .below:
        origin = NSPoint(x: current.maxX - newSize.width, y: current.maxY - newSize.height)
    }
    guard let screen else { return origin }
    return NSPoint(
        x: clampedX(origin.x, sizeWidth: newSize.width, screen: screen),
        y: clampedY(origin.y, sizeHeight: newSize.height, screen: screen))
}

struct PanelAnchor: Codable, Equatable {
    var maxX: Double
    var midY: Double
}

enum AnchorStore {
    static func defaultBase() -> URL {
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return base.appendingPathComponent("com.akshit2434.orbit", isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(
            "com.akshit2434.orbit", isDirectory: true)
    }

    static func url(base: URL? = nil) -> URL {
        (base ?? defaultBase()).appendingPathComponent("anchor.json")
    }

    static func load(base: URL? = nil) -> PanelAnchor? {
        guard let data = try? Data(contentsOf: url(base: base)) else { return nil }
        return try? JSONDecoder().decode(PanelAnchor.self, from: data)
    }

    static func save(_ anchor: PanelAnchor, base: URL? = nil) {
        let file = url(base: base)
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            NSLog("orbit: anchor save mkdir failed: %@", error.localizedDescription)
            return
        }
        do {
            let data = try JSONEncoder().encode(anchor)
            try data.write(to: file, options: .atomic)
        } catch {
            NSLog("orbit: anchor save failed: %@", error.localizedDescription)
        }
    }
}

func workedString(elapsed: TimeInterval) -> String {
    let total = Int(elapsed)
    if total < 60 {
        return "Worked for \(total)s"
    }
    return "Worked for \(total / 60)m \(total % 60)s"
}

struct DragSample: Sendable {
    var point: CGPoint
    var at: TimeInterval
}

/// Velocity (pt/s) from the last ≤3 samples within a 120ms window, else .zero.
func flingVelocity(_ samples: [DragSample]) -> CGVector {
    guard samples.count >= 2, let endAt = samples.last?.at else { return .zero }
    let recent = Array(samples.suffix(3)).filter { endAt - $0.at <= 0.12 }
    guard recent.count >= 2,
          let first = recent.first, let last = recent.last
    else { return .zero }
    let dt = last.at - first.at
    guard dt > 0 else { return .zero }
    return CGVector(
        dx: (last.point.x - first.point.x) / dt,
        dy: (last.point.y - first.point.y) / dt)
}

/// Keeps a release projection energetic without allowing one noisy pointer
/// sample to teleport the panel across a display.
func boundedThrow(_ velocity: CGVector, horizon: Double = 0.16, maximum: Double = 180) -> CGVector {
    var projected = CGVector(dx: velocity.dx * horizon, dy: velocity.dy * horizon)
    let length = hypot(projected.dx, projected.dy)
    guard length > maximum, length > 0 else { return projected }
    let scale = maximum / length
    projected.dx *= scale
    projected.dy *= scale
    return projected
}

/// Edge hysteresis: ×0.35 when within 24pt of the edge, else unchanged.
func hysteresisDamped(delta: CGVector, distanceToEdge: Double) -> CGVector {
    guard distanceToEdge < 24 else { return delta }
    return CGVector(dx: delta.dx * 0.35, dy: delta.dy * 0.35)
}

/// Directional edge hysteresis: ×0.35 only when within 24pt of the nearest
/// edge AND moving toward it, else unchanged.
///
/// Sign convention: delta is gesture-space (SwiftUI DragGesture: +width =
/// right, +height = down). movePanel(by:) applies origin.x += dx,
/// origin.y -= dy (AppKit origin bottom-left), so +height moves toward the
/// bottom edge and -height toward the top. Verified against movePanel(by:).
func hysteresisDamped(
    delta: CGVector, left: Double, right: Double, bottom: Double, top: Double
) -> CGVector {
    let nearest = min(left, right, bottom, top)
    guard nearest < 24 else { return delta }
    let towardNearest =
        (left == nearest && delta.dx < 0)
        || (right == nearest && delta.dx > 0)
        || (bottom == nearest && delta.dy > 0)
        || (top == nearest && delta.dy < 0)
    guard towardNearest else { return delta }
    return CGVector(dx: delta.dx * 0.35, dy: delta.dy * 0.35)
}

/// Tiling defense: keep the frame ≥2pt inside the visible frame.
func clampedDragFrame(_ frame: NSRect, screen: CGRect) -> NSRect {
    let inset: CGFloat = 2
    let minX = screen.minX + inset
    let maxX = screen.maxX - frame.width - inset
    let minY = screen.minY + inset
    let maxY = screen.maxY - frame.height - inset
    var clamped = frame
    clamped.origin.x = min(max(frame.origin.x, minX), max(minX, maxX))
    clamped.origin.y = min(max(frame.origin.y, minY), max(minY, maxY))
    return clamped
}

/// Final AppKit boundary invariant: the complete panel frame stays inside the
/// visible display regardless of which mode or transition requested it.
func containedPanelFrame(_ frame: NSRect, screen: CGRect, margin: CGFloat = 12) -> NSRect {
    var result = frame
    let usableWidth = max(0, screen.width - margin * 2)
    let usableHeight = max(0, screen.height - margin * 2)
    result.size.width = min(result.width, usableWidth)
    result.size.height = min(result.height, usableHeight)
    result.origin.x = min(max(result.minX, screen.minX + margin), screen.maxX - result.width - margin)
    result.origin.y = min(max(result.minY, screen.minY + margin), screen.maxY - result.height - margin)
    return result
}
