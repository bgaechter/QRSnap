# Local feasibility runtime — 14 October 2026

**Historical result; superseded by the [permission repair and runtime follow-up](screen-permission-runtime.md).** G0 remains open for the outstanding matrix. This earlier run opened the synthetic text document successfully but capture stayed blocked. The follow-up diagnoses the stale code-signing requirement and records successful capture without disabling the sandbox. The observations below retain their original scope.

## Build and scope

Test worktree: `runtime-verification`, branch `feature/runtime-verification`, based on `003010af49c16f40c79c00420b42074e8dda11c6` (merged PR #1). The only runtime source change adds a visible, keyboard-accessible feasibility controls window, a menu command to reopen it, and hiding that window before selection. Opening the app does not request permission, register a shortcut, capture, or launch a destination. The existing explicit test actions remain responsible for those operations.

Host: Mac16,8, arm64, macOS 26.5.2 (25F84), Swift 6.3.3, SDK 26.5, Command Line Tools. The app executable is arm64; the evidence-writing Python process ran under x86_64 translation. Full Xcode is unavailable locally. Bundle identity: `local.benny.QRSnap`; ad-hoc signature with App Sandbox and Hardened Runtime. CDHash: `6134346698257e0a0f14f9214eaadd41ea829a2d`. [Sanitized evidence](evidence/runtime-verification.json) records the executable and changed-source SHA-256 values, so this run can be distinguished from other builds with the same bundle identifier. The existing build/signature checks passed before launching. The runtime binary was not rebuilt during permission diagnosis.

The user explicitly approved the local synthetic runtime checks, screen-permission request and text handoff, then approved authorizing this exact build and completed macOS authentication and selection manually. No system application defaults were changed.

## Observations

| Check | Result | Scope |
| --- | --- | --- |
| Controls window | PASS | Scan and text-test buttons are exposed in the accessibility tree; controls reopen when the app is reopened. |
| Permission explanation / Cancel | PASS | Scan explains access before requesting it. Cancel returns to idle controls without starting selection. |
| Text handoff callback | PASS | NSWorkspace accepted the explicit synthetic test document. |
| Default editor content | PASS | TextEdit opened the document and visibly rendered the expected multilingual, emoji and multiline text. No hard-coded editor was used. |
| Text bytes / permissions | PASS | The one test document exactly matched expected UTF-8, with file mode 0600 and directory mode 0700. |
| Text retention | PASS, bounded | The same document remained after callback and QRSnap relaunch. Other editors, OS versions, and long-term retention were not tested. |
| Screen access after authorization | BLOCKED | System Settings visibly shows QRSnap enabled; after manual authorization of this exact path and fresh relaunch, Scan still follows the false-preflight permission explanation path. |
| Synthetic QR capture, crop, exclusion | NOT RUN | Permission prerequisite did not pass; Preview had the synthetic fixture ready, but capture never began. |
| Shortcut, Spaces, external displays, VoiceOver, timing | NOT RUN | No inference from compilation or unit tests. |

The intentionally retained synthetic document has a random UUID filename in the app container's `Application Support/local.benny.QRSnap/Scanned Text` directory. Its content was inspected only for this authorized test. No screen images or unrelated application content were saved to the repository.

## Permission diagnosis and next step

Process inspection confirmed the exact runtime-worktree executable, and that QRSnap and System Settings run under the same macOS user. Narrowly filtered privacy-service logs attributed the request to `local.benny.QRSnap` at that executable path; they did not expose an actionable denial reason.

The ad-hoc designated requirement is tied to this binary's code hash; the other worktree builds have different requirements. Apple's [code-requirement note](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) explains how privacy grants depend on identity, and [Apple DTS discusses this ad-hoc build symptom](https://developer.apple.com/forums/thread/819406). A stale grant for another build is a plausible explanation, **not a confirmed diagnosis**: the unchanged, explicitly reauthorized binary still reported no access. The implementation retains the documented preflight guard; no privacy reset, sandbox removal, broad entitlement or bypass was used.

Resume G0 in a controlled environment with a stable authorized development signing identity or a diagnosed matching grant, then run the full [manual matrix](manual-tests.md). Do not repeatedly rebuild this test identity while investigating its grant. The text result supports U4 on this host only; it does not accept G0 as a whole or enable automatic decoded-payload dispatch.
