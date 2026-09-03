# Orbit Floating UI Style

This document is the visual and interaction contract for Orbit's primary floating interface.

## Idle orb

- The visible orb is 30 px.
- Its minimum pointer target and render canvas are 56 px.
- Glow must decay fully inside the render canvas; a window or view boundary must never be visible.
- Idle motion is subtle breathing and slow internal drift.

## Expanded surface

- The waveform surface is approximately 190 × 44 px.
- It uses a translucent accent-colored glass capsule with a fine white highlight.
- The waveform is white, streams from right to left, is amplified near the center, and fades into softly blurred edges.
- No labels or status copy appear in the primary surface.
- Cancel and send controls replace the waveform on hover.
- Escape cancels and Return sends.
- Dragging the orb repositions it and must never activate it; buttons never show macOS focus rings.

## Motion

- Expansion and collapse use a smooth, non-bouncy transition around 220 ms.
- Native window bounds must expand before the visual surface and collapse after it, preventing clipping.
- State colors interpolate over approximately 460 ms.
- Within a state, color remains stable; motion comes from breathing, fluid drift, and live audio.
- Thinking has stronger breathing than idle without rapid hue or brightness changes.

## State color semantics

- Idle: calm blue.
- Listening: focused blue/cyan.
- Thinking: violet.
- Working: deep indigo.
- Red is reserved for approval-required or error states and must not appear on a timer.

## Modes and panel sizes

One `SurfaceMode` drives view, panel size, and placement. Panel sizes (points):

- orb 80×92, voice 218×76, thinking 250×80, output 250×120, card 320×400, history 320×400.
- The card content view is 296 wide with 12 pt padding, so it fills the 320 pt panel exactly; its height is content-driven within the 400 pt panel (reply scroll capped at 140, history list at 90, orb docked at the edge).
- History renders inside the card. Legacy `isExpanded`/`chatOpen`/`historyOpen` flags are retired; `isExpanded` and `chatOpen` remain only as computed views of mode.

## Placement (edge-aware)

- Near the right edge the bubble/card extend left; near the left edge they extend right; near the top they open below; near the bottom above.
- Corner rule: the nearest edge wins; left/right beat above/below on ties.
- Above/below placement clamps the panel's x origin on-screen with a 12 pt margin.

## Drag feel (magnetic, springy)

- The orb travels freely while dragged (single low-threshold gesture, never activates on drag) and on release glides to the nearest screen edge with a 12 pt margin via a ~0.35 s ease-out animation, then sticks there — never free-floating mid-screen at rest.
- The anchor persists only after the snap completes, so a quit mid-animation never keeps a stale pre-snap position.
- Native window bounds expand before the visual surface appears and collapse ~0.24 s after it, preventing clipping.

## Position persistence (file)

- The anchor (`maxX`, `midY`) persists to `anchor.json` under `Application Support/com.akshit2434.orbit` on every snap and launch; it is restored on launch when it still intersects a visible screen.
- `UserDefaults` (`orbit.panel.anchorX` / `orbit.panel.centerY`) is kept as a fallback. File-based because the dev binary's defaults domain proved unreliable across runs.

## Card behavior

- Violet thinking treatment; red stays reserved for approval/error and never appears on a timer.
- Live tool phrases until the first token, then a `Worked for Xs` timer (minutes past 60 s) ticking each second from the first streamed token.
- Copy button writes the reply to `NSPasteboard` and does nothing when the reply is empty (never clears the pasteboard for nothing).
- Text `Ask…` field plus mic button send through the same streaming pipeline; empty Enter never collapses anything.
- Close cross plus Escape return to the orb; closing mid-stream cancels and drops late tokens.
- Capsule copy-free rule stands; all words live in the bubble/card.

## Product behavior

- The orb is the primary interface and runs in a borderless, always-on-top accessory panel.
- Opening the full application is never the default response to clicking the orb.
- The interface should remain responsive with one click and must not treat the orb's hit target as draggable window background.
