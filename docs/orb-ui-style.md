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

- The orb panel is permanently 80×92. All non-orb modes render in a separate attached panel; mode changes never resize the orb window.

- orb 80×92, voice 218×76, thinking 250×80, output 250×120, card 320×400, history 320×400.
- The card content view is card outer 296 (content 272 after padding) + 12pt trailing inset = 308 within the 320pt panel; height content-driven ≤400 (reply scroll capped at 140, history list at 90, orb docked at the edge).
- History renders inside the card. Legacy `isExpanded`/`chatOpen`/`historyOpen` flags are retired; `isExpanded` and `chatOpen` remain only as computed views of mode.

## Placement (edge-aware)

- Near the right edge the bubble/card extend left; near the left edge they extend right; near the top they open below; near the bottom above.
- Corner rule: the nearest edge wins; left/right beat above/below on ties.
- Above/below placement clamps the panel's x origin on-screen with a 12 pt margin.

## Drag feel (magnetic, springy)

- Dragging is owned by the orb/voice surface, not attached dialogue or card content. It uses absolute screen mouse coordinates plus the initial grab offset, so moving the panel cannot make the gesture drift away from the cursor.
- Release velocity projects for 0.16 s and is capped to 180 pt before the surface glides to the nearest screen edge with a 12 pt margin via a ~0.35 s ease-out animation, then sticks there — never free-floating mid-screen at rest.
- The `NSPanel` is key-capable for text input but cannot become the main window and is not natively movable. Orbit alone moves it with `setFrame`, preventing macOS edge tiling/split-screen from taking over.
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
- Thinking, output, card, input, and history surfaces are opaque white with dark text, a hairline dark border, and a soft shadow. Translucent glass is reserved for the orb/voice surface.
- Close controls use a black circular background with a white cross and remain inside or intentionally overlap their owning surface.
- Expanding a completed output shows the current user prompt and assistant response as one dialogue turn. Earlier turns remain available below as complete prompt/response pairs; the composer is visually separate.
- Card layout is header (orb, frozen work duration, close), chronological scrollable chat, then a composer pinned to the bottom. Each assistant response owns its adjacent copy control.
- Work duration freezes when streaming completes; it never continues counting in a completed output/card.
- Card close uses a short opacity transition and the native panel collapses after 100 ms, avoiding a tall intermediate exit frame.
- Closing a thinking/output/card surface collapses it without cancelling the active query. Completion is recorded in its originating thread while the orb stays collapsed.
- Chat submissions remain in card mode. The selected thread receives every orb and card prompt until the user selects another thread or creates a new one.
- The card header includes thread selection and new-thread controls. Thread histories are isolated and the selected thread's chronological turns are passed to the model.
- The composer is one flat neutral bar with borderless text and an integrated voice control; nested fields and detached controls are prohibited.
- Capsule copy-free rule stands; all words live in the bubble/card.

## Product behavior

- The orb is the primary interface and runs in a borderless, always-on-top accessory panel.
- Opening the full application is never the default response to clicking the orb.
- The interface should remain responsive with one click and must not treat the orb's hit target as draggable window background.
- Every native frame mutation passes through `containedPanelFrame`; launch, restore, resize, drag, throw, snap, and reassert keep the complete panel inside the active screen's visible frame.
