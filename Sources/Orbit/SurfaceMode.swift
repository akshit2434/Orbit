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
