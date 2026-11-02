# Integrated MVP live validation — updated 2 November 2026

This record tests the integrated application from main commit `3aac5dc4d3cebe2f54e77674403111e05094625f`, including merged PRs #12 and #13. It supplements the earlier component records and does not replace their historical evidence.

## Candidate

- Worktree: `/Users/benny/.codex/worktrees/mvp-live-validation/QRSnap`, branch `feature/mvp-live-validation`.
- App: `build/QRSnap.app` in that worktree. The app has been built and launched.
- Host: macOS 26.5.2 (25F84), arm64, Swift 6.3.3, Command Line Tools.
- Strict ad-hoc signature verification passed with App Sandbox, Hardened Runtime and the declared user-selected file entitlement. The declared deployment target remains macOS 14; this is not execution evidence for that OS.
- [Machine-readable identity and observations](evidence/mvp-live-runtime.json) record the executable hash, CDHash and exact test scope.

## Results

| Check | Result | Evidence boundary |
| --- | --- | --- |
| Independent full standalone suite | PASS | 66 methods, zero assertion failures at the same source commit, including synthetic Vision fixtures. No actual capture or external launch in those tests. |
| Optimized app build and signature | PASS | Built separately from earlier authorized binaries. |
| App launch | PASS | Onboarding appeared without starting capture or requesting access. |
| Permission explanation and Cancel | PASS | Scan showed the explanation for missing access. Cancel returned to usable onboarding. |
| Settings keyboard loop | PASS | Tab traversed checkbox, Record, Default and Apply, then wrapped. Shift-Tab returned from checkbox to Apply. |
| Recording cancellation | PASS | Space started local shortcut recording. Escape cancelled recording, kept Settings open and restored Record focus. Saved shortcut remained disabled. |
| Settings close | PASS | Escape closed Settings without applying changes. |
| Application live test | PASS — user reported | On 2 November 2026, the user confirmed completing manual live testing. This closes the pending basic live-test prerequisite. |

The agent-run checks on 1 November used synthetic content and created no screenshot files or decoded payload logs. They changed no system defaults, privacy settings or launch-at-login settings. The binary above remains preserved.

## Manual acceptance

On 2 November 2026, the user confirmed that they had manually live tested the application and instructed that it be treated as live tested. Basic live validation is accepted on that basis. The earlier pending screen-access prerequisite is closed.

The user did not supply a scenario checklist, receiving-app details or a separate binary fingerprint for their run. The identity above belongs to the recorded 1 November candidate; this report does not invent additional measurements or per-scenario passes.

Wider OS/display coverage, timing and memory measurements, full VoiceOver, Developer ID signing, notarization and clean installation remain separate checks in [manual verification](manual-tests.md).
