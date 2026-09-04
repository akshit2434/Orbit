# Orbit

Orbit is an ambient AI layer for macOS and connected accounts—an AI second pair of hands that understands the user’s context and acts where work already happens.

## Engineering context

The product vision, architecture, stack, interaction model, priorities, and initial vertical slices are documented in [Engineering Context](docs/engineering-context.md). The locked visual and interaction contract for the floating surface is documented in [Orb UI Style](docs/orb-ui-style.md). The current SwiftUI prototype scope and implementation decisions are tracked in [Prototype Context](docs/prototype-context.md).

## Direction

- Native macOS application built with Swift and SwiftUI.
- Voice-first interaction with a persistent floating orb.
- Structured local context, local browser actions, and connected APIs.
- Solari for isolated, long-running, parallel cloud execution.
- Progressive UI that exposes only the complexity the current task requires.

## Status

Early product and architecture definition. The native floating shell is rebuilt on a single mode enum per the hand sketch (orb → voice pill → thinking bubble → short output → big card with timer, copy, text+mic input, and docked orb); implementation proceeds in vertical slices, beginning with “See + Talk.”

## Floating surface

The floating shell uses two coordinated native panels: a permanently fixed 80×92 orb panel and an independently sized/clamped attached panel for voice, thinking, output, card, and history. The orb owns pointer-locked dragging and magnetic edge settling; opening another mode never resizes or re-anchors it. Neither panel participates in native macOS movement or tiling.

The anchor (`maxX`, `midY`) persists to `anchor.json` under `Application Support/com.akshit2434.orbit` (restored on launch when still on-screen), with `UserDefaults` as fallback. Replies carry a `Worked for Xs` duration that freezes at completion. Thinking, output, card, composer, and history surfaces are opaque white with high-contrast close controls; glass remains reserved for the orb/voice surface. The card uses a compact chat structure: orb/duration header, chronological prompt/reply body with per-response copy controls, and a bottom-pinned composer. History is session-only (newest 50 turns) and renders inside the card.

## Run the SwiftUI prototype

The repository now includes a native macOS SwiftUI interaction prototype. It runs as a light-mode accessory process with a borderless, always-on-top floating orb rather than a conventional main window. With Xcode 16+ installed, launch it from the repository root:

```bash
swift run Orbit
```

Click the orb to open its live microphone waveform. Hover the waveform to reveal cancel and send controls; Escape cancels and Return sends. In live mode, send finalizes the local WAV recording, transcribes it through AssemblyAI, and submits the transcript. macOS will request microphone access the first time the interaction opens.

## See + Talk

The prototype now answers short voice/text prompts with tool-gated context:

- **See:** "What am I looking at?" collects the front app + window and requests a screenshot note; pasted text is only included when present; clipboard is only read when explicitly allowed. Denied/unavailable sources degrade to a graceful `.unavailable` path — never a leak.
- **Talk:** Send (or Return) goes thinking → the reply streams token-by-token into a chat card under the capsule → idle. While context tools collect, a one-line hint names them (e.g. `glancing at your screen… noting the front app…`). Replies are history-aware: the last 6 turns travel with each request so follow-ups resolve from conversation. Escape cancels the in-flight stream; the close cross (or Escape) dismisses the card.

### Text testing without a mic

```bash
swift run Orbit -- --mock-voice
```

With `--mock-voice`, an inject field appears under the expanded capsule: type a transcript and press Return to run the full Talk path with `MockVoiceSession` (no microphone, no network key required).

### Keys (`.env.local`, never committed)

Copy nothing into the repo; create an untracked `.env.local` at the repo root with any of these names:

- `OPENROUTER_API_KEY` — enables live answers via OpenRouter chat completions.
- `OPENROUTER_MODEL` — model name (default `openai/gpt-4o-mini`).
- `ASSEMBLYAI_API_KEY` — enables live mic transcription when the voice send arrow is pressed; `--mock-voice` uses `MockVoiceSession` instead.

Without keys the app still runs: `OpenRouterClient` falls back to a local stub reply (`Heard: … | app: … | screenshot: … | paste: … chars.`) so the whole See + Talk flow is exercisable offline.

## History chat

Hover the orb while it is collapsed to reveal a clock button; clicking it opens the history popout. Turns are listed newest-first; selecting one rereads that transcript + reply, with Back returning to the list. The chat card carries an `Ask…` field (Return sends through the same streaming pipeline) plus a mic button to start voice input. Empty Enter never collapses anything: an empty send keeps the surface open.

Turns live in selectable in-memory threads, each capped at the newest 50 turns. The selected thread receives every orb and card prompt until a different thread is selected or a new one is created from the card header. Its chronological recent turns are sent with each model request, so follow-ups have real thread memory. Collapsing the card does not cancel background work; explicit cancel still does. The store sits behind the `ChatStoring` protocol so disk persistence can slot in later.
