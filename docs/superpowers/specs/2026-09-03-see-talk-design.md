# See + Talk — Design (2026-09-03)

> Historical design record. For implemented behavior, use [Prototype Context](../../prototype-context.md) and [Orb UI Style](../../orb-ui-style.md).

## Goal
First functional vertical slice: user clicks orb, speaks or injects text, Orbit uses explicitly-gated local context and returns a text reply. Validates persistent-shell + tool-gated context + provider-independent voice without building full duplex audio, browser control, or cloud execution.

Non-goals: TTS/speaking audio, Chrome extension DOM, Accessibility actions, Solari delegation, persistent memory, full Orbit window.

## Context decisions
- Minimal but tool-gated. Nothing is always attached.
- Tools: `screenshot`, `activeAppWindow`, `pastedText` (explicit user paste), `clipboardIfAllowed` (opt-in, permission-gated).
- Screenshot/screen info only fetched when the turn needs it, never by default.
- Copy-paste path: user can paste text into the turn as a separate context item distinct from clipboard polling.

## Architecture
```
OrbitPanelModel (shell state only)
  ├─ VoiceSession (protocol)
  │    ├─ MockVoiceSession (text inject, no mic)
  │    └─ AssemblyAISTTSession (later, real STT)
  ├─ ContextService (gated tools)
  └─ TalkController (transcript + selected tools → text reply)
```

- `OrbitPanelModel` owns `OrbitState` + `isExpanded` + user intent only.
- Orb view (`OrbitShellView`) sees state, audio levels, and result string. No direct imports of AssemblyAI, ScreenCaptureKit, or AppKit context APIs in views.
- Voice provider events map into `OrbitState` via adapter: audio level → listening animation, final transcript → thinking, reply ready → result/idle, error → idle (red only for hard error/approval per orb-ui-style).
- Context tools are internal functions with explicit capability checks, not embedded in the view.

## Components
- `Sources/Orbit/ContextService.swift` (new): on-demand tools with permission handling and compact return types (downscaled image ref, app/bundleID + window title, pasted string, clipboard string-or-unavailable).
- `Sources/Orbit/VoiceSession.swift` (new): protocol `start/stop`, callbacks `onLevel/onFinalTranscript/onError`. `MockVoiceSession` supports launch-arg or debug-field text injection for headless testing before STT exists.
- `Sources/Orbit/TalkController.swift` (new): orchestrates one turn. Input: transcript + tool selection. Output: text reply. First version uses a stub responder (echo + context summary, e.g. app name + whether screenshot was used). LLM swap later behind same interface.
- `Sources/Orbit/OrbitApp.swift` (edit): wire services into model, keep panel size/position/drag/collapse behavior unchanged.
- `Sources/Orbit/OrbitShellView.swift` (edit): add minimal text-result presentation following progressive UI (`◉━━ result`), preserving 190×44 capsule, ~220 ms morph, no layout shift, no status copy in primary surface.

## Data flow
1. Idle orb breathes. Stationary click → panel expands first, then capsule → `listening`, mic monitor or mock session starts.
2. User speaks or tester injects text. Live levels drive waveform only.
3. Send/Return → stop capture, collapse surface → `thinking`.
4. TalkController selects tools via explicit v1 rules (no LLM tool-choice yet): prompts containing "looking at", "screen", or "seeing" → `screenshot` + `activeAppWindow`; non-empty paste buffer → `pastedText` included; `clipboardIfAllowed` only when user explicitly toggles it for that turn. All other prompts default to no context tools.
5. Stub responder returns text. Orb shows small result, returns to `idle`.
6. Escape at any point cancels to `idle` with no side effects.

## Error handling
- Mic denied: remain usable via text inject; no crash, no red.
- Screen recording denied: screenshot tool returns `.unavailable`, reply discloses it plainly.
- Clipboard denied/unavailable: tool returns `.unavailable`, never blocks turn.
- STT error: back to `idle`, preserve orb stability. Red reserved for approval-required or hard error states.

## Testing
- `swift build` + `git diff --check` clean.
- Manual on macOS: click vs drag disambiguation, hover reveals cancel/send, Escape cancels, Return sends, position persists across relaunch.
- Headless/internal: `MockVoiceSession` text prompts (e.g. "what am I looking at?", "summarize this pasted text: ...") with tools individually enabled/disabled; verify screenshot/clipboard are not fetched unless requested.
- Permission-denied paths: mic denied, screen denied, clipboard denied.

## Success criteria
- Click-to-text-reply works end-to-end with mock injection and no STT key.
- No turn attaches screenshot, screen info, or clipboard unless the tool was explicitly selected/granted.
- Orb UI contract (sizes, motion, colors, no focus rings, drag never activates) still holds.
- Swapping mock → AssemblyAI STT requires only a new `VoiceSession` conformance, no view changes.
