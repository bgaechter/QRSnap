# Cancellation-aware QR decoding

This follow-up addresses an A5 resource-lifecycle finding in the integrated MVP. Previously, the serial Vision queue retained each captured frame in an unconditional work closure. Cancelling or timing out a scan prevented its result from opening, but the obsolete job still held its pixels and later ran Vision. Repeated cancellation could delay a fresh scan behind abandoned work.

## Behavior and ownership

Each decode now has a synchronized job holding its frame, continuation and active request. Cancellation and completion share one terminal transition. They resume the caller, cancel a native request and release resources outside the state lock.

- A cancelled, unclaimed job releases its frame while its empty work item may still be queued. It does not create or perform a Vision request when dequeued.
- Cancellation before continuation installation still completes that caller once with cancellation.
- Cancellation while request creation is in progress releases the unclaimed frame and prevents request execution.
- Once the worker claims the frame, cancellation is best effort. This includes the interval before native analysis begins: the native call may still start or finish, and the worker may retain its frame until returning.
- Active cancellation is forwarded to the per-job Vision request. A late success or error cannot resume a cancelled continuation again. Existing coordinator session checks continue to reject stale destinations and UI changes.
- The public decoder interface, QR-only revision, image orientation, reading order, optional payload values and typed error behavior remain unchanged.

There is one serial native queue and a separate request for each job. The synchronized state uses the existing macOS-compatible lock facility. Only the small Vision request adapter bridges a non-Sendable framework class; configuration and result access remain on its worker, with cancellation as the intended concurrent operation.

Apple documents [request cancellation](https://developer.apple.com/documentation/vision/vnrequest/cancel()) and [Swift task cancellation handlers](https://developer.apple.com/documentation/swift/withtaskcancellationhandler(operation:oncancel:isolation:)). Neither establishes a bounded native cancellation latency or secure erasure of image memory.

## Regression coverage

Eight deterministic methods use synthetic pixels, controlled scheduling and injected request behavior. They cover already-cancelled tasks, cancellation before continuation installation, queued frame release, cancellation during request creation, active cancellation with late success/error, skipped obsolete backlog, ordering/orientation/optional payload preservation, and competing cancellation/completion.

The frame-lifetime cases check actual Core Graphics data-provider release before a cancelled queue slot runs. They establish ownership behavior for these controlled cases, not production peak-memory usage. The race loop samples interleavings; it is not an exhaustive proof. Failed completion checks have bounded exits, and blocked worker gates are released on cleanup so a lost-continuation regression does not strand the standalone suite.

## Integration and validation

The implementation was developed independently, then stacked on [PR #12](https://github.com/bgaechter/QRSnap/pull/12), branch feature/mvp-accessibility, to validate the combined MVP. Review the keyboard/accessibility PR first; this follow-up's PR targets that branch and contains only the decoder fix, its tests, generated project integration and evidence.

Independent source review found no unresolved blocker after tightening failed-test cleanup and the claimed-worker cancellation wording. Local whitespace and generated-project consistency checks passed. Development is on Linux; native evidence comes from [PR #13](https://github.com/bgaechter/QRSnap/pull/13).

[macOS validation run 39303781479](https://github.com/bgaechter/QRSnap/actions/runs/39303781479), job `118235449723`, passed on **macOS 15.7.9 (24G830), arm64, Xcode 16.4 (16F6), Swift 6.1.2**. Source head: `7b3cd6e507a53e336c765ccf6c5674b213760e7e`; tested PR merge: `c7b718bf1ccc0ff9c05b080db70082f9799dfe6e` against dependency head `ba2c845127821607fa47595de1ddb2851b9c1c3a`.

- **66 standalone methods** passed with zero assertion failures, including all eight cancellation methods and the existing real Vision fixture methods.
- **120 hosted XCTest methods** passed with zero failures. All eight cancellation methods also ran in the native app test host, alongside the keyboard/accessibility and existing integration suites. These totals overlap; they are not separate unique test counts.
- Generated-project consistency, the sandboxed app build, exact entitlements, Hardened Runtime, the Release archive and ad-hoc signature verification passed.
- The verified reviewer app and validation logs/`.xcresult` were uploaded. The [machine-readable evidence](evidence/decoder-cancellation-ci.json) records artifact IDs, digests and seven-day expiry. The archive is ad-hoc signed; Developer ID distribution is a separate gate.

The initial [run 39302966084](https://github.com/bgaechter/QRSnap/actions/runs/39302966084) compiled the standalone executable but ended with SIGTRAP before buffered test names were visible. The synthetic Core Graphics provider's release callback was moved from an actor-isolated helper to an explicitly nonisolated function, and standalone diagnostics now write immediately. Inherited callback isolation was the leading source-based diagnosis; the first run had no stack trace. The full native rerun above passed after this fixture correction.

This evidence record is added in a later documentation commit without changing application or test sources. CI runs on arm64; compilation of both Release architectures does not establish native Intel runtime behavior.

The signed live screen-scan/default-application smoke test, native Vision cancellation latency, repeated real-scan memory profiling, and the wider OS/display/accessibility matrix remain **NOT RUN** in this workspace. Developer ID signing, notarization and release installation checks remain separate gates. [Manual verification](manual-tests.md).
