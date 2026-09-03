# Floating surface rebuild — Design (2026-09-04)

Target UI is the hand sketch: orb → voice pill → thinking bubble with
tool updates → short output with close → click expands big card (timer,
copy, text+mic input, orb docked at edge). Full ChatGPT-like window
stays a later slice.

## Modes (single source of truth)
One mode enum drives view + panel size + placement. Modes: orb,
voice, thinking, output, card, history (history renders inside card).
Two booleans disagreeing caused the crammed-card bug; they retire.

## Placement (edge-aware)
- Near right edge: bubble/card extend left (sketch default).
- Near left edge: extend right. Near top: below. Near bottom: above.
- Corner rule: horizontal side wins left/right; vertical otherwise.
- Pure function of anchor + screen frame, unit-tested headlessly.

## Drag feel (magnetic, springy)
- Orb travels freely while dragged (low threshold, no fighting
  gestures), on release glides to the nearest screen edge with margin
  via a damped spring and sticks there.
- Never free-floating mid-screen at rest.

## Position persistence (file, not defaults)
- Anchor persists to JSON in Application Support on every move/submit;
  restored on launch. File-based because the dev binary's defaults
  domain proved unreliable (position reset every run); the file is
  also user-inspectable. Pure read/write, unit-tested.

## Card behavior (from prior answers)
- Violet thinking; red stays reserved for approval/error.
- Live tool phrases until first token, then "Worked for Xs" counting
  while streaming. Static per-tool phrases (LLM-written phrases parked).
- Timer + copy-to-clipboard on replies, both now.
- Close cross (top-left of bubble per sketch) + Esc return to orb.
- Capsule copy-free rule stands; all words in bubble/card.
- Old card code, resultText property, and diagnostic logging retire in
  this slice. One mode-transition log line stays until headed confirm.

## Testing
- Headless: mode→size table, side-selection matrix, persistence
  round-trip in temp dir, timer format, model transitions, stream/hint
  paths keep passing.
- Headed (user): position survives relaunch; edge flips correct on
  all four sides; drag snaps springy; full sketch walkthrough with
  screenshot; resize log pasted until confirmed, then logging removed.

## Success criteria
- No crammed UI in any mode on any edge; readable at first open.
- Orb resticks to edges, never resets position, drag feels fluid.
- Full suite green, secrets never in git, commit per task.
