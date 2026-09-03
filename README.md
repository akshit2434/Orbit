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

Early product and architecture definition. The first native floating-shell prototype is in place; implementation will proceed in vertical slices, beginning with “See + Talk.”

## Run the SwiftUI prototype

The repository now includes a native macOS SwiftUI interaction prototype. It runs as a light-mode accessory process with a borderless, always-on-top floating orb rather than a conventional main window. With Xcode 16+ installed, launch it from the repository root:

```bash
swift run Orbit
```

Click the orb to open its live microphone waveform. Hover the waveform to reveal cancel and send controls; Escape cancels and Return sends. macOS will request microphone access the first time the interaction opens.

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
- `ASSEMBLYAI_API_KEY` — enables live mic transcription; without it (or with `--mock-voice`) the shell uses `MockVoiceSession`.

Without keys the app still runs: `OpenRouterClient` falls back to a local stub reply (`Heard: … | app: … | screenshot: … | paste: … chars.`) so the whole See + Talk flow is exercisable offline.

## History chat

Hover the orb while it is collapsed to reveal a clock button; clicking it opens the history popout. Turns are listed newest-first; selecting one rereads that transcript + reply, with Back returning to the list. The chat card carries an `Ask…` field (Return sends through the same streaming pipeline) plus a mic button to start voice input. Empty Enter never collapses anything: an empty send keeps the surface open.

Turns live in an in-memory `ChatStore` capped at the newest 50 (`ChatStore.cap`); older turns drop until summarization-based compression lands. The store sits behind the `ChatStoring` protocol so persistence can slot in later.
