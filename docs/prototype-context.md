# Orbit Native Prototype Context

This document records the scope and decisions of the current macOS floating-shell prototype. It is a working implementation reference alongside the broader [Engineering Context](engineering-context.md) and the locked [Orb UI Style](orb-ui-style.md) contract.

## Scope

The prototype answers one product question: can Orbit feel like a persistent macOS presence while keeping the full application out of the way?

It validates:

- A borderless, always-on-top floating orb.
- A light-mode visual language with a restrained liquid-glass waveform surface.
- A direct click-to-listen interaction.
- Real microphone amplitude feeding a streaming waveform.
- Keyboard-first completion and cancellation.
- Position persistence across launches.
- A clean separation between the floating shell and future reasoning/tool services.

It does not yet implement spoken responses, browser control, connected accounts, or Solari execution. Speech recognition (AssemblyAI), text replies (OpenRouter), and tool-gated screen/clipboard context now exist behind the boundaries below.

## Runtime shape

```text
OrbitApp
  └─ OrbitAppDelegate
      ├─ accessory NSPanel
      ├─ position restoration and persistence
      └─ OrbitPanelModel
          ├─ SurfaceMode (orb / voice / thinking / output / card / history) + OrbitState
          ├─ mockText / askText / streamText / hintText / workStart / isMockVoice (+ computed isExpanded / chatOpen)
          ├─ selectedTurn + ChatStore (selectable in-memory threads, cap 50 turns each)
          ├─ MicrophoneMonitor
          ├─ ContextService (active-app, pastedText, clipboard-gated, screenshot note)
          ├─ TalkSession (TalkController.selectTools → ContextService.collect → token stream via OpenRouterTokenStreamer, history-aware messages)
          └─ VoiceSession (MockVoiceSession with --mock-voice, else AssemblyAISTTSession)
```

The executable is packaged with Swift Package Manager. `Support/Info.plist` supplies the accessory-app and microphone usage metadata required by the panel and audio path. `EnvLoader` builds `OrbitConfig` from process env over repo-root `.env.local` (key names: `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `ASSEMBLYAI_API_KEY`); without keys the Talk path degrades to a local stub reply so the UI flow stays testable offline.

## Interaction contract

### Idle

The visible orb is 30 px inside a 56 px interaction canvas. It breathes slowly, has soft internal fluid motion, and remains draggable.

### Modes

One `SurfaceMode` drives the view, the panel size, and edge-aware placement (see the locked contract in [Orb UI Style](orb-ui-style.md)): orb 80×92, voice 218×76, thinking 250×80, output 250×120, card/history 320×400. Thinking shows the hint bubble and output shows the short reply bubble (click expands to the card), mirrored by `ExpansionSide` so content extends toward the screen center (bubble-left only on `.left`, otherwise orb-left/bubble-right); card and history share the big card with the `Worked for Xs` timer, copy button, `Ask…` + mic input row, orb docked at the edge, and the session history list. The bubble/card extend toward the screen center based on the nearest edge (left/right win ties); above/below placement clamps x on-screen and all placements clamp y on-screen (12 pt margin, oversize-safe). Dragging moves the panel live and releases with a ~0.35 s magnetic snap to the nearest edge (12 pt margin); the anchor persists to `anchor.json` under `Application Support/com.akshit2434.orbit` only after the snap completes. The retired `resultText` property is removed; one `orbit: mode=` log line stays until headed confirm.

### Listening

A stationary click expands the native panel before the visual capsule appears. The microphone monitor starts, and the capsule shows only the live waveform until the user hovers it. Hover reveals the cancel and send buttons.

### Thinking

Send stops microphone capture, collapses the surface, and moves the orb to the thinking color and stronger breathing treatment. `OrbitPanelModel.submit(transcript:)` then streams `TalkSession.answerStream(transcript:history:onHint:onToken)` on a cancellable task: tool hints land in `hintText` (one line naming the fired tools), tokens accumulate in `streamText` (chat card under the collapsed capsule), and the orb returns to idle at completion. Each request carries the last 6 stored turns (`TalkController.messages`) so follow-ups resolve from history. When no key is configured the stream yields the stub reply as a single token. Escape cancels the task and clears the card; closing the card mid-stream cancels and drops late tokens.

Empty input never collapses the surface: `send()` with a blank field keeps the orb expanded and opens the chat card instead, and `submit` ignores blank transcripts outright (the Enter fix).

### Mock voice

Launched with `--mock-voice`, the model uses `MockVoiceSession` and shows a text inject field while expanded (Return submits). This exercises the full Think → answer → result path without microphone or network keys.

### Input precedence

Pointer movement takes precedence over activation. A small drag threshold prevents a drag from being interpreted as a click. Only the orb/voice surface owns the drag gesture, so selecting text and operating card controls cannot move the panel. Drag samples use absolute `NSEvent.mouseLocation` coordinates and preserve the initial pointer-to-panel offset, avoiding feedback drift as the window moves. The panel is key-capable but neither main-window-capable nor natively movable; all motion is applied explicitly, which keeps macOS window tiling out of the interaction. Release projection is bounded before the magnetic settle. The orb and action buttons opt out of macOS focus effects so keyboard shortcuts do not add a blue focus ring.

### Dialogue surfaces

Thinking and output bubbles sit 4 pt from the orb. Non-orb dialogue surfaces are opaque white with dark text, a subtle border, and soft shadow; close controls are white crosses on black circles. Expanding a completed output opens the same conversation as a compact chat layout: header with orb and frozen work duration, chronological prompt/reply turns in the scrollable body, an adjacent copy control under every assistant response, and the composer pinned at the bottom. `currentTranscript` keeps the active prompt renderable before store publication. Card close fades and collapses after 100 ms to avoid a tall intermediate frame. The orb and voice capsule retain the translucent glass treatment.

## State and service boundaries

`OrbitPanelModel` owns only shell state and user intent for this prototype. Services stay separate:

- `VoiceSession` (real: `AssemblyAISTTSession`; mock: `MockVoiceSession`) delivers final transcripts into `submit(transcript:)`; the view never sees provider callbacks.
- `TalkController.selectTools(transcript:hasPaste:clipboardAllowed:)` is the only place that decides which `ContextTool`s fire: screen words → `.screenshot` + `.activeAppWindow`; non-empty paste → `.pastedText`; explicit opt-in → `.clipboard`. Nothing else can pull context.
- `ContextService.collect(tools:)` enforces the gates: clipboard reads only when `clipboardAllowed`, screenshot capture only appends a `screenshot-requested` note (async `captureScreenshot()` fills `screenshotPNG` separately), empty tools yield an empty bundle.
- Streaming runs through `TokenStreamer` (`OpenRouterTokenStreamer` live SSE via `StreamParse.tokenDeltas`, `StubTokenStreamer` in tests). `TalkController.messages(transcript:context:history:)` builds the prompt from the collected bundle plus the trailing history turns; `hintStrings(for:)` is the single source of the progress line.
- `ChatStore` (behind the `ChatStoring` persistence seam) owns selectable in-memory `ChatThread`s and keeps the newest 50 turns per thread. The selected thread receives orb and card prompts until the user creates or selects another thread. `submit` captures that thread ID, passes its chronological recent history into `TalkSession`, and appends completion back to the originating thread. `openHistory()` enters history mode with no stale timer; `closeChat()` only collapses and intentionally leaves active work running; explicit cancel still cancels.
- All panel frame writes pass through `containedPanelFrame`, including launch restoration, mode resize, live drag, release projection, edge snap, and delayed reassert. Tests cover every surface mode at all four off-screen corner requests on a non-zero-origin display.
- `OpenRouterClient.complete(transcript:context:)` builds the prompt only from the collected bundle (front-app name, pasted text, clipboard, screenshot flag) and falls back to the stub reply when no key is configured. API keys never appear in logs, replies, or diffs.
- Long-running work should have task IDs, parent/child relationships, cancellation, and observable progress from the beginning. (Today: the answer `Task` is cancellable on Escape/activate; deeper task tracking is still owed.)

The orb renderer remains provider-independent. AssemblyAI and OpenRouter are integrations behind `VoiceSession` / `OpenRouterClient`, not assumptions the view layer knows about.

## Development

From the repository root:

```bash
swift build
swift run Orbit
swift run Orbit -- --mock-voice   # text inject, no mic or keys needed
```

The first listening interaction may prompt for microphone access. The current verification baseline is a successful `swift build`, the full `swift test` suite, a clean `git diff --check`, `.env.local` untracked, plus the Task 3 live E2E matrix (streaming multi-token replies, history memory probes, screen/app tools with hint, clipboard-denied no-leak, denied-screen graceful completion, empty-Enter stays open, long-reply completion, store-level reread; mic round-trip headed-only) with stub-mode parity via the nil-key tests. Full GUI manual checklist with `--mock-voice` remains owed in a headed session because accessory-only panels are not exposed to the current UI automation inventory.

## Next vertical slice

Before further visual polish, refactor the floating shell from one dynamically resized panel into two coordinated panels: a stable orb panel and an independently clamped attached-surface panel. The implementation plan is [Two-panel floating surface refactor](superpowers/plans/2026-09-04-two-panel-surface-refactor.md).

Live microphone → `AssemblyAISTTSession.transcribeWAV` wiring is explicitly the next slice, not this merge: this merge covers the mock voice session plus the offline OpenRouter stub path only, with the real STT/LLM calls present but unwired to live mic audio. The next slice hooks captured WAV bytes to `transcribeWAV` and exercises the keyed path end to end.

The next meaningful slice is richer “See”: attach real screenshot bytes via `captureScreenshot()`, add browser/active-window titles, then connected accounts and Solari execution as internal tools behind the same gating pattern.
