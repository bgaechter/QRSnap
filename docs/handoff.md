# Implementation handoff

## Latest follow-up — result windows and explicit export

[PR #9](https://github.com/bgaechter/QRSnap/pull/9) was reviewed without blocking findings and merged with its required check green as `c710a8a`. This follow-up adds reusable chooser, custom-destination confirmation and failure-recovery windows, with exact Copy/Save and stale-action guards. An explicit synthetic preview composes them with `ScanWorkflow`; actual screen scans still use the capture-proof path. The requested MIT `LICENSE` is included.

Worktree: `/Users/benny/.codex/worktrees/result-windows/QRSnap`; branch: `feature/result-windows`, based on `c710a8a`. The UI/test agent contributed `f27da81` from `feature/result-window-component`; its two files are integrated here. Local standalone suite: 58 methods passing; project and sandboxed hardened build checks pass. Execution of the eleven additional hosted AppKit tests is recorded in the feature PR's required CI check. Native Save and cancellation passed on the signed preview candidate with exact 65-byte UTF-8 output. App Sandbox remains enabled with narrow user-selected file access for Save. The previous authorized screen-capture binary and its grant are preserved. [Detailed evidence and remaining G0 gates](result-windows.md).

## Latest follow-up — scan-to-open core composition

[PR #8](https://github.com/bgaechter/QRSnap/pull/8) was reviewed without blocking findings and merged with its required check green as `4638634`. The next independent slice connects the real coordinator and dispatcher in `ScanWorkflow`: automatic single-result routing, explicit multi-result choice, renewed custom-handler confirmation, blocked-text actions, retained failure data and session-safe cancellation. The feasibility UI remains unchanged. See [behavior, evidence and remaining gates](scan-workflow.md).

Worktree: `/Users/benny/.codex/worktrees/scan-open-workflow/QRSnap`; branch: `feature/scan-open-workflow`, based on merged main `4638634`. The independent test agent contributed commit `7e60ac9` from `feature/scan-workflow-tests`; its test file is integrated here. The final local suite passes 58 methods (13 new workflow cases), generated-project/plist checks pass, and the sandboxed hardened app builds and verifies. Hosted Xcode results belong to the feature PR's required check. G0 remains open; this is core/mock evidence, not production GUI or release acceptance. The authorized runtime executable's SHA-256 still matches `2e2469336d23901082c47560c7de4ee8154668dc9fee5072afc868b5d15cc338`.

## Latest follow-up — A1 empty/binary fixtures

PR #7 is merged and reviewed without blocking findings; its final CI run passed. The next unblocked task adds real empty, binary and mixed QR fixtures with optional expectations and encoded-byte integrity checks. See [A1 evidence](decoder-edge-fixtures.md). Worktree: `/Users/benny/.codex/worktrees/decoder-edge-fixtures/QRSnap`, branch `feature/decoder-edge-fixtures`, based on `91198dc`. Full standalone suite: 45 methods passing. Production code, sandbox entitlements and the frozen authorized runtime app are unchanged. G0's remaining matrix and production composition remain explicit dependencies.

## Latest follow-up — screen permission repair

PRs #2–#5 are merged; [PR #7](https://github.com/bgaechter/QRSnap/pull/7) is based on main `3afaa4a`. Worktree: `/Users/benny/.codex/worktrees/screen-permission/QRSnap`, branch `fix/screen-permission`. Ordinary SSH push succeeded for this branch. The [runtime follow-up](screen-permission-runtime.md) diagnoses the stale ad-hoc code requirement and records successful sandboxed capture, zero-error 2× marker mapping, visual exclusion, freshness, shortcut/conflict, revocation recovery, user-observed full-screen Space behavior and TextEdit handoff. G0 remains open for the named outstanding matrix; automatic dispatch and production UI composition remain unimplemented.

The integrated source passes 44 standalone methods and a separate sandbox build. Preserve `build/QRSnap.app` (CDHash `b40106c537e85ed14464fbf68a07b83f792ecb0f`) while its grant is used; build future validation artifacts with `APP_OUTPUT_PATH`. The older sections below describe their original handoff state, not current merge or runtime status.

## Historical initial baseline

The following baseline predates repository initialization. Current Git and validation status follows below.

**Task IDs:** A0 started; independent A1 work implemented. At that time no Git commit existed; the baseline was subsequently committed as `003010af49c16f40c79c00420b42074e8dda11c6` and merged via PR #1. Source fingerprint: `evidence/source-sha256.json`.

**Implemented:** five Markdown document conversions with archived originals; one app/test Xcode project; Command Line Tools build/test scripts; frozen typed contracts; routing policy; local selection geometry; session validity/phase guards; serial Vision decoder; exact UTF-8 document storage; synthetic fixtures; a menu-bar feasibility app with explicit permission, shortcut and synthetic handoff actions and an in-memory capture report.

**Verified:** full application compilation, strict local ad-hoc signature verification, project/plist syntax, document preservation, 19 standalone test methods, exact baseline Vision fixture decoding, four characterization observations. See `claims.md` and raw logs.

**Not run:** full Xcode/XCTest, GUI launch, signed capture/permission/shortcut/Spaces/display tests, external editor handoff, macOS 14 and Intel execution, timing and memory measurements, VoiceOver, release signing/notarization. The current build does not automatically open decoded content.

**Findings:** CLT does not provide XCTest here; the same assertions run through the standalone harness. Agent command sandbox blocks graphics-service access; narrowly scoped synthetic tests pass with that access. App Sandbox stays enabled. Geometry arithmetic passes but platform mapping remains provisional. See `decisions.md`.

**Next dependency:** G0 manual runtime experiments in `manual-tests.md`. Full production A2–A4 behavior must wait for the affected G0 evidence; independent fixture expansion and pure-core improvements can continue. No overall acceptance gate has been silently marked complete.

## Current repository and parallel implementation — 14 October 2026

The repository uses `git@github.com:bgaechter/QRSnap.git` as `origin`. [AGENTS.md](../AGENTS.md) persists feature branches, dedicated worktrees, parallel subagents, PR review, shared-file integration ownership and evidence gates. The primary checkout follows merged `main`; task worktrees are retained for review.

| Task | Pull request / dependency | Local worktree |
| --- | --- | --- |
| Scan coordinator | [#2](https://github.com/bgaechter/QRSnap/pull/2), targets main | `/Users/benny/.codex/worktrees/scan-coordinator/QRSnap` |
| Payload dispatcher | [#3](https://github.com/bgaechter/QRSnap/pull/3), depends on #2 | `/Users/benny/.codex/worktrees/dispatch-contracts/QRSnap` |
| Combined macOS CI | [#4](https://github.com/bgaechter/QRSnap/pull/4), depends on #3 | `/Users/benny/.codex/worktrees/macos-ci/QRSnap` |
| Feasibility controls/runtime evidence | [#5](https://github.com/bgaechter/QRSnap/pull/5), targets main | `/Users/benny/.codex/worktrees/runtime-verification/QRSnap` |

Review/merge the core stack in order #2 → #3 → #4, retargeting each dependent PR to main after its dependency lands. PR #5 is independent. Coordinator and dispatcher histories are combined in the dependent branches; runner registration and project-generation conflicts were resolved by the integrator. This handoff did not merge those new PRs.

The combined source passes **42 standalone tests locally**, then **42 standalone and 42 hosted XCTest tests** on macOS 15.7.9 arm64 / Xcode 16.4. [CI evidence](ci.md#combined-hosted-result) separates the command-line hardened app signature audit from Xcode's ad-hoc XCTest host behavior. A file-local legacy SDK import fixes the older ScreenCaptureKit annotation failure without changing the permission guard.

PR #5 records the authorized sandbox-app synthetic TextEdit handoff, exact UTF-8, restrictive modes and retained document. Screen preflight remains unavailable after the user reauthorized the exact build and it was relaunched; no capture/crop/exclusion result is claimed. See the [runtime record](https://github.com/bgaechter/QRSnap/blob/feature/runtime-verification/docs/runtime-verification.md). Production coordinator/dispatcher UI composition and automatic opening remain gated on the missing G0 evidence.

SSH authentication currently fails with `Permission denied (publickey)`. Branches and PRs were published through the authenticated GitHub connector, preserving commit topology and verifying exact Git tree hashes before synchronizing local refs. Original local commits remain under `refs/qrsnap/local-published/`. The supplied SSH remote remains configured; no private keys or tokens were copied. Ordinary SSH pushes require the user's GitHub SSH authentication to be configured.
