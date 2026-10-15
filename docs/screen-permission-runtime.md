# Screen permission repair and G0 runtime follow-up — 14 October 2026

**The screen permission blocker is resolved on this Mac with App Sandbox and Hardened Runtime enabled. G0 remains open for the outstanding compatibility and desktop-mode matrix.** This record supplements, rather than rewrites, the earlier [blocked run](runtime-verification.md). Automatic QR dispatch is still absent from the feasibility UI.

## Cause and repair

The original executable had CDHash `6134346698257e0a0f14f9214eaadd41ea829a2d`. Although System Settings showed QRSnap enabled, narrowly filtered `tccd` diagnostics showed macOS checking it against the stale requirement `cdhash H"4a6c142ee0eb0315a65fbe8436b65e424c4e1932"`, with `SecStaticCodeCheckValidity` status `-67050`. The first diagnostic build (`5b996d5756665d2691736d3ba1efecdf8bd082c8`) reported preflight false and a real ScreenCaptureKit denial (`SCStreamErrorDomain`, `-3801`). This was an identity mismatch, not evidence that the preflight guard should be removed.

After explicit user approval, only QRSnap's entry was removed and the exact diagnostic app at `build/QRSnap.app` in this task worktree was added through System Settings. Quit & Reopen completed the change. The same diagnostic build then reported preflight true before and after an accepted shareable-content query; `tccd` reported a matching requirement and allowed access. After adding the marker measurement controls, the grant was refreshed for the final artifact below. No other app grant, sandbox entitlement, system default, or launch-at-login setting was changed.

Apple explains that an ad-hoc designated requirement identifies a specific code version in [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements); [Apple DTS](https://developer.apple.com/forums/thread/819406) describes ad-hoc rebuilds appearing as a different app to screen-capture authorization. This machine reports **zero valid code-signing identities**. No weak custom requirement or unsandboxed workaround was introduced.

## Exact tested artifact and validation boundaries

Host: Mac16,8, arm64, macOS 26.5.2 (25F84), Swift 6.3.3, SDK 26.5. One built-in display: ID 1, 1512×982 logical points, 2× scale. Only Command Line Tools are selected locally.

- Runtime app: `/Users/benny/.codex/worktrees/screen-permission/QRSnap/build/QRSnap.app`.
- Bundle ID: `local.benny.QRSnap`; CDHash: `b40106c537e85ed14464fbf68a07b83f792ecb0f`.
- Executable SHA-256: `2e2469336d23901082c47560c7de4ee8154668dc9fee5072afc868b5d15cc338`.
- Strict signature verification passed; the only entitlement is `com.apple.security.app-sandbox=true`; Hardened Runtime is enabled.
- The runtime artifact was built from the runtime-controls base `47c2481` plus the diagnostic/marker changes. Its [source hashes and signature](evidence/screen-permission-runtime.json) identify it independently of later integration. That binary stayed unchanged throughout the final checks.
- After integration onto main `3afaa4a`, **44 standalone methods passed with zero failures**, including Vision fixtures, coordinator/dispatcher mocks, and two synthetic marker methods. [Test log](evidence/screen-permission-tests.log). This is distinct from GUI runtime evidence.
- The integrated application built and passed strict signature verification at `build/validation/QRSnap.app`, using `APP_OUTPUT_PATH` so the authorized binary was preserved. [Build log](evidence/screen-permission-build.log). This second app was not granted access or launched. Local full Xcode/XCTest is NOT RUN; the earlier 42-method hosted result remains documented in [CI evidence](ci.md).
- [Hosted run 38643183564](https://github.com/bgaechter/QRSnap/actions/runs/38643183564) passed for PR #7 code/evidence commit `3ac74523ec2a2f078c9b5c8caea2fcd3fdf7a95a`: generated-project checks, standalone fixtures, sandbox app build/audit, and app-hosted XCTest on the macOS 15 / Xcode 16.4 job. Subsequent evidence-label corrections do not change implementation or tests. Hosted XCTest does not replace the frozen signed GUI runtime experiment.

## Runtime results

All QR content was synthetic. Captured pixels remained in memory; no screenshot files or payload logs were created. The marker analyzer reports only bounds and phase for the explicit 800×800 fixture. It is not a general overlay-contamination detector.

| Check | Result | Observed evidence and boundary |
| --- | --- | --- |
| Permission diagnostic | PASS | Before repair: false / query denied -3801 / false. After exact-build replacement: true / query accepted / true. Query success alone was not counted as capture. |
| Actual sandbox capture + Vision | PASS on this host | Initial Preview crop: 660×640 pixels, display 1, one exact synthetic HTTPS observation. Later controlled fixture: 800×800, one exact observation. No destination was opened. |
| Known point-to-pixel mapping | PASS for named 2× setup | Fixture content at x=28, y=127, w=400, h=400 top-left display points. Crop 800×800. Inclusive marker bounds: `(20,20,35,35)`, `(764,20,779,35)`, `(20,764,35,779)`, `(764,764,779,779)`. Maximum edge error **0 px**, within the ≤1 px target. |
| Four drag directions | PASS for dimensions/decode; PARTIAL for numeric markers | All four directions returned 800×800 and one exact QR. Top-left→bottom-right and bottom-left→top-right produced complete zero-error bounds. Right-origin drags had a visible automation pointer glow over a corner and did not yield all four qualifying markers. No exact-edge claim for those two runs. |
| Own overlay exclusion | PASS, visual observation | Preview retained the fixture's white background and colored markers while QRSnap's overlay remained up until capture completed; no QRSnap dim layer or selection border appeared. A pointer/glow from the automation surface was visible in some crops; native cursor exclusion is not established by these runs. |
| Scene freshness after invocation | PASS, bounded | Invoked with phase B, observed selection overlay, changed source to phase A using its menu, verified overlay still active, then dragged/released. Result identified phase A with zero-error bounds. Earlier A→B sequence was also visually observed. This proves freshness after invocation; change while the mouse is held and frame-level latency were NOT RUN. |
| Escape, no-drag click, tiny selection | PASS | Escape and click without drag cancelled. A 10×10-point selection showed the minimum-size message. Subsequent scans worked. Report close returned to usable controls. |
| Global shortcut from another app | PASS, user observed | User physically pressed Control-Shift-Q and Escape: “Overlay appeared and Escape cancelled.” Injected automation keys did not exercise this reliably. No Accessibility/Input Monitoring prompt was observed; absence of any pre-existing grant was not independently audited. |
| Exclusive shortcut conflict | PASS | Second-process registration returned `-9878` while QRSnap owned it. After disabling, second process registered with status 0. While it held the key, QRSnap showed status -9878, kept checkbox off, and Scan/Escape remained usable. Probe unregistered with status 0. Quit/relaunch left the shortcut off and the probe registered again. Does not prove every possible shortcut conflict is detectable. |
| Full-screen Space invocation | PASS, user observed | User brought Preview's synthetic QR into full screen and physically invoked/cancelled: “Overlay stayed in Preview's Space and cancelled.” Arbitrary Space transitions and Stage Manager remain untested. |
| Revocation / recovery | PASS | Disabled only QRSnap's grant and used Quit & Reopen. Scan showed its explanation before selection; Cancel returned to controls. Restored the same grant, relaunched, and captured phase B with exact QR and zero-error marker bounds. Grant is left enabled for the frozen artifact. |
| Default `.txt` application | PASS on this host | Current build opened synthetic text in TextEdit; Unicode and multiline content visible. Exact 66 UTF-8 bytes, file mode 0600, directory mode 0700. File retained after editor close and QRSnap restart; SHA-256 `641a09e97fca2f7a4656b6763769e7ebdf47449f28a4c99f2a1d6a52d9fd479c`. No associations changed. |

Earlier automated marker attempts used a source window that was not visible at the assumed position, yielding no markers/QR. After the user brought it forward and moved it, the helper's live geometry title supplied the correct coordinates. Those attempts are not counted as passes or as a diagnosed capture-mapping defect.

## Remaining gates

- **NOT RUN — unavailable hardware/OS:** external displays, left/above origins, 1× display, portrait, attach/detach during selection, macOS 14 and Intel execution. No compatibility claim is extended to these cases.
- **NOT RUN — controlled settings/physical-input matrix:** fresh-identity OS dialog denial, alternate keyboard layout, arbitrary Space switching, Stage Manager, alternate default text editor. Existing system defaults were preserved. Revocation is covered separately and is not substituted for first-time denial.
- **PARTIAL — measurement tooling:** right-origin exact marker checks and cursor-free captures need a physical run without the automation pointer overlay. Scene changes during a held drag need a controlled source timer or physical second operator.
- **NOT RUN — later acceptance work:** release-to-launch timing (automatic dispatch is not composed), 30-run performance samples, measured peak memory/16-megapixel limit, leak profiling, complete keyboard/VoiceOver flow, and release signing/notarization. Closing a preview and static no-write inspection do not prove a full memory/privacy audit.
- **Diagnostic limitation:** a shareable-content query that never returns can leave this feasibility diagnostic busy until restart. A bounded timeout/cancel UI is follow-up work before production adoption.

## Reproduction without invalidating the grant

Keep the frozen runtime app unchanged. To validate a new build, use `APP_OUTPUT_PATH="$PWD/build/validation/QRSnap.app" ./scripts/build-app.sh`. An existing stable signing identity can be selected deliberately through `SIGNING_IDENTITY`; none was available here. If an ad-hoc build changes, compare its designated requirement with the consented artifact and replace only its own stale System Settings entry with user authorization. Do not disable the sandbox or remove the permission guard.

Build the separate synthetic source with `bash scripts/build-g0-fixture.sh`, then open `.build/G0Fixture.app`. Its title reports the current top-left content rectangle in display points; select that rectangle using the current display scale. The source never captures. The in-app marker measurement currently supports only its 400-point square at 2×. Its floating/all-Spaces behavior must not be used as proof of ordinary app Space behavior.

For the conflict probe, compile `scripts/g0-hotkey-probe.swift` with `xcrun swiftc`, then run with `--hold` to hold the registration until Return. It neither observes keys nor injects input. Release it after the check. The QRSnap shortcut is left off after the final restart; retained synthetic text remains under the documented retention policy.
