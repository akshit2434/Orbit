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
      ├─ fixed orb NSPanel + independently clamped attached-surface NSPanel
      ├─ position restoration and persistence
      └─ OrbitPanelModel
          ├─ SurfaceMode (orb / voice / thinking / output / card / history) + OrbitState
          ├─ mockText / askText / streamText / hintText / workStart / isMockVoice (+ computed isExpanded / chatOpen)
          ├─ selectedTurn + ChatStore (persistent local threads, uncapped turns + attachment files)
          ├─ MicrophoneMonitor
          ├─ ContextService (active-app, pastedText, clipboard-gated, permission-aware screenshot)
          ├─ TalkSession (TalkController.selectTools → ContextService.collectForRequest → token stream via OpenRouterTokenStreamer, history-aware messages)
          └─ VoiceSession (MockVoiceSession with --mock-voice, else AssemblyAISTTSession)
```

The executable is packaged with Swift Package Manager. `Support/Info.plist` supplies the accessory-app and microphone usage metadata required by the panel and audio path. `EnvLoader` builds `OrbitConfig` from process env over repo-root `.env.local` (key names: `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `ASSEMBLYAI_API_KEY`); without keys the Talk path degrades to a local stub reply so the UI flow stays testable offline.

## Interaction contract

### Idle

The visible orb is 30 px inside a 56 px interaction canvas. It breathes slowly, has soft internal fluid motion, and remains draggable.

### Modes

One `SurfaceMode` drives attached content while `FloatingSurfaceCoordinator` owns three windows. The 56×56 orb panel exclusively owns drag/snap persistence. Voice, thinking, output, card, and history render in a separate panel placed from the stable visual-orb footprint by `attachedSurfacePlacement`. The hover history button has its own 36×36 panel and appears on the available side opposite the nearest edge, so it never relies on an out-of-window offset or clips. Preferred-side fallback and final visible-frame containment prevent overflow without moving the orb. Interactive hosting views accept first-mouse events.

### Listening

A stationary click expands the native panel before the visual capsule appears. The microphone monitor starts, and the capsule shows only the live waveform until the user hovers it. Hover reveals the cancel and send buttons.

### Thinking

Send stops microphone capture, collapses the surface, and moves the orb to the thinking color and stronger breathing treatment. `OrbitPanelModel.submit(transcript:)` then streams `TalkSession.answerStream(transcript:history:onHint:onToken)` on a cancellable task: tool hints land in `hintText` (one line naming the fired tools), tokens accumulate in `streamText` (chat card under the collapsed capsule), and the orb returns to idle at completion. Each request carries the last 6 stored turns (`TalkController.messages`) so follow-ups resolve from history. When no key is configured the stream yields the stub reply as a single token. Escape cancels the task and clears the card; closing the card mid-stream cancels and drops late tokens.

Empty input never collapses the surface: `send()` with a blank field keeps the orb expanded and opens the chat card instead, and `submit` ignores blank transcripts outright (the Enter fix).

### Live and mock voice

In live mode, `MicrophoneMonitor` writes the same input tap used by the waveform to a temporary WAV. Pressing send finalizes that file, `AssemblyAISTTSession` transcribes it, and the transcript enters the normal thread-aware answer pipeline. Launched with `--mock-voice`, the model uses `MockVoiceSession` and shows a text inject field while expanded (Return submits).

### Input precedence

Pointer movement takes precedence over activation. A small drag threshold prevents a drag from being interpreted as a click. Only the orb/voice surface owns the drag gesture, so selecting text and operating card controls cannot move the panel. Drag samples use absolute `NSEvent.mouseLocation` coordinates and preserve the initial pointer-to-panel offset, avoiding feedback drift as the window moves. The panel is key-capable but neither main-window-capable nor natively movable; all motion is applied explicitly, which keeps macOS window tiling out of the interaction. Release projection is bounded before the magnetic settle. The orb and action buttons opt out of macOS focus effects so keyboard shortcuts do not add a blue focus ring.

### Dialogue surfaces

Thinking and output bubbles sit 4 pt from the orb. Non-orb dialogue surfaces are opaque white with dark text, a subtle border, and soft shadow; close controls are white crosses on black circles. Expanding a completed output opens the same conversation as a compact chat layout: header with orb and frozen work duration, chronological prompt/reply turns in the scrollable body, an adjacent copy control under every assistant response, and the composer pinned at the bottom. `currentTranscript` keeps the active prompt renderable before store publication. Card close fades and collapses after 100 ms to avoid a tall intermediate frame. The orb and voice capsule retain the translucent glass treatment.

## State and service boundaries

`OrbitPanelModel` owns only shell state and user intent for this prototype. Services stay separate:

- `VoiceSession` (real: `AssemblyAISTTSession`; mock: `MockVoiceSession`) delivers final transcripts into `submit(transcript:)`; the view never sees provider callbacks.
- With an OpenRouter key, `OpenRouterToolPlanner` gives the model native `capture_screen`, `read_clipboard`, and (when available) `load_screenshot` tools. Production tool choice is model-directed; the legacy phrase selector is used only by nil-key test mode.
- `ContextService.collectForRequest(tools:)` executes only selected tools. Clipboard content is read once when the clipboard tool runs. Screen capture checks permission, captures the pointer's display while excluding Orbit's windows, and reports `captured`, `permissionDenied`, or `unavailable` distinctly.
- Streaming runs through typed `StreamEvent`s. Transport errors cannot masquerade as assistant tokens. `TalkController.messages(transcript:context:history:)` sends every completed turn and excludes failed, cancelled, interrupted, and generating turns. Tool-selected PNG data is encoded as an OpenRouter `image_url` data URL.
- `ChatStore` persists selectable local `ChatThread`s, selected-thread identity, uncapped turns, outcomes, duration, and tool metadata atomically. PNG attachments live beside the JSON store and are deleted when their turn is removed. A restored `.generating` turn becomes `.interrupted`. This storage seam is intended for later frequent cloud synchronization.
- A thread accepts only one generation at a time. Submission immediately creates a `.generating` turn and starts its timer; collapse and orb activation preserve work, while Stop records `.cancelled`. Failed/cancelled/interrupted turns provide Retry/Remove and never enter model memory.
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

The first listening interaction may prompt for microphone access; the first explicit screen-related request may prompt for Screen Recording access. The current verification baseline is a successful `swift build`, the full `swift test` suite, a clean `git diff --check`, `.env.local` untracked, plus the Task 3 live E2E matrix (streaming multi-token replies, history memory probes, screen/app tools with hint, clipboard-denied no-leak, denied-screen graceful completion, empty-Enter stays open, long-reply completion, store-level reread; mic round-trip headed-only) with stub-mode parity via the nil-key tests. Automated coverage verifies that ordinary prompts do not invoke capture, explicit screen prompts do, permission denial remains distinguishable, and PNG bytes are serialized into the documented multimodal request shape. Full GUI manual checklist with `--mock-voice` remains owed in a headed session because accessory-only panels are not exposed to the current UI automation inventory.

## Next vertical slice

The floating-surface refactor is implemented; the original two-panel implementation plan remains as historical context at [Two-panel floating surface refactor](superpowers/plans/2026-09-04-two-panel-surface-refactor.md). The history control subsequently moved into a third dedicated panel to support unclipped edge-aware placement.

Live microphone audio is captured as WAV and sent through `AssemblyAISTTSession.transcribeWAV`; the resulting transcript enters the same selected-thread streaming path as typed input. Mock voice and nil-key fallbacks remain available for deterministic local testing.

The next storage enhancement is periodic history/image compression before cloud sync. Browser/active-window titles, connected accounts, and Solari execution remain future tools behind the same model-directed boundary.
