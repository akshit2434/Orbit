# Two-panel floating surface refactor

> Historical implementation plan. The implemented system subsequently added a third edge-aware history-control panel and persistent local threads. See [Prototype Context](../../prototype-context.md).

## Goal

Replace the timing-sensitive, dynamically resized panel with two coordinated native panels:

- A fixed 80×92 orb panel that exclusively owns dragging, throwing, snapping, hover discovery, and anchor persistence.
- A separate attached surface panel that renders voice, thinking, output, card, and history modes without changing the orb panel’s frame.

The refactor must preserve thread memory and background work while making panel overflow, stale resize layout, macOS tiling, and post-card edge bias structurally impossible.

## Non-goals

- No redesign of orb artwork or chat typography during the architecture migration.
- No disk persistence for chat threads.
- No new provider, microphone, or context features.
- No commit of visual changes until the user completes headed verification.

## Architecture

```text
OrbitAppDelegate
  └─ FloatingSurfaceCoordinator
      ├─ OrbPanel (always 80×92)
      │   └─ OrbRootView
      ├─ SurfacePanel (mode-sized, independently clamped)
      │   └─ AttachedSurfaceView
      └─ OrbitPanelModel (shared state, queries, threads)
```

The coordinator owns all native window behavior. SwiftUI views emit user intent but never calculate global panel origins or resize native windows.

## Invariants

1. Orb panel size never changes after creation.
2. Orb drag samples use absolute screen coordinates and preserve the initial grab offset.
3. Both panels are non-native-movable, non-main, non-tileable utility panels.
4. Every native frame write passes through visible-screen containment.
5. Surface placement is a pure function of orb anchor, surface size, preferred side, and screen visible frame.
6. Surface panel cannot change the persisted orb anchor.
7. Collapsing or hiding either UI surface never implicitly cancels a query.
8. Explicit cancel remains the only UI action that cancels active work.
9. Card focus and keyboard input may make the surface panel key without changing window ordering or anchor state.
10. Voice/thinking/output/card transitions animate inside the surface panel; they never resize the orb panel.

## Task 1: Extract pure two-panel geometry

Files:

- Modify `Sources/Orbit/SurfaceMode.swift`
- Extend `Tests/OrbitTests/SurfaceTests.swift`

Implement:

- `OrbAnchor` containing the orb panel’s screen-space center.
- `surfaceFrame(mode:anchor:preferredSide:screen:)` returning a completely contained frame.
- Side fallback order when the preferred side lacks room: preferred, opposite, then perpendicular side with the most available area.
- Surface-to-orb gap of 4–8 pt without overlap.
- Oversize-safe behavior for displays smaller than card dimensions.
- Separate `snapTarget` operating only on the fixed orb frame.

Tests:

- Six surface modes × four edges × four corners.
- Non-zero and negative screen origins.
- Menu-bar and Dock visible-frame offsets.
- Small displays and multi-monitor boundary points.
- No surface/orb overlap and no frame overflow.
- Mode transitions never alter the input orb anchor.

Verification:

```bash
swift test --filter SurfaceTests
swift build
git diff --check
```

## Task 2: Introduce the native window coordinator

Files:

- Create `Sources/Orbit/FloatingSurfaceCoordinator.swift`
- Modify `Sources/Orbit/OrbitApp.swift`
- Extend `Tests/OrbitTests/SurfaceTests.swift`

Implement:

- Construct one fixed orb `NSPanel` and one attached surface `NSPanel`.
- Share one `OrbitPanelModel` between both hosting views.
- Keep both panels above normal windows and across Spaces using the existing accessory behavior.
- Configure both panels as manually positioned, non-main, and non-native-movable.
- Surface panel becomes key only for text input.
- Mode changes show, hide, or internally transition the surface panel; they never resize the orb panel.
- Move the attached panel whenever the orb frame changes.
- Persist only the orb anchor after snap completion.
- Re-place both panels when screen configuration changes.

Tests:

- Coordinator-facing geometry accepts no uncontained frame.
- Surface hide/show leaves orb frame unchanged.
- Persistence always records the orb frame, never the surface frame.
- Display removal selects a surviving screen and clamps both panels.

## Task 3: Split SwiftUI roots and interaction ownership

Files:

- Modify `Sources/Orbit/OrbitShellView.swift`
- Modify `Sources/Orbit/OrbitApp.swift`
- Extend model tests where behavior changes.

Implement:

- `OrbRootView`: orb rendering, orb-only drag gesture, delayed history affordance.
- `AttachedSurfaceView`: voice, thinking, output, card, and history rendering.
- Remove global frame assumptions and trailing alignment from the combined root.
- Make the card’s blank header region a coordinated drag handle that moves the orb anchor and both panels.
- Keep header buttons clickable by requiring the existing low drag threshold.
- Hover history appears only from orb hover, remains while moving onto the control, and hides 500 ms after leaving both.
- Surface close means collapse/hide; cancel remains explicit.

Verification:

- Unit/model tests for collapse versus cancel.
- History hover timing tested through a small state helper rather than timers embedded only in the view.
- Build and diff check.

## Task 4: Preserve query and thread semantics

Files:

- Modify `Sources/Orbit/OrbitApp.swift`
- Modify `Sources/Orbit/ChatStore.swift` only if required
- Extend `Tests/OrbitTests/ChatModelTests.swift`
- Extend `Tests/OrbitTests/ChatStoreTests.swift`

Implement and verify:

- Every prompt targets the thread selected when submission begins.
- The selected thread’s chronological recent turns are passed into `TalkSession`.
- Completion is appended to the originating thread even if the user collapses, selects another thread, or creates a new thread meanwhile.
- A collapsed completion does not automatically reopen the attached panel.
- Opening chat later displays the completed turn.
- New threads render an empty state, never a synthetic “Thinking…” row.
- Card submissions remain in card mode.

Tests:

- Collapse during streaming, then reopen originating thread.
- Switch threads during streaming and verify completion routing.
- Create a new thread during streaming and verify isolation.
- Follow-up request contains only selected-thread history.
- Explicit cancel records no late turn.

## Task 5: Headed visual and interaction matrix

Run with:

```bash
swift run Orbit -- --mock-voice
```

User-visible matrix:

- Drag orb slowly and quickly from its center and off-center grab points.
- Throw toward every edge and pull away after snapping.
- Touch all macOS tiling hotspots; no split-screen UI may appear.
- Open every surface mode at left, right, top, bottom, and all corners without corrective dragging.
- Confirm neither panel crosses the active screen’s visible frame.
- Move between monitors with different origins/scales.
- Open and close card repeatedly; no tall intermediate frame or anchor shift.
- Drag card from blank header space; controls remain clickable.
- Verify orb-only history hover and 500 ms dismissal.
- Exercise two threads, background collapse, thread switching, and new-thread empty state.

Capture screenshots for each failed case. Iterate without committing visual changes until the user explicitly approves the headed result.

## Task 6: Cleanup, docs, and final verification

After headed approval:

- Remove the combined dynamically resized panel code and obsolete resize helpers.
- Remove temporary mode/layout diagnostics.
- Update `README.md`, `docs/engineering-context.md`, `docs/prototype-context.md`, and `docs/orb-ui-style.md` to describe the implemented two-panel contract.
- Run the complete suite and build.
- Commit implementation in tested slices, then push.

Final gate:

```bash
swift test
swift build
git diff --check
git status --short
```

## Acceptance criteria

- Orb movement remains pointer-locked and independent of surface mode.
- macOS never offers split-screen/tiling while dragging Orbit.
- No rendered surface can leave the active screen’s visible frame.
- Opening or closing chat cannot move or bias the orb toward an edge.
- Voice/thinking/output/card never require a corrective drag to lay out correctly.
- Thread memory and background completion behavior pass automated tests and headed checks.
- Visual changes are committed only after explicit user approval.
