# Orbit: Engineering Context

## Product Vision

Orbit is an ambient AI layer over the user's Mac and connected accounts.

Goal:
Enable technical and non-technical users to use AI inside their normal daily workflows with almost no friction.

Orbit should feel like part of macOS, not like another chatbot or desktop app.

Core mental model:

> AI as a second pair of hands attached to your computer. It sees what you see, understands what you are doing, and can act where the work already happens.

The full Orbit window should rarely need to open.

---

# Core Product Behaviors

Orbit should eventually be able to:

- Understand what the user is currently viewing.
- Understand active app/window/browser context.
- Use recent workflow context without repeated copy-pasting.
- Accept natural voice and text instructions.
- Respond conversationally in real time.
- Act inside the local browser.
- Perform lightweight actions on the local Mac.
- Act through connected APIs/accounts.
- Delegate large, long-running, isolated, or parallel tasks to cloud computers.
- Continue cloud work while the user keeps using their Mac.
- Ask for confirmation before sensitive/destructive actions.
- Surface results without forcing the user into a chat window.

Example:

User:

> "Research all the companies on this page and tell me which ones are worth contacting."

Orbit:

1. Reads the current browser context.
2. Extracts the companies.
3. Launches multiple Solari cloud browsers.
4. Researches them in parallel.
5. User continues working normally.
6. Orbit surfaces completion/results through the floating UI.

---

# Engineering Strategy

Build Orbit in vertical slices.

Do NOT block the product on perfect arbitrary macOS computer control.

Highest-priority areas:

1. Voice agent
2. Solari cloud execution
3. Screen/context understanding
4. Local browser interaction
5. Connected services
6. Limited native Mac actions
7. General-purpose local computer control later

The product should become useful long before arbitrary desktop control is solved.

## Current prototype snapshot

The repository currently contains a native macOS SwiftUI prototype for Orbit's primary floating surface. It is intentionally a shell for interaction and visual validation, not the finished agent runtime.

- `swift run Orbit` launches a borderless, always-on-top accessory panel.
- The panel defaults to a small light-mode orb and does not open a conventional app window on click.
- Clicking the orb expands a compact accent-colored glass capsule with a live microphone waveform.
- The waveform is backed by `AVAudioEngine` input levels and is amplified at the center with softened edges.
- Hovering the expanded surface reveals cancel and send actions.
- Escape cancels the current listening state and Return sends it into the thinking state.
- The orb can be dragged without triggering activation; stationary clicks activate it.
- The panel position is persisted relative to the screen edge and restored on relaunch.
- The prototype uses SwiftUI for rendering and AppKit `NSPanel` for accessory-window behavior and native window dragging.

The visual and interaction rules for this shell are authoritative in [Orb UI Style](orb-ui-style.md). Keep provider integrations, context collection, and agent routing behind internal abstractions as those slices are added.

### Planned panel architecture

The current prototype uses one dynamically resized `NSPanel`. A planned refactor will split this into a permanently fixed-size orb panel plus a separate attached surface panel for voice, thinking, output, and chat. This keeps drag geometry stable, isolates surface layout and screen clamping, and removes resizing/tiling behavior from the orb window. See [Two-panel floating surface refactor](superpowers/plans/2026-09-04-two-panel-surface-refactor.md).

---

# Native macOS Stack

Orbit is a native macOS application.

Primary stack:

- Swift
- SwiftUI
- AppKit where lower-level macOS window/control APIs are required
- Metal / SwiftUI shaders / Core Animation for the orb
- AVFoundation for local audio capture/playback plumbing
- macOS Accessibility APIs for native UI inspection/actions
- ScreenCaptureKit / native macOS capture APIs for screen/window context
- Chrome extension for strong browser context/control
- AssemblyAI for realtime voice
- Solari for cloud browsers, sandboxes, and desktops

Do NOT use Electron, React, Three.js, or a web-wrapper architecture for the main app.

---

# UI / UX Vision

Orbit should feel like a persistent system presence.

## Default UI

Normally the only visible UI is a small floating orb.

Properties:

- Borderless
- Transparent background
- Always on top
- Draggable
- Snaps/magnetizes to screen edges
- Remembers position
- Minimal distraction when idle
- Smooth, premium motion
- No harsh rectangular UI unless necessary

The orb should use:

- Blended blurred 3D gradients
- Soft depth
- Breathing animation
- Fluid internal movement
- Audio-reactive animation
- Minimal visible edges
- Faded / blurred transitions

Possible implementation:
SwiftUI + Metal shader with state/audio/time parameters.

---

# Orb States

Keep state vocabulary small.

## Idle

- Almost static
- Very slow breathing/internal drift

## Listening

- Reacts gently to microphone amplitude
- Slight expansion
- More active fluid movement

## Thinking

- Internal gradients fold/swirl
- No traditional spinner

## Speaking

- Smooth audio-reactive motion

## Working

- Subtle visual signal indicating autonomous/cloud work
- Should not become distracting

## Needs Approval

- Attached UI automatically appears with approve/cancel controls

---

# Orb Interaction Model

## Hover

Very subtle enlargement/brightness.

May expose minimal affordance such as:
"Ask Orbit"

## Click

Do NOT open the full application.

The orb should fluidly expand/morph into a small attached control surface.

Example concept:
```
◉━━━━ waveform ━ cancel ━ send
```

Possible contents:

- Live waveform
- Cancel
- Send
- Optional text/keyboard mode

Clicking the orb can immediately start listening.

The orb remains visually connected to the expanded UI.

---

# No Layout Shift Rule

UI transitions should feel continuous.

Avoid:

- New rectangular dialogs suddenly appearing
- Reflowing controls
- Hard modal transitions
- Abrupt component mounts/resizes

Prefer:

- Fixed overlay coordinates
- Transform/opacity/mask animations
- Fluid container morphing
- Hidden controls already occupying final geometry
- Restrained spring animations
- Soft blur/fade transitions

Conceptually:

orb
↓
orb stretches
↓
orb━━waveform━━controls

Not:

orb
↓
new dialog appears

---

# Progressive UI Principle

Hard product rule:

> Orbit should expand only as much as the current interaction requires.

Typical states:

Idle:
◉

Voice:
◉━━━━ waveform

Approval:
◉━━━━ action ✓ ×

Background task:
◉━━━━ 4 agents working

Small result:
◉━━━━ result

Complex work/settings:
Full Orbit window

---

# Full Orbit Application

A conventional application window exists but is secondary.

Use it for:

- Profile
- Appearance/theme
- Voice settings
- Connected apps
- Permissions
- Context/memory controls
- Cloud workers
- Activity history
- Advanced settings
- Viewing complex agent execution/results

Normal user interaction should rarely require opening it.

---

# Execution Architecture
```
                 ┌─ Local screen/context
                 │
```

Voice ──► Orbit Brain ──► Local browser
│
├─► Lightweight native actions
│
├─► Connected APIs
│
└─► Solari
├─ Cloud browsers
├─ Sandboxes
└─ Full desktops

---

# AssemblyAI Role

AssemblyAI is the main realtime voice layer.

Responsibilities:

- Speech-to-text
- Realtime conversational audio
- Turn detection
- Barge-in / interruption
- Voice activity
- Tool-call integration where useful

Orbit should maintain its own reasoning/state/tool orchestration layer rather than coupling product logic tightly to the voice provider.

AssemblyAI events should map into UI state, e.g.:

listening + amplitude
thinking
speaking
idle

Orb rendering should remain provider-independent.

---

# Solari Role

Solari provides Orbit's remote execution layer.

Use it for:

## Cloud Browsers

- Web research
- Automated browsing
- Clicking/forms/navigation
- Logged-in cloud workflows
- Parallel web tasks

## Profiles

- Persist cloud browser login/session state

## Sandboxes

- Run generated code
- Data transformation
- Scripts
- File processing
- Isolated execution

## Full Cloud Desktops

Use when browser/sandbox execution is insufficient.

Core principle:

> Local Mac = interactive/context-sensitive work.
> Solari = long-running, isolated, scalable, or parallel work.

---

# Local Context Collection

High-priority and relatively straightforward.

Orbit should initially understand:

- Current screenshot
- Active application
- Active window
- Browser URL/title
- Browser DOM where available
- Selected text
- Clipboard when relevant
- Accessibility tree where useful

Context should be converted into compact semantic information before sending everything blindly to models.

Privacy and context-retention controls are important architectural concerns.

---

# Browser Strategy

Local browser control should come before universal desktop control.

Use a Chrome extension for:

- Active tab
- URL/title
- DOM reading
- Page text/context
- Selected elements
- Form fields
- Clicking
- Typing
- Script execution
- Current visible-page screenshot

This enables many high-value workflows without solving arbitrary native UI control.

Examples:

- "Reply to this email."
- "Fill this form using my resume."
- "Compare this with my other tabs."
- "Summarize this page."
- "Click the yearly plan."
- "Research every company in this table."

---

# Native macOS Interaction

Early native functionality should focus on:

- Screenshot/current screen
- Active app/window
- Selected text
- Clipboard
- Keyboard shortcuts
- Text insertion
- Opening/focusing apps
- Reading accessibility-tree data
- Clicking known Accessibility API elements where reliable

General arbitrary visual computer control is lower priority.

---

# Difficult / Research-Heavy Areas

## 1. Universal macOS Computer Control

Reliable control across:

- Native apps
- Electron apps
- Custom UI frameworks
- Canvas-rendered interfaces
- Popups
- Dialogs
- Multiple monitors
- Fullscreen apps

is hard.

Treat as later-stage infrastructure.

---

## 2. UI Grounding

Orbit needs a robust hierarchy for identifying targets.

Preferred order:

1. Browser DOM
2. macOS Accessibility tree
3. Vision-based coordinate grounding

Do not rely solely on screenshots/pixels when structured UI information exists.

---

## 3. Context Continuity

Example:

User:

1. Reads an email.
2. Opens a PDF.
3. Opens a spreadsheet.
4. Says:
   "Update it with their revised quote."

Orbit should understand:

- "it"
- "their"
- "revised quote"

Need to design:

- Recent-context representation
- Semantic memory
- Context expiry
- User-visible controls
- Privacy boundaries
- What stays local
- What gets sent remotely

This is strategically important and can become a major differentiator.

---

## 4. Local → Cloud Handoff

Easy case:

Current page contains 30 companies.

User:

> "Research all of these."

Orbit:

- Extracts entities locally
- Spawns Solari workers
- Aggregates results

Harder case:

> "Do this inside my logged-in Salesforce."

Do NOT initially attempt automatic transfer of arbitrary local browser sessions/cookies.

Preferred early approach:

- User explicitly connects/logs into the relevant account inside an Orbit-managed Solari profile.

---

## 5. Agent Orchestration

Orbit needs a routing/execution layer that determines:
```css
Is this informational only?
    ↓
Use local context?
    ↓
Use connected API?
    ↓
Use local browser?
    ↓
Use native action?
    ↓
Spawn Solari browser?
    ↓
Spawn sandbox?
    ↓
Spawn full VM?
```

This router is effectively the core execution brain.

Keep provider-specific implementations behind tools/adapters.

---

## 6. Interrupting Running Work

Voice interruption is straightforward.

Interrupting autonomous execution is harder.

Example:

7 Solari agents are running.

User:

> "Stop. Only research European companies."

Need:

- Task IDs
- Parent/child task relationships
- Cancellation
- Checkpoints
- Partial results
- Replanning
- Worker cleanup
- Progress state

Design task orchestration with cancellation from the start.

---

# Initial Vertical Slices

## Slice 1: See + Talk

User activates Orbit:

> "What am I looking at?"

Inputs:

- Screenshot
- Active app/window
- Browser context if available

Output:

- Immediate voice response

---

## Slice 2: See + Write

User:

> "Write a concise reply to this."

Orbit:

- Understands current context
- Generates response
- Inserts it into focused field

This should feel much more computer-native than copy-pasting through ChatGPT.

---

## Slice 3: See + Delegate

User:

> "Research these 20 companies."

Orbit:

- Understands current screen/page
- Extracts targets
- Spawns parallel Solari browsers
- Continues talking to user
- User keeps working locally
- Surfaces result when done

This should be one of Orbit's signature interactions.

---

## Slice 4: Local Browser Actions

Examples:

- Fill form
- Navigate website
- Compare tabs
- Extract data
- Click/open target
- Generate/insert text
- Process multiple records

---

## Slice 5: Connected Apps

API-native integrations where possible.

Likely early targets:

- Gmail
- Google Calendar
- Google Drive
- Notion
- Slack
- GitHub

Prefer reliable API actions over visual clicking when APIs exist.

---

## Slice 6: Limited Native Desktop Actions

Add:

- Open/focus apps
- Accessibility-tree reading
- Known-element clicking
- Text insertion
- Keyboard shortcuts
- Simple menu actions

Expand native coverage based on real user failures rather than trying to solve all apps upfront.

---

# Current Priority

## P0

- Native floating Orbit shell
- High-quality orb animations/states
- AssemblyAI realtime voice
- Screen/current-context understanding
- Solari tool execution
- Task state/progress

## P1

- Chrome extension
- Browser context + local browser actions
- See + Write
- See + Delegate
- Smooth orb popout interactions

## P2

- Connected accounts/APIs
- Context continuity
- Persistent cloud profiles
- Task history/results
- Permission UX

## P3

- Basic native Accessibility API actions
- More local app integrations

## P4

- General-purpose macOS computer-use engine

---

# Key Engineering Principles

1. Native macOS first.
2. Orbit should feel like part of the OS, not a web app.
3. Voice and Solari are high-value, low-risk foundations.
4. Do not wait for perfect computer control.
5. Prefer structured context over screenshot-only reasoning.
6. Prefer APIs over GUI automation when possible.
7. Browser control before arbitrary desktop control.
8. Local Mac for interactive work, cloud workers for scalable work.
9. Every autonomous task should be observable and cancellable.
10. UI should expose complexity only when necessary.
11. Avoid layout shifts and conventional modal-heavy UX.
12. Provider-specific systems should sit behind internal abstractions so AssemblyAI/Solari can be replaced or extended later.
