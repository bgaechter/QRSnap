# G0 manual verification record

**G0 is incomplete.** The authorized local run verified synthetic text handoff and permission explanation/Cancel; capture stayed blocked after user reauthorization and relaunch. See [runtime evidence](runtime-verification.md). All other rows remain NOT RUN. Use only synthetic content and an authorized controlled GUI environment.

Record per run: date, source hash/commit, app signature/identity, entitlements, macOS build, Mac/architecture, display IDs/origins/point sizes/scales, keyboard layout, initial permissions, actions, expected/observed values and sanitized evidence. A successful callback is not proof of rendered content. Do not save screenshots containing unrelated user data.

| Gate | Procedure | Expected evidence | Status |
| --- | --- | --- | --- |
| U1 permission | Fresh signed identity: invoke Scan, cancel before request, then separately test grant/deny/revoke/relaunch. | No capture before explicit action; accurate recovery guidance; actual capture success only when authorized. | PARTIAL: explanation/Cancel pass; preflight unavailable after grant/relaunch; deny/revoke NOT RUN |
| U1/U3 crop/exclusion | Display `https.png` in another app. Select known bounds while overlay stays visible. Use known corner markers and an exact declared point rectangle. | Output dimensions and marker bounds within one output pixel; no dim layer or selection outline. Compare live content changed before release to verify freshness. | NOT RUN |
| U3 display matrix | Repeat on primary/secondary, display left/above primary, 1×/2×, scaled mode and portrait. | Correct display-ID mapping and crop for every named arrangement. Mark unavailable hardware NOT RUN. | NOT RUN |
| U3 desktop modes | Invoke over another app's full-screen Space, switch Spaces, enable Stage Manager. | Overlay visible without unwanted Space switching; reliable Escape; no stuck input interception. | NOT RUN |
| U2 shortcut | Explicitly enable ⌃⇧Q, foreground another app, invoke, Escape, disable and retry. | Background invocation works; disabled/quit shortcut is unregistered; observed permission behavior recorded. | NOT RUN |
| U2 conflict/layout | Controlled second exclusive registration of the same hotkey; repeat with non-US input layout. | Registration failure is shown and menu remains usable; document physical-key behavior, do not claim all conflicts are detected. | NOT RUN |
| T1 cancellation | Click without dragging, tiny rectangle, drag each direction, repeated invocation, Escape during capture, disconnect/change screen during selection. | No destination opens, all panels/cursors removed, next scan usable, stale results discarded. | NOT RUN |
| U4 handoff | Click synthetic text test, identify actual default editor, inspect Unicode/multiline output and original bytes, then close editor/relaunch proof. | File readable from sandbox path, exact UTF-8, retained after callback and relaunch, no changed associations. Repeat another editor only on an authorized test account. | PARTIAL PASS: TextEdit rendering/bytes/modes and retention after QRSnap relaunch; editor-close and alternate-editor matrix NOT RUN |
| T7 memory/privacy | Repeated scans/cancel/fail/preview-close; inspect only app-created files and authorized logs. | Preview references released on close; no screenshots/payload logs; intentional text documents retained; no continuous capture in idle. | NOT RUN |
| T8 accessibility | Navigate menus/proof UI by keyboard and VoiceOver. | Labels/status readable; record selection limitation and required production work. | NOT RUN |
| U7 supported OS/architecture | Repeat on macOS 14 and intended release OS/CPU with controlled signing identity. | Named compatibility evidence; compile target alone is insufficient. | NOT RUN |

After G0 passes, promote the proven adapters into A2/A3, implement configurable shortcut/settings and the full A4 workflow, add fake-boundary late-completion tests, then execute A5's timing/privacy/accessibility matrix. Release signing/notarization is A6 and requires separate release authorization.
