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

Independent source review found no unresolved blocker after tightening failed-test cleanup and the claimed-worker cancellation wording. Local whitespace and generated-project consistency checks passed. Development is on Linux; macOS execution belongs to the follow-up PR's validation run, whose results will be recorded after completion.

The signed live screen-scan/default-application smoke test, native Vision cancellation latency, repeated real-scan memory profiling, and the wider OS/display/accessibility matrix remain **NOT RUN** in this workspace. Developer ID signing, notarization and release installation checks remain separate gates. [Manual verification](manual-tests.md).
