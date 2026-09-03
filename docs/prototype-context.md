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
          ├─ OrbitState (+ resultText / debugText / isMockVoice)
          ├─ MicrophoneMonitor
          ├─ ContextService (active-app, pastedText, clipboard-gated, screenshot note)
          ├─ TalkSession (TalkController.selectTools → ContextService.collect → OpenRouterClient.complete)
          └─ VoiceSession (MockVoiceSession with --mock-voice, else AssemblyAISTTSession)
```

The executable is packaged with Swift Package Manager. `Support/Info.plist` supplies the accessory-app and microphone usage metadata required by the panel and audio path. `EnvLoader` builds `OrbitConfig` from process env over repo-root `.env.local` (key names: `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `ASSEMBLYAI_API_KEY`); without keys the Talk path degrades to a local stub reply so the UI flow stays testable offline.

## Interaction contract

### Idle

The visible orb is 30 px inside a 56 px interaction canvas. It breathes slowly, has soft internal fluid motion, and remains draggable.

### Listening

A stationary click expands the native panel before the visual capsule appears. The microphone monitor starts, and the capsule shows only the live waveform until the user hovers it. Hover reveals the cancel and send buttons.

### Thinking

Send stops microphone capture, collapses the surface, and moves the orb to the thinking color and stronger breathing treatment. `OrbitPanelModel.submit(transcript:)` then awaits `TalkSession.answer(transcript:)` on a cancellable task; the answer lands in `resultText` (small 2-line bubble under the collapsed capsule) and the orb returns to idle. Escape cancels the task and clears the result.

### Mock voice

Launched with `--mock-voice`, the model uses `MockVoiceSession` and shows a text inject field while expanded (Return submits). This exercises the full Think → answer → result path without microphone or network keys.

### Input precedence

Pointer movement takes precedence over activation. A small drag threshold prevents a native window drag from being interpreted as a click. The orb and action buttons opt out of macOS focus effects so keyboard shortcuts do not add a blue focus ring to the visual surface.

## State and service boundaries

`OrbitPanelModel` owns only shell state and user intent for this prototype. Services stay separate:

- `VoiceSession` (real: `AssemblyAISTTSession`; mock: `MockVoiceSession`) delivers final transcripts into `submit(transcript:)`; the view never sees provider callbacks.
- `TalkController.selectTools(transcript:hasPaste:clipboardAllowed:)` is the only place that decides which `ContextTool`s fire: screen words → `.screenshot` + `.activeAppWindow`; non-empty paste → `.pastedText`; explicit opt-in → `.clipboard`. Nothing else can pull context.
- `ContextService.collect(tools:)` enforces the gates: clipboard reads only when `clipboardAllowed`, screenshot capture only appends a `screenshot-requested` note (async `captureScreenshot()` fills `screenshotPNG` separately), empty tools yield an empty bundle.
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

The first listening interaction may prompt for microphone access. The current verification baseline is a successful `swift build`, 21/21 `swift test`, a clean `git diff --check`, `.env.local` untracked, and manual validation of click, drag, hover, Escape, Return, and relaunch-position behavior on macOS. Full GUI manual checklist with `--mock-voice` remains owed in a headed session (Task 7 recorded it N/A-headless with build/test evidence).

## Next vertical slice

The next meaningful slice is richer “See”: attach real screenshot bytes via `captureScreenshot()`, add browser/active-window titles, then connected accounts and Solari execution as internal tools behind the same gating pattern.
