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

It does not yet implement speech recognition, spoken responses, screen understanding, browser control, connected accounts, or Solari execution.

## Runtime shape

```text
OrbitApp
  └─ OrbitAppDelegate
      ├─ accessory NSPanel
      ├─ position restoration and persistence
      └─ OrbitPanelModel
          ├─ OrbitState
          └─ MicrophoneMonitor
```

The executable is packaged with Swift Package Manager. `Support/Info.plist` supplies the accessory-app and microphone usage metadata required by the panel and audio path.

## Interaction contract

### Idle

The visible orb is 30 px inside a 56 px interaction canvas. It breathes slowly, has soft internal fluid motion, and remains draggable.

### Listening

A stationary click expands the native panel before the visual capsule appears. The microphone monitor starts, and the capsule shows only the live waveform until the user hovers it. Hover reveals the cancel and send buttons.

### Thinking

Send stops microphone capture, collapses the surface, and moves the orb to the thinking color and stronger breathing treatment. The current prototype stops at this visual state; real reasoning will replace this transition later.

### Input precedence

Pointer movement takes precedence over activation. A small drag threshold prevents a native window drag from being interpreted as a click. The orb and action buttons opt out of macOS focus effects so keyboard shortcuts do not add a blue focus ring to the visual surface.

## State and service boundaries

`OrbitPanelModel` owns only shell state and user intent for this prototype. Keep future services separate:

- Voice provider events should map into `OrbitState` and audio levels through an adapter.
- Screen and active-window context should be collected by a local context service.
- Browser, connected-account, and Solari operations should be exposed as internal tools rather than embedded in the view.
- Long-running work should have task IDs, parent/child relationships, cancellation, and observable progress from the beginning.

The orb renderer should remain provider-independent. AssemblyAI and Solari are planned integrations, not assumptions the view layer should know about.

## Development

From the repository root:

```bash
swift build
swift run Orbit
```

The first listening interaction may prompt for microphone access. The current verification baseline is a successful `swift build`, a clean `git diff --check`, and manual validation of click, drag, hover, Escape, Return, and relaunch-position behavior on macOS.

## Next vertical slice

The next meaningful slice is “See + Talk”: add structured active-app, active-window, browser, and screenshot context, then connect a real voice session without coupling provider callbacks directly to the orb view.
