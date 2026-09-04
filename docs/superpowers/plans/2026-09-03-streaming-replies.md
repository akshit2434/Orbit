# Streaming replies + Enter fix + hints Implementation Plan

> Historical implementation plan. For current behavior, use [Prototype Context](../../prototype-context.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replies stream token-by-token with honest thinking hints, and Enter always gives visible feedback instead of silently collapsing.

**Architecture:** New token-streamer protocol (live SSE + stub single-chunk through one interface) feeds an extended TalkSession that emits hint strings for tools actually fired and streams tokens; the shell keeps a streaming buffer, shows the hint with blur/fade, and retires the result pill. Views stay provider-independent.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit NSPanel, URLSession.bytes SSE, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-03-streaming-chat-design.md` (sub-project A sections)

## Global Constraints

- macOS v15+ only, Swift tools 6.0, light-mode accessory panel behavior unchanged.
- Orb contract: 30px orb in 56px canvas, 190x44 capsule, ~220ms smooth morph, ~460ms state color interp, no focus rings, drag never activates, Escape cancels / Return sends.
- Primary orb capsule stays copy-free; all words live in the chat card.
- Hint swaps use blur + fade in the existing timing language.
- `.env.local` holds keys and is never committed; keys never logged.
- Every task ends with `swift build`, `git diff --check`, and a commit.

---

## File Map

- Create `Sources/Orbit/StreamingClient.swift` — token-streamer protocol, live SSE client, stub client.
- Modify `Sources/Orbit/TalkController.swift` — hint strings, ChatTurn struct, TalkSession streaming method with history.
- Modify `Sources/Orbit/OrbitApp.swift` — Enter fix, streaming buffer, hint state.
- Modify `Sources/Orbit/OrbitShellView.swift` — hint view, streaming text, close cross, retire pill.
- Create `Tests/OrbitTests/StreamingTests.swift` — SSE fixture parsing, stub streaming, hint mapping.

---

### Task 1: Token streamer (SSE + stub)

**Files:**
- Create: `Sources/Orbit/StreamingClient.swift`
- Test: `Tests/OrbitTests/StreamingTests.swift`

**Interfaces:**
- Consumes: `OrbitConfig` (model + key).
- Produces: `protocol TokenStreamer: Sendable { func stream(model: String, messages: [[String:String]], apiKey: String) -> AsyncStream<String> }`, `struct OpenRouterTokenStreamer: TokenStreamer`, `struct StubTokenStreamer: TokenStreamer { var text: String }`, `enum StreamParse { static func tokenDeltas(fromSSELine line: String) -> [String] }`. Error convention: non-200 yields one `"[openrouter <status>] "` chunk; mid-stream failure yields trailing `" [interrupted — resend to retry]"`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Orbit

final class StreamingTests: XCTestCase {
    func testParsesDeltaContent() {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        XCTAssertEqual(StreamParse.tokenDeltas(fromSSELine: line), ["Hello"])
    }
    func testIgnoresDoneAndBlanks() {
        XCTAssertEqual(StreamParse.tokenDeltas(fromSSELine: "data: [DONE]"), [])
        XCTAssertEqual(StreamParse.tokenDeltas(fromSSELine: ""), [])
        XCTAssertEqual(StreamParse.tokenDeltas(fromSSELine: ": keep-alive"), [])
    }
    func testStubYieldsWholeTextOnce() async {
        let s = StubTokenStreamer(text: "abc")
        var got: [String] = []
        for await t in s.stream(model: "m", messages: [], apiKey: "") { got.append(t) }
        XCTAssertEqual(got, ["abc"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StreamingTests`
Expected: FAIL with "cannot find 'StreamParse'" / "cannot find 'StubTokenStreamer'".

- [ ] **Step 3: Write minimal implementation `Sources/Orbit/StreamingClient.swift`**

```swift
import Foundation

public protocol TokenStreamer: Sendable {
    func stream(model: String, messages: [[String: String]], apiKey: String) -> AsyncStream<String>
}

public enum StreamParse {
    public static func tokenDeltas(fromSSELine line: String) -> [String] {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("data:") else { return [] }
        let payload = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return [] }
        struct Delta: Decodable { var content: String? }
        struct Choice: Decodable { var delta: Delta? }
        struct Event: Decodable { var choices: [Choice]? }
        guard let data = payload.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: data) else { return [] }
        return event.choices?.compactMap { $0.delta?.content }.filter { !$0.isEmpty } ?? []
    }
}

public struct OpenRouterTokenStreamer: TokenStreamer {
    public init() {}
    public func stream(model: String, messages: [[String: String]], apiKey: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                var request = OpenRouterClient.buildRequest(model: model, messages: messages, apiKey: apiKey)
                var body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
                body["stream"] = true
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        continuation.yield("[openrouter \(status)] ")
                        continuation.finish()
                        return
                    }
                    var failed = false
                    for try await line in bytes.lines {
                        for token in StreamParse.tokenDeltas(fromSSELine: line) { continuation.yield(token) }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(" [interrupted — resend to retry]")
                    continuation.finish()
                }
            }
        }
    }
}

public struct StubTokenStreamer: TokenStreamer {
    public var text: String
    public init(text: String) { self.text = text }
    public func stream(model: String, messages: [[String: String]], apiKey: String) -> AsyncStream<String> {
        AsyncStream { $0.yield(text); $0.finish() }
    }
}
```

Mid-stream throw exits to `catch`, which yields the interrupted marker.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StreamingTests`
Expected: PASS (3/3). Then `swift build` and `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Orbit/StreamingClient.swift Tests/OrbitTests/StreamingTests.swift
git commit -m "feat(streaming): add token streamer with SSE parse and stub"
```

---

### Task 2: Hints + streaming orchestration with memory

**Files:**
- Modify: `Sources/Orbit/TalkController.swift`
- Test: `Tests/OrbitTests/StreamingTests.swift` (append new cases)

**Interfaces:**
- Consumes: `TokenStreamer`, `ContextService`, `OrbitConfig`, `ContextTool`.
- Produces: `struct ChatTurn: Equatable, Sendable { var transcript: String; var reply: String; var tools: [String] }`, `TalkController.hintStrings(for tools: Set<ContextTool>) -> [String]`, `TalkSession.answerStream(transcript:history:onHint:onToken:) async` where history is `[ChatTurn]` (last 6 used as prior messages), onHint/onToken are `@Sendable (String) -> Void` / `@Sendable (String) -> Void`. Stub path (no key): yields stub text as one token through the streamer interface, hints still fire.

Hint copy (exact): `.screenshot` → "glancing at your screen…", `.activeAppWindow` → "noting the front app…", `.pastedText` → "reading your pasted text…", `.clipboard` → "reading the clipboard…". Order: screenshot, activeAppWindow, pastedText, clipboard. Joined with " " when several fire.

- [ ] **Step 1: Write the failing tests (append to StreamingTests.swift)**

```swift
func testHintStringsFollowTools() {
    XCTAssertEqual(TalkController.hintStrings(for: [.screenshot, .activeAppWindow]),
                   ["glancing at your screen… noting the front app…"])
    XCTAssertEqual(TalkController.hintStrings(for: []), [])
}

func testAnswerStreamYieldsStubAsOneToken() async {
    let svc = ContextService()
    let stub = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
    let s = TalkSession(context: svc, client: stub)
    var hints: [String] = []
    var tokens: [String] = []
    await s.answerStream(transcript: "what am I looking at?", history: [],
                         onHint: { hints.append($0) }, onToken: { tokens.append($0) })
    XCTAssertEqual(hints.count, 1)
    XCTAssertTrue(hints[0].contains("glancing"))
    XCTAssertEqual(tokens.count, 1)
    XCTAssertTrue(tokens[0].contains("what am I looking at?"))
}

func testHistoryBecomesPriorMessages() {
    let msgs = TalkSession.messages(transcript: "and it?", history: [
        ChatTurn(transcript: "what am I looking at?", reply: "A browser.", tools: ["screenshot"])
    ])
    let joined = msgs.map { $0["content"] ?? "" }.joined(separator: "\n")
    XCTAssertTrue(joined.contains("what am I looking at?"))
    XCTAssertTrue(joined.contains("A browser."))
}
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter StreamingTests`
Expected: FAIL (`hintStrings`, `answerStream`, `messages`, `ChatTurn` undefined).

- [ ] **Step 3: Implement in `Sources/Orbit/TalkController.swift`** (keep existing `selectTools` and `answer` untouched)

```swift
public struct ChatTurn: Equatable, Sendable {
    public var transcript: String
    public var reply: String
    public var tools: [String]
    public init(transcript: String, reply: String, tools: [String]) {
        self.transcript = transcript; self.reply = reply; self.tools = tools
    }
}

public static func hintStrings(for tools: Set<ContextTool>) -> [String] {
    var parts: [String] = []
    if tools.contains(.screenshot) { parts.append("glancing at your screen…") }
    if tools.contains(.activeAppWindow) { parts.append("noting the front app…") }
    if tools.contains(.pastedText) { parts.append("reading your pasted text…") }
    if tools.contains(.clipboard) { parts.append("reading the clipboard…") }
    return parts.isEmpty ? [] : [parts.joined(separator: " ")]
}

public static func messages(transcript: String, context: ContextBundle, history: [ChatTurn]) -> [[String: String]] {
    var msgs = [["role": "system", "content": OpenRouterClient.systemPrompt]]
    for turn in history.suffix(6) {
        msgs.append(["role": "user", "content": turn.transcript])
        msgs.append(["role": "assistant", "content": turn.reply])
    }
    var parts = ["User said: \(transcript)"]
    if let app = context.app?.appName { parts.append("Front app: \(app)") }
    if let pasted = context.pastedText, !pasted.isEmpty { parts.append("Pasted text: \(pasted)") }
    if let clipboard = context.clipboard, !clipboard.isEmpty { parts.append("Clipboard: \(clipboard)") }
    if context.screenshotPNG != nil { parts.append("Screenshot attached: yes") }
    msgs.append(["role": "user", "content": parts.joined(separator: "\n")])
    return msgs
}
```

`hintStrings` and `messages` go inside `enum TalkController`. Then on `TalkSession`:

```swift
public func answerStream(transcript: String, history: [ChatTurn] = [],
                         onHint: @Sendable @escaping (String) -> Void,
                         onToken: @Sendable @escaping (String) -> Void) async {
    let tools = TalkController.selectTools(transcript: transcript,
        hasPaste: !context.pastedText.isEmpty, clipboardAllowed: context.clipboardAllowed)
    for hint in TalkController.hintStrings(for: tools) { onHint(hint) }
    let bundle = context.collect(tools: tools)
    if client.config.openRouterKey?.isEmpty != false {
        onToken(OpenRouterClient.stub(transcript: transcript, context: bundle))
        return
    }
    let streamer = OpenRouterTokenStreamer()
    let msgs = TalkController.messages(transcript: transcript, context: bundle, history: history)
    for await token in streamer.stream(model: client.config.openRouterModel, messages: msgs, apiKey: client.config.openRouterKey ?? "") {
        onToken(token)
    }
}
```

`TalkSession` needs `client` visible: it already holds `private let client`; add nothing — same-file access is fine since all three types live in these files. `OpenRouterClient.config` is public. `OpenRouterClient.stub` is internal — same module, testable via `@testable`.

- [ ] **Step 4: Run tests**

Run: `swift test --filter StreamingTests`
Expected: PASS (6/6). Then full `swift test`, `swift build`, `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Orbit/TalkController.swift Tests/OrbitTests/StreamingTests.swift
git commit -m "feat(streaming): add hints and streaming orchestration with memory"
```

---

### Task 3: Shell wiring — Enter fix, streaming view, close

**Files:**
- Modify: `Sources/Orbit/OrbitApp.swift` (model only)
- Modify: `Sources/Orbit/OrbitShellView.swift` (chat card UI)

**Interfaces:**
- Consumes: `TalkSession.answerStream`, `TalkController.hintStrings`, `ChatTurn`.
- Produces: model gains `@Published var streamText = ""`, `@Published var hintText: String?`, `@Published var chatOpen = false`, `func closeChat()`; `send()` empty path keeps surface open and sets `chatOpen = true` instead of collapsing; `submit` streams tokens into `streamText` with hint cross-fade, sets `chatOpen = true` on completion.

Behavior rules (exact): empty Send/Return → `isExpanded = true`, `chatOpen = true`, state stays `.listening`, no collapse, no reply. Non-empty → `.thinking`, `isExpanded = false`, `chatOpen = true`, hint shows first, tokens append to `streamText`, hint clears on first token, `.idle` on finish. `closeChat()` → clears `streamText`/`hintText`, `chatOpen = false`, state `.idle`. Escape → `cancel()` extended to also clear stream/hint/chat. Delete the result pill (`resultText` view) — `resultText` property may stay for one release but nothing renders it.

- [ ] **Step 1: Failing check** — press Return with empty input today collapses; assert new behavior in `Tests/OrbitTests/ChatModelTests.swift`:

```swift
import XCTest
@testable import Orbit

@MainActor
final class ChatModelTests: XCTestCase {
    func testEmptySendKeepsSurfaceOpen() {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.activate()
        model.debugText = "   "
        model.send()
        XCTAssertTrue(model.isExpanded)
        XCTAssertTrue(model.chatOpen)
        XCTAssertEqual(model.state, .listening)
    }
    func testSubmitStreamsStubToCompletion() async {
        let svc = ContextService()
        let client = OpenRouterClient(config: OrbitConfig(assemblyAIKey: nil, openRouterKey: nil, openRouterModel: "m"))
        let model = OrbitPanelModel(isMockVoice: true, context: svc,
            talk: TalkSession(context: svc, client: client), voice: MockVoiceSession())
        model.submit(transcript: "ping")
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(model.streamText.contains("ping"))
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.chatOpen)
    }
}
```

`OrbitPanelModel` init is currently `(isMockVoice:context:talk:voice:)` — matches. `submit` is synchronous starting an async Task; the sleep lets the stub finish.

- [ ] **Step 2: Run to verify fail**

Run: `swift test --filter ChatModelTests`
Expected: FAIL (`chatOpen`, `streamText`, `hintText` undefined).

- [ ] **Step 3: Implement model changes in `OrbitApp.swift`** — add the three published properties; rewrite `send()` empty branch to open chat instead of collapse; rewrite `submit` to use `answerStream` appending tokens to `streamText`, setting `hintText` from onHint and clearing it on first token; add `closeChat()`; extend `cancel()` to clear the new state. Keep panel sizes, drag threshold, anchor keys, shortcuts, collapse timing untouched.

- [ ] **Step 4: Implement chat card in `OrbitShellView.swift`** — collapsed surface gains: hint line (caption, secondary color, `.transition(.blurReplace.combined(with: .opacity))`), streaming/final text (max 3 lines, tail truncation only for overflow), close cross button (xmark, 20px, top-trailing of card, `.focusable(false)`, calls `model.closeChat()`). Remove result-pill block. Wrap hint/text swaps in the existing animation language; keep capsule/orb/mic controls byte-identical.

- [ ] **Step 5: Verify** — `swift test --filter ChatModelTests` PASS, full `swift test`, `swift build`, `git diff --check`, manual headed check if display available (click, type, Return, stream visible, close cross, Esc).

- [ ] **Step 6: Commit**

```bash
git add Sources/Orbit/OrbitApp.swift Sources/Orbit/OrbitShellView.swift Tests/OrbitTests/ChatModelTests.swift
git commit -m "feat(streaming): wire shell streaming with Enter fix and close"
```
