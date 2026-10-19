# Integrated MVP — 19 October 2026

PR #10 was reviewed at `49ecb18d65878154d770746691bd3732868455c9` with no blocking findings, no unresolved review threads, and all current checks passing. Its validation run confirmed 58 standalone methods, 69 hosted XCTest methods, Release archive/signature verification and artifact uploads. It was merged as `c64ca52ab422bf9f534bb8a4294b72a336efbf18` before this implementation.

## Application behavior

The normal Scan command now composes screen permission, the existing region overlay and capture adapter, Vision, `ScanWorkflow`, the native result controller, retained text storage and the session-scoped `WorkspacePayloadLauncher`. The feasibility capture-report path is replaced by this workflow. A single web/text result dispatches according to the existing policy; multiple observations require a choice; registered app URIs require confirmation; blocked schemes remain explicit text actions. Recovery retains original text for Copy/Save.

The production composition owns selection, Escape and display-change callbacks through the active session. It gives a key cancellation panel focus before closing selection panels after capture, then keeps it until result presentation or termination. Delayed progress uses the status item separately. Native Save sheets retain their own Escape behavior. Callbacks retain their session IDs; late capture, UI actions, retries and terminal events cannot close or dispatch a replacement session. Captured pixels are not retained by the result UI. Rejected selections use the existing workflow's failure presentation without starting capture.

Settings persist explicit shortcut preferences, support local shortcut recording, report registration conflicts, and restore an enabled shortcut at the next normal launch. XCTest hosting does not restore user hotkeys or show onboarding. Menu scanning remains available when registration fails. App Sandbox, Hardened Runtime, macOS 14 deployment target, payload routing and text retention are preserved.

## Validation

Implementation is developed in `/workspace/worktrees/working-mvp`, branch `feature/working-mvp`, with independent controller and settings worktrees. This environment is Linux; native build and XCTest evidence comes from [PR #11](https://github.com/bgaechter/QRSnap/pull/11).

[macOS validation run 39202990847](https://github.com/bgaechter/QRSnap/actions/runs/39202990847), job `117899737297`, passed on **macOS 15.7.9 (24G830), arm64, Xcode 16.4 (16F6)**. Source head: `404da914920e1d15804de1437b6dcc240debb0d5`; tested PR merge: `b836d2bb90f44b88bbd3b7917c082a10dc95414c` against main `c64ca52ab422bf9f534bb8a4294b72a336efbf18`. Subsequent evidence-only edits do not change the application or tests.

- Deterministic project generation passed.
- **58 standalone methods** passed with zero assertion failures.
- **98 hosted XCTest methods** passed with zero failures, including 16 new application-controller and 13 new shortcut/settings methods.
- The development app and Xcode Release archive passed signature, exact-entitlement, App Sandbox, Hardened Runtime and declared deployment-floor checks.
- The verified Release ZIP and validation logs/`.xcresult` were uploaded. Reviewer artifact: `QRSnap-adhoc-pr-b836d2bb90f44b88bbd3b7917c082a10dc95414c-1`, available from the run until its seven-day retention expires. It is ad-hoc signed, not a notarized distribution.

Independent source review found no remaining blocking issue after fixing continuous processing cancellation focus. Local shell/plist/scheme syntax, documentation links and `git diff --check` also passed.

Tests inject permission, selection, capture and application-launch side effects. They exercise the production composition and native controls without requesting screen access, changing system defaults, registering global hotkeys or opening other apps. Existing Vision tests continue to use committed synthetic images.

## Runtime boundary

The prior [screen-permission runtime record](screen-permission-runtime.md) and [result-window runtime record](result-windows.md) establish named-host component behavior only. A live signed scan-to-default-app smoke test of this combined candidate is **NOT RUN** in this Linux environment. G0/G4/G6 are not declared accepted by compiling or passing mocked tests.

On an authorized Mac, use this candidate's exact binary with a stable signing identity where available. Record the source commit, executable identity, OS/architecture and observed receiving app. Check a single harmless HTTPS code, exact Unicode/multiline text, multiple-code choice, custom-handler confirmation, no-code recovery, Escape during selection/processing, a fresh scan after cancellation, shortcut persistence/conflict and text retention. Do not change system defaults or privacy settings implicitly. Preserve unavailable cases as NOT RUN.

The wider OS/display/permission matrix, timing/memory, pointer-free selection/full VoiceOver and Developer ID/notarization/clean installation remain the [manual and release gates](manual-tests.md).
