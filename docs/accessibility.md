# Keyboard navigation and accessible feedback

This follow-up implements the remaining keyboard and status-feedback work from A4/T8 on top of the integrated MVP. The rectangle gesture still requires a pointing device. This change does not establish complete nonvisual accessibility.

## Behavior

- Onboarding, processing, settings and result actions use focusable native buttons with explicit key loops. Tab moves forward, Shift-Tab moves back and Space activates the focused action. Disabled actions are skipped; held Space does not repeat an action.
- Focusing a choice scrolls its control into view. Its accessibility label includes the numbered, bounded preview so separately detected codes remain distinguishable. No result is chosen just by changing focus.
- The decoded-text view remains selectable and read-only. Command-A selects its displayed contents, and Tab leaves the text view. Explicit Copy and Save keep the original decoded UTF-8 value, including whitespace and combining characters.
- Settings starts on the shortcut enable control. Return applies changes; Escape and Command-W close the window. During shortcut recording, the existing window-scoped local key monitor has priority: Escape cancels recording and restores the saved registration, while invalid input does not Apply or close the window.
- Result windows support Command-W and Escape cancellation. Native Save sheets retain their own keyboard behavior. External-destination confirmation has no default Return action; navigate to Open and use Space, or use its normal native accessibility action.
- The application menu exposes Settings with Command-comma, Close Window with Command-W and Quit with Command-Q. These are app-local commands; the user's separately configured global shortcut remains unchanged.

Scan selection, delayed processing, cancellation and handoff request feedback now use AppKit's explicit accessibility-announcement API on the application element. The hidden onboarding label is no longer the only notification source. Result headings, Copy/Save outcomes and shortcut recording/registration feedback also have announcements. These status messages do not automatically read decoded destinations or text. A user can inspect the labelled result text or focus a chooser row to read its preview.

The implementation uses Apple's documented [accessibility announcement notification](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested) and native key-view navigation. Posting a notification establishes that the application provides the feedback; it does not prove which speech or braille a running assistive technology produces.

## Validation scope

Hosted tests exercise native hidden controls and injected clipboard, save, registration and announcement boundaries. They cover focus traversal, Space activation, repeated-key suppression, bounded chooser labels, text selection, original-text Copy, close/cancel idempotency, stale/reentrant announcement callbacks, recording Escape priority, invalid input, registration restoration and conflict feedback.

Local development is on Linux. Native compilation, hosted test execution and archive/signature validation belong to this follow-up's macOS PR validation run; results will be recorded once that run completes. Local source/project consistency checks are separate from runtime acceptance.

## Live checks still required

On the exact signed candidate, record the macOS version, keyboard layout and keyboard-navigation preference. Exercise Tab/Shift-Tab/Space through onboarding, a long chooser, confirmation, Copy/Save, recovery and settings. Verify offscreen focus scrolling, no handoff from focus changes, native Save-sheet Escape behavior and shortcut recording after a conflict.

With VoiceOver enabled by the tester, verify that selection, delayed processing, cancellation, result headings, Copy/Save outcomes and registration errors are announced intelligibly; that each chooser row identifies its preview; and that decoded text can be inspected without trapping keyboard focus. Screen-capture permission, display arrangements, Spaces and actual default-app handoff need the existing [manual smoke test](manual-tests.md). These live checks are **NOT RUN** in the Linux development environment.
