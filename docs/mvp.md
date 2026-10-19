# Integrated MVP — 19 October 2026

PR #10 was reviewed at `49ecb18d65878154d770746691bd3732868455c9` with no blocking findings, no unresolved review threads, and all current checks passing. Its validation run confirmed 58 standalone methods, 69 hosted XCTest methods, Release archive/signature verification and artifact uploads. It was merged as `c64ca52ab422bf9f534bb8a4294b72a336efbf18` before this implementation.

## Application behavior

The normal Scan command now composes screen permission, the existing region overlay and capture adapter, Vision, `ScanWorkflow`, the native result controller, retained text storage and the session-scoped `WorkspacePayloadLauncher`. The feasibility capture-report path is replaced by this workflow. A single web/text result dispatches according to the existing policy; multiple observations require a choice; registered app URIs require confirmation; blocked schemes remain explicit text actions. Recovery retains original text for Copy/Save.

The production composition owns selection, Escape and display-change callbacks through the active session. Callbacks retain their session IDs; late capture, UI actions, retries and terminal events cannot close or dispatch a replacement session. Captured pixels are not retained by the result UI. Rejected selections use the existing workflow's failure presentation without starting capture.

Settings persist explicit shortcut preferences, support local shortcut recording, report registration conflicts, and restore an enabled shortcut at the next normal launch. XCTest hosting does not restore user hotkeys or show onboarding. Menu scanning remains available when registration fails. App Sandbox, Hardened Runtime, macOS 14 deployment target, payload routing and text retention are preserved.

## Validation

Implementation is developed in `/workspace/worktrees/working-mvp`, branch `feature/working-mvp`, with independent controller and settings worktrees. This environment is Linux; native macOS build and XCTest evidence comes from the feature PR's GitHub Actions run. Hosted results will be recorded here after validation.

Tests inject permission, selection, capture and application-launch side effects. They exercise the production composition and native controls without requesting screen access, changing system defaults, registering global hotkeys or opening other apps. Existing Vision tests continue to use committed synthetic images.

## Runtime boundary

The prior [screen-permission runtime record](screen-permission-runtime.md) and [result-window runtime record](result-windows.md) establish named-host component behavior only. A live signed scan-to-default-app smoke test of this combined candidate is **NOT RUN** in this Linux environment. G0/G4/G6 are not declared accepted by compiling or passing mocked tests.

On an authorized Mac, use this candidate's exact binary with a stable signing identity where available. Record the source commit, executable identity, OS/architecture and observed receiving app. Check a single harmless HTTPS code, exact Unicode/multiline text, multiple-code choice, custom-handler confirmation, no-code recovery, Escape during selection/processing, a fresh scan after cancellation, shortcut persistence/conflict and text retention. Do not change system defaults or privacy settings implicitly. Preserve unavailable cases as NOT RUN.

The wider OS/display/permission matrix, timing/memory, pointer-free selection/full VoiceOver and Developer ID/notarization/clean installation remain the [manual and release gates](manual-tests.md).
