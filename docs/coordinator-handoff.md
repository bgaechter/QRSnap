# Scan coordinator implementation handoff

Task: `feature/scan-coordinator`, stacked on `feature/initial-feasibility` at `003010a`. The integrator owns publication, project generation, test-runner registration and application composition. This branch adds only `QRSnap/Scan/ScanCoordinator.swift`, `QRSnapTests/ScanCoordinatorTests.swift`, and this record.

## Behavior and interface

`@MainActor ScanCoordinator` uses the frozen `ScreenCapturing`, `QRDecoding`, `Selection`, `DecodedItem`, `ScanFailure` and `SessionLifecycle` contracts. It has no AppKit UI, permission prompt, storage or launch side effect. Check/explain permission before beginning selection. It is independent core work while G0 remains open, not acceptance of A4/G4 or production capture/routing integration.

Initializer dependencies are `capture`, `decoder`, an optional `progressDelay` (300 ms), `timeout` (5 s), injectable asynchronous `sleep`, and a main-actor `onEvent` closure. Progress delay must be nonnegative and less than the positive timeout. Production sleep uses `Task.sleep`; tests use manually resumed timers.

| API | Contract |
| --- | --- |
| `sessionID`, `phase`, `results` | Read-only current state; results are immutable value observations, with optional payload preserved. |
| `beginSelection() -> UUID?` | Starts exactly one session; returns nil while busy or if the synchronous selecting callback cancels/replaces the new token. Selection time has no processing deadline. |
| `submit(_ selection: Selection) -> Bool` | Accepts the current selecting token once. Starts asynchronous capture and then decoding, with one shared processing deadline. |
| `cancel(sessionID:) -> Bool` | Invalidates the token immediately, cancels owned tasks and emits exactly one terminal event. |
| `displayDidChange(sessionID:) -> Bool` | Same cleanup with `.failed(.displayChanged)`. |
| `claimOpening(sessionID:) -> Bool` | Advances only the current reviewing token to opening; succeeds once. Does not launch anything. |
| `finishOpening(sessionID:) -> Bool` | Finishes only the current opening token. Caller owns any launch-failure presentation. |

Events are `.selecting(UUID)`, `.processing(UUID)`, `.progress(UUID, isVisible: Bool)`, `.results(UUID, [DecodedItem])`, and `.finished(UUID, FinishReason)`. Finish reasons are `.cancelled`, `.failed(ScanFailure)` and `.openingFinished`.

`.processing` is a state notification: it does not mandate closing the selection overlay before capture. `.finished` requests complete cleanup of that session's overlays, cursor, observers, progress and previews. All events carry a token, including terminal events, so synchronous callback reentrancy and later retries can be handled without affecting a new session. State and task cleanup finish before the terminal callback.

Zero observations finish with `.noQR`; one or multiple observations enter reviewing and publish all items once. A nil payload stays an unsupported observation for downstream presentation; it is not changed to “no QR.” No duplicate observations are removed and no payload is classified, logged or launched here. The decoder dependency owns its serial worker queue. Capture retains the existing main-actor asynchronous OS interface.

Timers stop when decode completes: chooser/confirmation time is excluded. Cancellation, disconnect, timeout and errors clear current results and invalidate late completions. Typed failures pass through; unknown capture/decode errors receive the corresponding typed fallback. A suspended OS operation may ignore task cancellation, so the coordinator cannot force its frame to be released before that operation completes; its late result is discarded. The coordinator itself stores no image or screenshot file.

Claim opening at the launch boundary. If caller work suspends after the claim (for example, text-file preparation), recheck both `sessionID` and `.opening` immediately before invoking the launcher. A past successful claim is not authorization after cancellation. Cancellation cannot retract an external launch already made.

## Validation on 14 October 2026

Environment: arm64 macOS host, Swift 6 compilation targeting macOS 14 using the selected Command Line Tools. No GUI app was launched by this task.

- `./scripts/test.sh --core-only`: PASS, 17 existing standalone methods, zero assertion failures; also compiles the new coordinator/tests.
- Temporary ignored `.build/CoordinatorStandaloneRunner.swift`, derived from the existing runner with the ten methods below registered: PASS, 27 total methods, zero assertion failures. Built with `xcrun swiftc -parse-as-library -swift-version 6 -D STANDALONE_TESTS -target arm64-apple-macosx14.0` and the same source set as `scripts/test.sh`; ran `.build/coordinator-contract-tests --core-only`.
- `./scripts/build-app.sh`: PASS, arm64 application compiled and its ad-hoc sandboxed signature verified. The shared Xcode project is unchanged and requires integrator regeneration.
- Full Xcode/XCTest, signed GUI coordinator workflow, actual capture/permission/display/launch integration, macOS 14 execution, T6 performance measurement and release validation: NOT RUN. Existing G0 gates remain open.

The following `ScanCoordinatorTests` methods need registration in the shared standalone runner (XCTest discovery uses their normal test names):

1. `testBusyInvocationAndSelectionIdentityAreGuarded`
2. `testCancellationDiscardsLateCaptureAndKeepsNewSession`
3. `testCancelledDecodeCannotReplaceNewSessionResults`
4. `testTimeoutDuringCaptureDiscardsLateCompletionAndAllowsRetry`
5. `testTimeoutDuringDecodeDiscardsLateResults`
6. `testProgressIsDelayedAndReviewingStopsDeadline`
7. `testNoQRAndErrorsCleanUpAndPermitAnotherScan`
8. `testDisplayChangeCancelsSelectionCaptureDecodeAndReview`
9. `testSingleAndMultipleResultsPreserveObservationsAndOpeningIsOnceOnly`
10. `testEventReentrancyCannotPublishCancelledResultsOrInvalidateRetry`

Fakes intentionally complete capture/decode and timers after cancellation. Tests cover capture/decode timeout, two-session races, late timer events, reentrant cancellation, unknown and typed failures, nil/duplicate result preservation, and cancellation after claiming opening. These are mocked-boundary checks with synthetic data; they prove no actual handler behavior or performance target.

## Integrator registration

The shared standalone runner and generated Xcode project now include all ten coordinator test methods. The full fixture suite is executed by the integrator before PR publication. This branch is stacked on `feature/initial-feasibility`. G0 and app composition remain open.
