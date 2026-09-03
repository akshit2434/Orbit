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
