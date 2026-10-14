# Implementation handoff

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
