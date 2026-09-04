# History store + chat popout + live E2E Implementation Plan

> Historical implementation plan. Session-only storage, 50-turn caps, and the original hover mechanism below are superseded. See [Prototype Context](../../prototype-context.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hovering the orb reveals a history button that opens past turns in the attached chat card, backed by a session-only store, proven by up to ~10 live conversations including memory references.

**Architecture:** In-memory turn store behind a protocol seam (persistence later) feeds the chat card; the history button slides from behind the orb on hover and opens the card in history mode; tapping a turn rereads it; live E2E exercises singles, memory, tools, denials, and mic.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit NSPanel, URLSession (live OpenRouter SSE), XCTest.

**Spec:** `docs/superpowers/specs/2026-09-03-streaming-chat-design.md` (sub-project B sections)

## Global Constraints

- macOS v15+ only, Swift tools 6.0, light-mode accessory panel behavior unchanged.
- Orb contract: 30px orb in 56px canvas, 190x44 capsule, ~220ms smooth morph, ~460ms state color interp, no focus rings, drag never activates, Escape cancels / Return sends.
- Primary orb capsule stays copy-free; all words live in the chat card.
- History is session-only, newest first, capped at 50 turns; cap is temporary and compression (summarizing old turns) is the documented future improvement.
- `.env.local` holds keys and is never committed; keys never logged, printed, or quoted anywhere.
- Every task ends with `swift build`, `git diff --check`, and a commit.

---

## File Map

- Create `Sources/Orbit/ChatStore.swift` — storing protocol + in-memory store.
- Modify `Sources/Orbit/OrbitApp.swift` — own the store, append turns, history mode flag.
- Modify `Sources/Orbit/OrbitShellView.swift` — history button, popout list, tap-to-reread.
- Modify `README.md`, `docs/prototype-context.md` — new behavior docs.

---

### Task 1: Session turn store

**Files:**
- Create: `Sources/Orbit/ChatStore.swift`
- Test: `Tests/OrbitTests/ChatStoreTests.swift`

**Interfaces:**
- Consumes: `ChatTurn` (from Plan A: transcript, reply, tools).
- Produces: `protocol ChatStoring: AnyObject { var turns: [ChatTurn] { get }; func append(_ turn: ChatTurn); func clear() }`, `final class ChatStore: ObservableObject, ChatStoring` with `@Published private(set) var turns: [ChatTurn]`, `static let cap = 50`, append drops oldest beyond cap. DB seam: the protocol is the persistence point; document in a one-line comment that compression replaces the hard cap later.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Orbit

final class ChatStoreTests: XCTestCase {
    func testAppendKeepsNewestFirst() {
        let s = ChatStore()
        s.append(ChatTurn(transcript: "a", reply: "b", tools: []))
        s.append(ChatTurn(transcript: "c", reply: "d", tools: ["screenshot"]))
        XCTAssertEqual(s.turns.map { $0.transcript }, ["c", "a"])
    }
    func testCapDropsOldest() {
        let s = ChatStore()
        for i in 0..<(ChatStore.cap + 5) {
            s.append(ChatTurn(transcript: "t\(i)", reply: "r", tools: []))
        }
        XCTAssertEqual(s.turns.count, ChatStore.cap)
        XCTAssertEqual(s.turns.first?.transcript, "t\(ChatStore.cap + 4)")
        XCTAssertNil(s.turns.first(where: { $0.transcript == "t0" }))
    }
    func testClearEmpties() {
        let s = ChatStore()
        s.append(ChatTurn(transcript: "a", reply: "b", tools: []))
        s.clear()
        XCTAssertTrue(s.turns.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter ChatStoreTests`
Expected: FAIL with "cannot find 'ChatStore'" / "cannot find 'ChatTurn'" (if Plan A not yet merged, ChatTurn missing too — B1 runs after Plan A lands, so only ChatStore missing).

- [ ] **Step 3: Write `Sources/Orbit/ChatStore.swift`**

```swift
import Combine
import Foundation

public protocol ChatStoring: AnyObject {
    var turns: [ChatTurn] { get }
    func append(_ turn: ChatTurn)
    func clear()
}

// Persistence seam: keep storage behind ChatStoring. The hard cap below is
// temporary; future improvement is compression (summarizing old turns)
// instead of dropping them.
@MainActor
public final class ChatStore: ObservableObject, ChatStoring {
    public static let cap = 50
    @Published public private(set) var turns: [ChatTurn] = []
    public init() {}
    public func append(_ turn: ChatTurn) {
        turns.insert(turn, at: 0)
        if turns.count > Self.cap { turns.removeLast(turns.count - Self.cap) }
    }
    public func clear() { turns.removeAll() }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ChatStoreTests`
Expected: PASS (3/3). Then full `swift test`, `swift build`, `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Orbit/ChatStore.swift Tests/OrbitTests/ChatStoreTests.swift
git commit -m "feat(history): add session turn store with documented cap"
```

---

### Task 2: History button + popout UI

**Files:**
- Modify: `Sources/Orbit/OrbitApp.swift` (model only)
- Modify: `Sources/Orbit/OrbitShellView.swift` (button + popout)

**Interfaces:**
- Consumes: `ChatStore`, `TalkSession.answerStream`, Plan A state (`streamText`, `hintText`, `chatOpen`, `closeChat`).
- Produces: model gains `let store = ChatStore()`, `@Published var historyOpen = false`; `submit` appends finished `ChatTurn(transcript:reply:tools:)` to store (tools recorded as the fired set's sorted raw values); history button opens card in history mode listing store turns; tap a turn shows it read-only in the card; close cross/Esc returns to orb.

Behavior rules (exact): history button is 22px, appears only on orb hover, slides from behind the orb (offset + scale + opacity, same timing language), never shifts the orb itself. Opening history sets `historyOpen = true`, `chatOpen = true`, `isExpanded = false`, state `.idle`. Tapping a turn sets a `selectedTurn` shown read-only with a back affordance returning to the list. Empty store shows "No turns yet." in the card (card copy only — orb capsule stays copy-free). Text input + voice button in the card send new turns via the Plan A pipeline. Close cross visible whenever the card is open.

- [ ] **Step 1: Failing tests** — store wiring in `Tests/OrbitTests/ChatModelTests.swift` (append):

```swift
func testSubmitAppendsTurnToStore() async {
    let svc = ContextService()
    let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
    let model = OrbitPanelModel(isMockVoice: true, context: svc,
        talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
    XCTAssertTrue(model.store.turns.isEmpty)
    model.submit(transcript: "what am I looking at?")
    try? await Task.sleep(nanoseconds: 500_000_000)
    XCTAssertEqual(model.store.turns.count, 1)
    XCTAssertEqual(model.store.turns.first?.transcript, "what am I looking at?")
    XCTAssertTrue(model.store.turns.first?.tools.contains("screenshot") ?? false)
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter ChatModelTests`
Expected: FAIL (`store` undefined).

- [ ] **Step 3: Implement model changes in `OrbitApp.swift`** — add `store`, `historyOpen`, `selectedTurn` (a `ChatTurn?`); record fired tools' sorted raw values when appending in `submit` completion; `openHistory()` / `closeChat()` extended to reset history state; `cancel()` clears history flags too. Keep panel/drag/anchor/shortcut/timing code untouched.

- [ ] **Step 4: Implement UI in `OrbitShellView.swift`** — history button (clock.arrow.circlepath glyph, 22px, hover-only, behind-orb slide), popout card (turn list newest-first, tap-to-reread with back, empty copy, input row with text field + voice + close). Reuse Plan A card container and animation language; capsule/orb/mic controls byte-identical.

- [ ] **Step 5: Verify** — `swift test --filter ChatModelTests` PASS, full suite, `swift build`, `git diff --check`, headed check if display available.

- [ ] **Step 6: Commit**

```bash
git add Sources/Orbit/OrbitApp.swift Sources/Orbit/OrbitShellView.swift Tests/OrbitTests/ChatModelTests.swift
git commit -m "feat(history): add hover button and popout chat with store"
```

---

### Task 3: Live E2E (up to ~10 convos) + docs

**Files:**
- Modify: `README.md`, `docs/prototype-context.md`
- Test: live matrix below (no new code unless a bug is found; bugfixes get their own TDD task first).

SECURITY (binding): `.env.local` holds REAL keys. Read values in-memory only; NEVER print, quote, log, or commit key values. Scratch harnesses live under `/tmp`, never in the repo. Confirm `.env.local` untracked at the end.

Matrix (each records transcript shape, tools fired, hint shown, streamed-vs-stub, memory check):
1. Single factual reply ("Reply in one sentence: what is 2+2?") — stream arrives in >1 token.
2. Paste summary + follow-up memory probe ("sum it up in three words" referring to turn 1's paste) — history used.
3. "What am I looking at?" — screenshot+app tools, hint names them.
4. Follow-up memory probe ("what app was I using?") — resolves from history.
5. Clipboard-denied draft — no clipboard tool, no leak.
6. Denied screen path — graceful copy, turn completes.
7. Empty Enter — stays open, no collapse (bug fix proof).
8. Mic round-trip if hardware present, else record skipped-why.
9. Long reply streams to completion without truncation bugs.
10. Reread turn from history popout (headed if display, else store-level).

- [ ] **Step 1: Run the matrix** (live key in-memory; stub-mode rerun with keys unset for parity).
- [ ] **Step 2: Update `README.md`** (streaming + history usage, `--mock-voice`, `.env.local` names only, cap note) and `docs/prototype-context.md` (new runtime shape, store seam, Enter fix).
- [ ] **Step 3: Verify** — `swift build`, full `swift test`, `git diff --check`, `git status` (only docs modified + prior task commits; `.env.local` untracked).
- [ ] **Step 4: Commit and push**

```bash
git add README.md docs/prototype-context.md
git commit -m "docs(streaming): update for streaming replies and history chat"
git push origin main
```
