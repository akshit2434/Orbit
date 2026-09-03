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
    case .orb: NSSize(width: 80, height: 92)
    case .voice: NSSize(width: 218, height: 76)
    case .thinking: NSSize(width: 250, height: 80)
    case .output: NSSize(width: 250, height: 120)
    case .card: NSSize(width: 320, height: 400)
    case .history: NSSize(width: 320, height: 400)
    }
}

enum ExpansionSide: Equatable {
    case left
    case right
    case above
    case below
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
