# Payload dispatch contract handoff — 14 October 2026

This change is independent policy and adapter work on `feature/payload-dispatch`, stacked on `feature/initial-feasibility`. It does not connect automatic routing to the feasibility app. G0 and G3 remain open: mocked dispatch success and compilation do not establish sandboxed default-application access, correct rendering in a receiving app, or end-to-end scan behavior.

## Implemented contract

`PayloadDispatcher(launcher:textStore:)` is main-actor isolated and accepts the existing `PayloadLaunching` and `TextDocumentStoring` boundaries. Its public operations are:

```swift
prepare(_ original: String?, isCurrent: () -> Bool) -> PreparedPayload?
dispatch(_ prepared: PreparedPayload,
         action: PayloadDispatchAction = .automatic,
         isCurrent: () -> Bool) async -> PayloadDispatchOutcome
```

Preparation classifies without writing or opening. A non-web URI candidate queries the OS-boundary launcher for a handler; unknown schemes become text. `PreparedPayload.original` retains the exact decoded string independently of the routing candidate, and `route` exposes the destination and handler metadata for the later UI. Unsupported input remains typed.

The coordinator must keep the same prepared object for all actions on one selected observation and must provide a predicate for that session's validity. Its separate `claimOpening` guard is not the predicate: the predicate must remain a repeatable query. Each prepared object permits only one accepted dispatch attempt, including while a launch callback is pending. A write/launch failure retains the original string and the written document URL when one exists, for later Copy/Save UI. Deliberate retry requires a newly prepared attempt.

| Route | `.automatic` on deliberate dispatch | Explicit action |
| --- | --- | --- |
| HTTP/HTTPS | Check handler, then open the URL once. | `.openAsText` preserves the original as a document. |
| Registered non-web URI | Return `.confirmationRequired(handler)`. | `.openExternal` rechecks the handler before opening. A changed handler updates the route and requires another confirmation; a missing handler returns typed failure with the original text. |
| Unknown, invalid, or ordinary text | Write exact UTF-8 through the store and open the resulting document once. | `.openAsText` has the same document behavior. |
| `file:`, `javascript:`, `data:` | Return `.explicitTextActionRequired`; no write or launch. | Only `.openAsText` can produce a handoff, using the stored document URL, never the original URI. |
| Unsupported | Return `.unsupported(reason)`. | No action dispatches it. |

Current-session validity and Swift task cancellation are checked before preparation, after handler lookup, after synchronous storage, immediately before launcher invocation, and after asynchronous completion. A cancellation during storage can leave a retained document, as required by the retention policy. Once a launch has been submitted, cancellation cannot retract the receiving application's action; a late callback returns `.cancelled` so the cancelled UI does not revive.

`WorkspacePayloadLauncher(isCurrent:workspace:)` is the AppKit adapter, excluded from the package core by the existing `App` exclusion. It independently checks the supplied predicate at each NSWorkspace call, uses asynchronous opening and `addsToRecentItems = false`, and reports callback failure without logging the URL, text, or OS error. It queries system defaults and never changes them. A successful callback means handoff accepted, not content loaded. The current contract rechecks registered-scheme metadata immediately before launch; it does not pin an application across a concurrent system association change.

## Validation

- `./scripts/test.sh --core-only`: **PASS**, 17 baseline methods, zero assertion failures; this also compiled the new test file.
- A worktree-local generated copy of `StandaloneRunner.swift` registered all 13 `PayloadDispatcherTests` methods: **PASS**, 30 core methods total, zero assertion failures. Assertions cover registered/unknown/blocked schemes, handler changes and disappearance, malformed URL fallback, exact Unicode/whitespace/empty text, failed storage and launch, unavailable handlers, cancellation before and after side effects, pending callbacks, task cancellation, unsupported values, and duplicate/alternative actions. Launch/storage spies open no apps and create no files. Existing storage tests separately exercise retained UTF-8 files.
- `./scripts/build-app.sh`: **PASS**, complete Swift 6 app compilation for arm64 with deployment target macOS 14, ad-hoc signing and strict signature verification. This does not launch the app or prove deployment-floor execution.
- Full Xcode/XCTest, real browser/editor handoff through this adapter, and end-to-end app routing: **NOT RUN**. The adapter is not composed into the running app while G0 remains open.

The integrator owns registration of the 13 methods in the shared standalone runner and regeneration of the Xcode project. Source ownership for this task is limited to `PayloadDispatcher.swift`, `WorkspacePayloadLauncher.swift`, `PayloadDispatcherTests.swift`, and this handoff.

## Integrator registration

The shared standalone runner and generated Xcode project now include all thirteen dispatcher test methods. The full fixture suite is executed by the integrator before PR publication. This branch is stacked on `feature/initial-feasibility`. Real UI dispatch remains disabled pending G0.
