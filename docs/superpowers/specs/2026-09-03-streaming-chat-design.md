# Streaming replies + history chat — Design (2026-09-03)

> Historical design record. Session-only and capped-history statements below were superseded by persistent, currently uncapped local threads. See [Prototype Context](../../prototype-context.md).

## Goal
Turn the orb into a complete voice/text loop: ask from the orb, watch it
think (with honest hints about what context it is using), read the reply
as it streams, revisit past turns from a history popout. Fixes the
silent-collapse Enter bug on the way.

Non-goals: persisted history (session-only store; DB later), TTS/spoken
replies, browser extension, cloud delegation.

## Sub-projects (build in order)
- A: Enter fix + streaming replies + thinking hints + close. Usable alone.
- B: History button + attached chat popout on the in-memory store.

## Workflow
- Click orb: listening wave, as today.
- Type or speak, press Enter: surface stays open, orb shifts to thinking,
  hint line fades in naming only the context actually used.
- Reply streams token by token; hint cross-fades out as text arrives.
- Reply settles; close cross appears; Escape closes too.
- Empty Enter: surface stays open, input keeps focus (bug fix — today it
  collapses silently because send reads only the hidden mock field and
  live-mic transcription was never wired).
- Mic path: short capture transcribed, typed input remains the fallback
  when no speech key is configured.
- Hover orb: history button slides out from behind; click opens past
  turns in the card; tap a turn to reread; close returns to orb.

## Feel and copy rules
- Hint, streaming, and final states swap via blur + fade, reusing the
  existing timing language (fast morph, slow color shifts).
- Primary orb capsule stays copy-free; all words live in the chat card.
- History is session-only, newest first, capped at 50 turns. The cap is
  documented as temporary: future improvement is compression
  (summarizing old turns) instead of a hard cap.
- One reply surface: the chat card replaces the old result pill.

## Memory
- Follow-up turns include recent history (last few turns) as prior
  messages so the assistant can resolve references like "it" or "that".
- Offline stub path ignores history (documented; stub shape unchanged).

## Architecture
- Shell stays dumb: state, streaming buffer, open/closed flags only.
- Three isolated units behind protocols: streaming client (live SSE +
  stub single-chunk through one token-stream interface), session
  in-memory turn store (cap documented above; persistence seam left
  open), chat orchestrator (tools, hints, stream, store append).
- Views render state only; no network types in views.

## Error handling
- Speech key missing: typed input works; no dead end.
- Stream failure mid-reply: keep partial text, mark it plainly, offer
  retry via resend (no silent fake-complete).
- Non-200 API status: surfaced marker, never the plain offline shape.
- Denied screen/clipboard: graceful unavailable copy, turn continues.

## Testing
- Offline (no keys/mic): stream parser fixtures, hint mapping, store cap
  behavior, Enter empty/non-empty behavior, red-green per fix.
- Live (real keys, up to ~10 convos): single replies, multi-turn memory
  (references across turns), tool-gated turns (screen/paste), denied
  paths, one mic round-trip if hardware present. Keys in-memory only,
  never logged or committed.
- Headed: hover slide-out, popout open/close, Esc, streaming visual,
  relaunch position.

## Success criteria
- Enter always produces visible feedback; silent collapse is gone.
- Replies stream with honest hints; close/Esc reliably return to orb.
- History button appears on hover, opens turns, works by voice or text.
- Full suite green, build clean, secrets never in git, commit per task.
