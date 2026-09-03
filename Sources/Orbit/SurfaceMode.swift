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

func placementOrigin(anchor: PanelAnchor, size: NSSize, side: ExpansionSide) -> NSPoint {
    let orb = surfaceSize(.orb)
    switch side {
    case .left:
        return NSPoint(x: anchor.maxX - size.width, y: anchor.midY - size.height / 2)
    case .right:
        let orbLeft = anchor.maxX - orb.width
        return NSPoint(x: orbLeft, y: anchor.midY - size.height / 2)
    case .above:
        let orbBottom = anchor.midY - orb.height / 2
        return NSPoint(x: anchor.maxX - size.width, y: orbBottom)
    case .below:
        let orbTop = anchor.midY + orb.height / 2
        return NSPoint(x: anchor.maxX - size.width, y: orbTop - size.height)
    }
}

func resizeOrigin(current: NSRect, newSize: NSSize, side: ExpansionSide) -> NSPoint {
    switch side {
    case .left:
        return NSPoint(x: current.maxX - newSize.width, y: current.midY - newSize.height / 2)
    case .right:
        return NSPoint(x: current.minX, y: current.midY - newSize.height / 2)
    case .above:
        return NSPoint(x: current.maxX - newSize.width, y: current.minY)
    case .below:
        return NSPoint(x: current.maxX - newSize.width, y: current.maxY - newSize.height)
    }
}

struct PanelAnchor: Codable, Equatable {
    var maxX: Double
    var midY: Double
}

enum AnchorStore {
    static func defaultBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.akshit2434.orbit", isDirectory: true)
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
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(anchor) {
            try? data.write(to: file, options: .atomic)
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
