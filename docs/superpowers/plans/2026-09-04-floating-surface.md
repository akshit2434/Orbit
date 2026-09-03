# Floating surface rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the floating surface per the hand sketch on one mode enum: edge-aware bubble/card placement, magnetic springy drag, file-based position persistence, timer + copy on replies.

**Architecture:** A single `surfaceMode` drives view, panel size, and placement; legacy `isExpanded`/`chatOpen` become computed views of mode so nothing disagrees; anchor persists to JSON; drag snaps to edges with a spring.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit NSPanel, NSAnimationContext, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-04-floating-surface-design.md`

## Global Constraints

- macOS v15+ only, Swift tools 6.0, light-mode accessory panel behavior unchanged.
- Orb contract: 30px orb in 56px canvas, ~220ms smooth morph, ~460ms state color interp, no focus rings, drag threshold low and single (no fighting gestures), Escape cancels / Return sends.
- Violet thinking; red reserved for approval/error. Capsule copy-free; words in bubble/card.
- History session-only, newest first, cap 50, compression future.
- `.env.local` never committed; keys never logged. One mode-transition log line stays until headed confirm.
- Every task ends with `swift build`, `git diff --check`, and a commit.

---

## File Map

- Create `Sources/Orbit/SurfaceMode.swift` — mode enum, size table, side selection, anchor store.
- Modify `Sources/Orbit/OrbitApp.swift` — mode property, computed legacy flags, controller resize/place/persist/drag-snap.
- Modify `Sources/Orbit/OrbitShellView.swift` — sketch layouts per mode (bubble left of orb, card, timer, copy, input).
- Create `Tests/OrbitTests/SurfaceTests.swift` — size table, side matrix, persistence round-trip, timer format, transitions.

---

### Task 1: Mode + sizes + persistence core

**Files:**
- Create: `Sources/Orbit/SurfaceMode.swift`
- Modify: `Sources/Orbit/OrbitApp.swift` (add mode, computed flags, rewire resize/persist; views untouched)
- Test: `Tests/OrbitTests/SurfaceTests.swift`

**Interfaces:**
- Consumes: existing model flags (read-only during migration).
- Produces: `enum SurfaceMode: Equatable, Sendable { case orb, voice, thinking, output, card, history }`, `func surfaceSize(_ mode: SurfaceMode) -> NSSize` (orb 80×92, voice 218×76, thinking 250×80, output 250×120, card 320×400, history 320×400), `enum ExpansionSide: Equatable { case left, right, above, below }`, `func expansionSide(anchorX: Double, anchorY: Double, screen: CGRect) -> ExpansionSide` (nearest-edge wins; left/right beat above/below on ties), `struct PanelAnchor: Codable, Equatable { var maxX: Double; var midY: Double }`, `enum AnchorStore { static func url(base: URL) -> URL; static func load(base: URL) -> PanelAnchor?; static func save(_ anchor: PanelAnchor, base: URL) }` (base defaults to Application Support/com.akshit2434.orbit; tests pass temp dir).

Model mapping (exact): add `@Published var mode: SurfaceMode = .orb`; `isExpanded` becomes computed `mode == .voice`; `chatOpen` becomes computed `mode == .thinking || mode == .output || mode == .card || mode == .history`. All existing writers (`activate`, `cancel`, `send`, `submit`, `openHistory`, `closeChat`) set `mode` instead: activate→.voice, submit→.thinking then .output on finish, empty send→.voice, openHistory→.history, closeChat/cancel→.orb, card expand→.card. Resize/persist observe `$mode`. Keep the temporary resize NSLog, adding mode.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Orbit

final class SurfaceTests: XCTestCase {
    func testSizeTable() {
        XCTAssertEqual(surfaceSize(.orb), NSSize(width: 80, height: 92))
        XCTAssertEqual(surfaceSize(.voice), NSSize(width: 218, height: 76))
        XCTAssertEqual(surfaceSize(.thinking), NSSize(width: 250, height: 80))
        XCTAssertEqual(surfaceSize(.output), NSSize(width: 250, height: 120))
        XCTAssertEqual(surfaceSize(.card), NSSize(width: 320, height: 400))
    }
    func testSideFollowsNearestEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(expansionSide(anchorX: 950, anchorY: 400, screen: screen), .left)
        XCTAssertEqual(expansionSide(anchorX: 50, anchorY: 400, screen: screen), .right)
        XCTAssertEqual(expansionSide(anchorX: 500, anchorY: 750, screen: screen), .below)
        XCTAssertEqual(expansionSide(anchorX: 500, anchorY: 50, screen: screen), .above)
    }
    func testAnchorRoundTrip() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        XCTAssertNil(AnchorStore.load(base: base))
        AnchorStore.save(PanelAnchor(maxX: 1236, midY: 554), base: base)
        XCTAssertEqual(AnchorStore.load(base: base), PanelAnchor(maxX: 1236, midY: 554))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter SurfaceTests`
Expected: FAIL (`surfaceSize`, `expansionSide`, `AnchorStore` undefined).

- [ ] **Step 3: Create `SurfaceMode.swift`** with the exact types above. Side rule: compute distances to each edge from anchor point; pick min; tie-break left/right over above/below.

- [ ] **Step 4: Rewire model** — add `mode`, convert flags to computed, update the six writers, observe `$mode` for resize/persist (drop the `$isExpanded`/`$chatOpen` sinks), keep NSLog with mode. Views compile untouched (they read the same flag names).

- [ ] **Step 5: Verify** — `swift test --filter SurfaceTests` PASS, full suite, `swift build`, `git diff --check`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Orbit/SurfaceMode.swift Sources/Orbit/OrbitApp.swift Tests/OrbitTests/SurfaceTests.swift
git commit -m "feat(surface): add mode enum with sizes, sides, file persistence"
```

---

### Task 2: Sketch layouts per mode

**Files:**
- Modify: `Sources/Orbit/OrbitShellView.swift`
- Test: extend `Tests/OrbitTests/SurfaceTests.swift` (timer format only; layout is headed)

**Interfaces:**
- Consumes: `mode`, `streamText`, `hintText`, `store`, `SurfaceMode` sizes.
- Produces: per-mode views. Voice: existing capsule untouched. Thinking: bubble left of orb with hint text ("Thinking…" then tool phrases). Output: short bubble + close top-left + click expands to card. Card: timer ("Worked for 3s" from first token, ticking each second), full reply, copy button (NSPasteboard, no fancy feedback), text+mic input row, orb docked at edge, history list inside card. All swaps blur+fade in existing timing.

Timer format (exact, tested): `func workedString(elapsed: TimeInterval) -> String` → under 60s: "Worked for \(Int)s"; 60s+: "Worked for \(m)m \(s)s". Lives in SurfaceMode.swift (pure).

- [ ] **Step 1: Failing test**

```swift
func testWorkedString() {
    XCTAssertEqual(workedString(elapsed: 3), "Worked for 3s")
    XCTAssertEqual(workedString(elapsed: 64), "Worked for 1m 4s")
}
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement views** — switch on mode; keep orb/capsule/mic code byte-identical; add bubble (left of orb, close top-left), card (320×400, timer row, copy, input, history list reusing store, ScrollView capped), transitions `.blurReplace.combined(with: .opacity)`.
- [ ] **Step 4: Verify** — tests PASS, full suite, build, diff-check. Headed owed (Task 4 + user).
- [ ] **Step 5: Commit**

```bash
git add Sources/Orbit/SurfaceMode.swift Sources/Orbit/OrbitShellView.swift Tests/OrbitTests/SurfaceTests.swift
git commit -m "feat(surface): build sketch layouts with timer and copy"
```

---

### Task 3: Edge placement + magnetic drag

**Files:**
- Modify: `Sources/Orbit/OrbitApp.swift` (placement, drag-snap, persist points)
- Test: extend `SurfaceTests.swift` (nearest-edge pure function)

**Interfaces:**
- Consumes: `expansionSide`, `AnchorStore`, mode sizes.
- Produces: `func snapTarget(current: NSRect, screen: CGRect) -> NSPoint` (nearest edge origin with 12pt margin, pure, tested); drag moves panel live with single low-threshold gesture (remove the fighting WindowDragGesture+threshold pair); on release, NSAnimationContext spring (damping ~0.8, ~0.35s) to snap target, then persist anchor to file; placement computes panel origin from anchor + mode size + side (bubble extends toward screen center).

- [ ] **Step 1: Failing test**

```swift
func testSnapTargetsNearestEdge() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let near = NSRect(x: 900, y: 400, width: 80, height: 92)
    let p = snapTarget(current: near, screen: screen)
    XCTAssertEqual(p.x, 1000 - 80 - 12, accuracy: 0.5)
}
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** — pure `snapTarget` in SurfaceMode.swift; controller drag/snap/persist; single gesture in view calling `model.drag(to:)` / `model.endDrag()`; delete the old dual-gesture code.
- [ ] **Step 4: Verify** — tests, suite, build, diff-check.
- [ ] **Step 5: Commit**

```bash
git add Sources/Orbit/SurfaceMode.swift Sources/Orbit/OrbitApp.swift Tests/OrbitTests/SurfaceTests.swift Sources/Orbit/OrbitShellView.swift
git commit -m "feat(surface): add edge-aware placement and magnetic drag"
```

---

### Task 4: Cleanup + docs + headed protocol

**Files:**
- Modify: `Sources/Orbit/OrbitApp.swift` (remove diagnostic NSLog, remove `resultText` property + last writers)
- Modify: `README.md`, `docs/prototype-context.md`, `docs/orb-ui-style.md` (amend locked contract: modes, sides, magnetics, file persistence)
- Test: none new (removals verified by full suite staying green)

- [ ] **Step 1: Remove NSLog + resultText**, fix compile fallout if any.
- [ ] **Step 2: Update docs** — modes table, placement rule, drag feel, persistence path, timer/copy, sketch as target (reference image described, not embedded).
- [ ] **Step 3: Verify** — full `swift test`, `swift build`, `git diff --check`, `git status` (`.env.local` untracked).
- [ ] **Step 4: Commit and push**, then hand the user the headed checklist: relaunch persistence, four-edge flips, springy snap, full sketch walkthrough with screenshot.

```bash
git add Sources/Orbit/OrbitApp.swift README.md docs/prototype-context.md docs/orb-ui-style.md
git commit -m "docs(surface): finalize rebuild, remove diagnostics"
git push origin main
```
