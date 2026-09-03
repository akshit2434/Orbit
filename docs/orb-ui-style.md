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

## Product behavior

- The orb is the primary interface and runs in a borderless, always-on-top accessory panel.
- Opening the full application is never the default response to clicking the orb.
- The interface should remain responsive with one click and must not treat the orb's hit target as draggable window background.
