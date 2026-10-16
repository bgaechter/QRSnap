# Implementation evidence — updated 16 October 2026

**A0 is started, not accepted. G0 remains open.** A1 has independent core/fixture evidence. A2–A6 acceptance is pending. Original planning evidence remains in [04-evidence-and-verification.md](../04-evidence-and-verification.md); do not confuse it with implementation results here.

Environment: macOS 26.5.2 (25F84), arm64, Apple Swift 6.3.3, macOS SDK 26.5, selected developer directory `/Library/Developer/CommandLineTools`. The initial checks predated Git initialization; their [source hashes](evidence/source-sha256.json) remain the historical baseline. That source was committed as `003010af49c16f40c79c00420b42074e8dda11c6` and merged through PR #1. The later [runtime record](runtime-verification.md) identifies the tested controls-window change and exact executable separately.

| Check | Actual result | Evidence / limitation |
| --- | --- | --- |
| Five document conversions | PASS | [Conversion record](evidence/document-conversion.json), [prose check](evidence/document-conversion-check.log); exact original bytes preserved. |
| Application build | PASS | [Workflow build log](evidence/scan-workflow-build.log); Swift 6, arm64, deployment target macOS 14, separate worktree preserving the authorized runtime app. Does not prove execution on macOS 14. |
| Local signature | PASS | Ad-hoc signature, strict verification, App Sandbox and Hardened Runtime. [Runtime signature](evidence/screen-permission-runtime.json) and [workflow build](evidence/scan-workflow-build.log). No Developer ID/notarization claim. |
| Xcode project/plist syntax and hosted XCTest | PASS | Generated project checked; [PR #7 hosted run](https://github.com/bgaechter/QRSnap/actions/runs/38643183564) passed including app-hosted XCTest. Local full Xcode is unavailable. Hosted tests do not establish screen permission or signed GUI runtime acceptance. |
| Core behavior | PASS | 55 standalone core methods, including 13 composed workflow tests, coordinator races, guarded dispatch, geometry, marker measurement and retained text. Pure/mocked evidence does not establish production GUI composition. |
| Vision baseline | PASS on this machine | 12 original positive PNG fixtures, one no-code image and three new empty/binary/mixed fixtures. Exact optional payload arrays and reading order. [A1 follow-up](decoder-edge-fixtures.md). |
| Vision characterization | OBSERVED | Dense (1, exact), small (1, exact), cropped (0), damaged (0). Four isolated samples do not locate a general reliability boundary. |
| Full standalone suite | PASS | [58 methods, zero assertion failures](evidence/scan-workflow-tests.log), using graphics-service access outside the agent command sandbox. No test opens another application. Earlier logs retain their historical scope. |
| Empty/binary observations | PASS for named fixtures | Real QR images yield empty text, nil text, and mixed supported/unsupported observations. Encoded fixture bytes, observation count/order, unique IDs and typed classification verified. [Evidence](decoder-edge-fixtures.md). |
| G0 capture/permission/shortcut/Spaces | PARTIAL PASS | Stale ad-hoc grant diagnosed and repaired. Actual sandbox capture, zero-error 2× marker mapping, visual overlay exclusion, post-invocation freshness, cancellation, shortcut/conflict, revoke/recover pass. Physical shortcut and full-screen Space checks are user-observed. Remaining matrix is explicit in the [follow-up](screen-permission-runtime.md). |
| G0 external `.txt` access | PASS on this host | TextEdit rendering, exact 66 UTF-8 bytes, 0600/0700 and retention after editor close and QRSnap restart verified again. Other editors/OS versions NOT RUN. [Follow-up](screen-permission-runtime.md). |
| Scan-to-open composition | CORE MOCKS PASS / GUI NOT RUN | Real coordinator and dispatcher composed through fake capture/decode/storage/launcher boundaries: automatic routing, chooser, renewed confirmation, explicit text action, retained failures and cancellation. [Evidence and remaining gates](scan-workflow.md). Feasibility UI integration remains pending. |
| G2 display/OS matrix, T6 timing, T8 accessibility | PARTIAL / NOT RUN | Primary 2× display measured on this host. Other hardware/OS configurations, 30-run timings and complete keyboard/VoiceOver checks NOT RUN. |
| G6 release | NOT RUN | Full Xcode, chosen release signing identity, release authorization and clean installation tests required. |

## Claim status

- **U1 / U3:** supported for the named 2× host checks, open for the remaining [manual matrix](manual-tests.md). Grant mismatch is resolved; do not extrapolate to unavailable OS/display configurations.
- **U2:** background physical invocation, full-screen invocation, exclusive collision and unregister behavior pass on this host. Alternate layout and broader conflict behavior remain open.
- **U4:** supported on this host by signed sandbox runtime handoff to TextEdit, visual content, exact UTF-8 and retained-file checks. Other default editors and OS versions remain open.
- **U5:** native Vision supports the current synthetic baseline, including empty and unsupported observations, on this host. Deployment-floor and broader decoder reliability remain unverified; fixture success does not imply universal QR support.
- **U6:** session identity, composed scan-to-open policy and mocked late-callback/launch tests pass. Production GUI composition and performance remain open.
- **U7:** local sandboxed, hardened capture and text handoff pass on this host. Supported OS/architecture coverage and distribution remain open.

## Platform source checks

The installed SDK headers for `SCStreamConfiguration.sourceRect`, `SCContentFilter.pointPixelScale`, application exclusion, the macOS 14 screenshot method, and Vision revision 4 were inspected; the whole application then compiled against those signatures. Apple documents the [content-filter API](https://developer.apple.com/documentation/screencapturekit/sccontentfilter) and [asynchronous NSWorkspace handoff](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:configuration:completionhandler:)). These checks establish API usage, not G0 behavior. The implementation uses the reviewed macOS 14 screenshot path, not the newer screenshot configuration API.
