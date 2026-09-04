# Drag feel + tiling defense + card polish Implementation Plan

> Historical implementation plan. For the implemented interaction contract, use [Orb UI Style](../../orb-ui-style.md) and [Prototype Context](../../prototype-context.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Orb drag feels 1:1 with fluid throw and edge stickiness, the system tile never wins, and the card UI is opaque, readable, and always shows the trail.

**Architecture:** Pure physics helpers (velocity, hysteresis, clamp) stay testable outside the view; controller owns gesture → move → release → re-assert sequence; card view goes opaque white with a pinned current turn.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit NSPanel, XCTest.

**Spec:** hand sketch + approved follow-ups (opaque white card, thinking nudge, pinned trail). Prior specs still bind (modes, violet thinking, copy-free capsule, session history cap 50).

## Global Constraints

- macOS v15+ only, Swift tools 6.0, light-mode panel unchanged.
- Orb contract: 30px orb in 56px canvas, ~220ms morph, ~460ms interp, no focus rings, single gesture, Escape cancels / Return sends.
- Violet thinking; red for approval/error. Orb stays glassy; bubbles/card/rows opaque white with dark text.
- `.env.local` never committed; keys never logged. Keep the one `orbit: mode=` log line.
- Every task ends with `swift build`, `git diff --check`, and a commit.

---

## File Map

- Modify `Sources/Orbit/SurfaceMode.swift` — physics helpers + tests.
- Modify `Sources/Orbit/OrbitApp.swift` — gesture pipeline, re-assert, trail state.
- Modify `Sources/Orbit/OrbitShellView.swift` — opaque restyle, nudge, trail, input.
- Create/extend `Tests/OrbitTests/SurfaceTests.swift`.

---

### Task 1: Drag physics + tiling defense

**Files:**
- Modify: `Sources/Orbit/SurfaceMode.swift`, `Sources/Orbit/OrbitApp.swift`
- Test: `Tests/OrbitTests/SurfaceTests.swift`

**Interfaces:**
- Produces: `struct DragSample: Sendable { var point: CGPoint; var at: TimeInterval }`, `func flingVelocity(_ samples: [DragSample]) -> CGVector` (last ≤3 samples within 120ms, pt/s, else .zero), `func hysteresisDamped(delta: CGVector, distanceToEdge: Double) -> CGVector` (×0.35 when within 24pt of edge and moving away, else unchanged), `func clampedDragFrame(_ frame: NSRect, screen: CGRect) -> NSRect` (keep ≥2pt inside visible frame). Controller: `drag(to:withVelocity:)` moves 1:1 (no smoothing), `endDrag(velocity:)` projects `origin + v*0.18`, snaps, persists; schedules re-assert at +0.4s (reset frame to snap target only if drifted >2pt, single shot, cancelled by next drag).

- [ ] **Step 1: Failing tests**

```swift
func testFlingVelocityFromSamples() {
    let v = flingVelocity([
        DragSample(point: CGPoint(x: 0, y: 0), at: 0),
        DragSample(point: CGPoint(x: 60, y: 0), at: 0.06),
        DragSample(point: CGPoint(x: 120, y: 0), at: 0.12),
    ])
    XCTAssertEqual(v.dx, 1000, accuracy: 1)
    XCTAssertEqual(flingVelocity([]).dx, 0)
}

func testHysteresisDampsNearEdge() {
    let d = hysteresisDamped(delta: CGVector(dx: 10, dy: 0), distanceToEdge: 10)
    XCTAssertEqual(d.dx, 3.5, accuracy: 0.01)
    let far = hysteresisDamped(delta: CGVector(dx: 10, dy: 0), distanceToEdge: 200)
    XCTAssertEqual(far.dx, 10, accuracy: 0.01)
}
```

- [ ] **Step 2: Run, expect FAIL** (undefined symbols).
- [ ] **Step 3: Implement** helpers + controller pipeline; view passes velocity from gesture (track last samples in view or model — model owns samples array, view forwards translation+timestamp).
- [ ] **Step 4: Verify** — filter PASS, full suite, build, diff-check.
- [ ] **Step 5: Commit**

```bash
git add Sources/Orbit/SurfaceMode.swift Sources/Orbit/OrbitApp.swift Tests/OrbitTests/SurfaceTests.swift
git commit -m "feat(drag): add velocity fling, edge hysteresis, tile re-assert"
```

---

### Task 2: Opaque card UI (nudge, white, trail, input)

**Files:**
- Modify: `Sources/Orbit/OrbitShellView.swift`
- Test: none new (visual; guarded by build + existing suite)

**Interfaces:**
- Consumes: mode, streamText, hintText, store, selectedTurn, askText/mockText.
- Produces: thinking/output bubbles with 6pt leading nudge (close overlaps bubble edge -4pt); all chat surfaces opaque white (`Color.white` fills, `.primary`/`.secondary` text, hairline `.black.opacity(0.1)` stroke, soft shadow `.black.opacity(0.12)` radius 8 y 2); card pins current turn on top (transcript caption-secondary + reply primary, or selectedTurn in reread mode with Back); history trail below with visible affordance; input row rebuilt (borderless field, gray-12 fill, radius 8, no bezel, mic 24px, Return sends); orb glass unchanged.

- [ ] **Step 1: Implement** per above; keep sizes/positions/modes/transitions, change only fills/text/gaps/trail/input.
- [ ] **Step 2: Verify** — full suite green (no behavior change expected), `swift build`, `git diff --check`, headed owed.
- [ ] **Step 3: Commit**

```bash
git add Sources/Orbit/OrbitShellView.swift
git commit -m "feat(card): opaque white surfaces, pinned trail, fresh input"
```

---

### Task 3: Side audit + docs + final

**Files:**
- Modify: `Sources/Orbit/OrbitShellView.swift` (any mode ignoring side, esp. voice), `README.md`, `docs/prototype-context.md`, `docs/orb-ui-style.md`
- Test: extend `SurfaceTests.swift` for any new pure logic; visual rest headed

**Interfaces:**
- Every mode (orb, voice, thinking, output, card, history) renders fully on-screen on all four edges given the side-aware origin math; voice capsule mirrors like bubbles.

- [ ] **Step 1: Audit each mode's view against side**; fix voice/any stragglers to mirror; add tests for pure parts.
- [ ] **Step 2: Update docs** — opaque card, drag feel, tiling defense, trail, input.
- [ ] **Step 3: Verify** — full suite, build, diff-check, status (`.env.local` untracked).
- [ ] **Step 4: Commit and push**, then hand user the headed checklist (drag feel, tile fight at edges, off-screen edges with mode-log paste, thinking nudge, trail, input).

```bash
git add Sources/Orbit/OrbitShellView.swift Tests/OrbitTests/SurfaceTests.swift README.md docs/prototype-context.md docs/orb-ui-style.md
git commit -m "feat(surface): side audit and polish docs"
git push origin main
```
