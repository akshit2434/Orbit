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

Working native prototype with the floating-shell, live/mock voice input, model-directed screen and clipboard tools, streaming replies, persistent local threads, explicit generation lifecycle, and three-panel edge-safe UI implemented. Browser control, connected accounts, cloud execution/sync, history compression, and spoken responses remain future slices.

## Floating surface

The floating shell uses three coordinated native panels: a fixed 56×56 orb panel, an independently sized/clamped panel for voice/thinking/output/chat, and a small hover-only history panel. The orb owns pointer-locked dragging and magnetic edge settling; attached surfaces calculate from its visible footprint and appear toward available screen space. No panel participates in native macOS movement or tiling.

The anchor (`maxX`, `midY`) persists to `anchor.json` under `Application Support/com.akshit2434.orbit` (restored on launch when still on-screen), with `UserDefaults` as fallback. Replies carry a `Worked for Xs` duration that freezes at completion. Thinking, output, card, composer, and history surfaces are opaque white with high-contrast close controls; glass remains reserved for the orb/voice surface. The card uses a compact chat structure: orb/duration header, chronological prompt/reply body with per-response copy controls, and a bottom-pinned composer. Threads and their currently uncapped turn histories persist locally.

## Run the SwiftUI prototype

The repository now includes a native macOS SwiftUI interaction prototype. It runs as a light-mode accessory process with a borderless, always-on-top floating orb rather than a conventional main window. With Xcode 16+ installed, launch it from the repository root:

```bash
swift run Orbit
```

Click the orb to open its live microphone waveform. Hover the waveform to reveal cancel and send controls; Escape cancels and Return sends. In live mode, send finalizes the local WAV recording, transcribes it through AssemblyAI, and submits the transcript. macOS will request microphone access the first time the interaction opens.

## See + Talk

The prototype now answers short voice/text prompts with tool-gated context:

- **See:** OpenRouter chooses when to call `capture_screen`, `read_clipboard`, or `load_screenshot`; there is no production keyword router. Captured PNGs exclude Orbit's windows, are stored as thread attachments, and can be loaded by the model on later turns. Tool failures return readable context instead of pretending the model saw something.
- **Talk:** Send (or Return) goes thinking → token stream → completed, failed, or cancelled. A thread permits one generation at a time; its composer becomes a stop control while working, and collapsing does not cancel it. Failed, cancelled, and interrupted turns stay visible with Retry/Remove but are excluded from model history. Completed history is currently uncapped and sent in full.

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

Without keys the app still runs: `OpenRouterClient` falls back to a local stub reply (`Heard: … | app: … | screenshot: … | paste: … chars.`), and deterministic tool selection remains available only for offline tests.

Threads, selected-thread identity, outcomes, timings, and tool metadata are saved locally in `Application Support/com.akshit2434.orbit/chat-store.json`. Screenshot attachments are stored under its `attachments` directory and removed with their owning turn. This local-first format is the future cloud-sync boundary.

## History chat

Hover the orb while it is collapsed to reveal a clock button; clicking it opens the history popout. Turns are listed newest-first; selecting one rereads that transcript + reply, with Back returning to the list. The chat card carries an `Ask…` field (Return sends through the same streaming pipeline) plus a mic button to start voice input. Empty Enter never collapses anything: an empty send keeps the surface open.

The clock uses its own edge-aware panel. A coordinator samples the pointer against the orb and clock frames, keeping the clock present while crossing the gap and dismissing it 0.5 seconds after leaving both. Its fade/scale animation runs from the same synchronous state, avoiding stale cross-window hover events.

Turns live in selectable, locally persisted threads with no current turn cap. The selected thread receives every orb and card prompt until a different thread is selected or a new one is created from the card header. All eligible chronological turns are sent with each model request, so follow-ups have real thread memory. Collapsing the card does not cancel background work; the stop-generating control does. The store remains behind `ChatStoring` as the future cloud-sync boundary.
