# Implementation evidence — 14 October 2026

**A0 is started, not accepted. G0 remains open.** A1 has independent core/fixture evidence. A2–A6 acceptance is pending. Original planning evidence remains in [04-evidence-and-verification.md](../04-evidence-and-verification.md); do not confuse it with implementation results here.

Environment: macOS 26.5.2 (25F84), arm64, Apple Swift 6.3.3, macOS SDK 26.5, selected developer directory `/Library/Developer/CommandLineTools`. The initial checks predated Git initialization; their [source hashes](evidence/source-sha256.json) remain the historical baseline. That source was committed as `003010af49c16f40c79c00420b42074e8dda11c6` and merged through PR #1. The later [runtime record](runtime-verification.md) identifies the tested controls-window change and exact executable separately.

| Check | Actual result | Evidence / limitation |
| --- | --- | --- |
| Five document conversions | PASS | [Conversion record](evidence/document-conversion.json), [prose check](evidence/document-conversion-check.log); exact original bytes preserved. |
| Application build | PASS | [Build log](evidence/build.log); Swift 6, arm64, deployment target macOS 14. Does not prove execution on macOS 14. |
| Local signature | PASS | Ad-hoc signature, strict verification, App Sandbox and Hardened Runtime. [Signature audit](evidence/signature.log). No Developer ID/notarization claim. |
| Xcode project/plist syntax | PASS | `plutil -lint`; shared scheme XML parsed. No Xcode build or XCTest run. |
| Core behavior | PASS | 17 methods through the standalone runner: routing/host/escape validation, text preservation, nil/size guard, drag/clipping/rounding, observation order, session invalidation and one-time opening gate, text bytes/permissions/retention/failure. |
| Vision baseline | PASS on this machine | 12 positive PNG fixtures plus one no-code image. Exact optional payload arrays, including two-code reading order. HTTP(S), multilingual/emoji, multiline, escaped URL, custom/mailto, Wi-Fi and credentials-like synthetic text, rotation and inversion. |
| Vision characterization | OBSERVED | Dense (1, exact), small (1, exact), cropped (0), damaged (0). Four isolated samples do not locate a general reliability boundary. |
| Full standalone suite | PASS | [19 methods, zero assertion failures](evidence/contract-tests.log), using graphics-service access outside the agent command sandbox. No test opens another application. |
| Empty/binary observations | PARTIAL | Pure nil/empty classification covered. No real binary/empty QR observation fixture yet. |
| G0 capture/permission/shortcut/Spaces | PARTIAL / BLOCKED | Explicit explanation and Cancel observed. Preflight still reports unavailable after authorized exact-build grant and relaunch; no capture occurred. Shortcut/Spaces NOT RUN. [Runtime record](runtime-verification.md). |
| G0 external `.txt` access | PASS on this host | Explicit synthetic test opened in default TextEdit; Unicode/multiline display, exact bytes, 0600/0700 and retention after QRSnap relaunch verified. Other editors/OS versions NOT RUN. [Runtime record](runtime-verification.md). |
| Production coordinator races | NOT RUN | Session value is tested. Delayed fake capture/decode/launcher integration belongs to A4. |
| G2 display/OS matrix, T6 timing, T8 accessibility | NOT RUN | Need hardware/OS matrix, 30-run measurements, and keyboard/VoiceOver checks. |
| G6 release | NOT RUN | Full Xcode, chosen release signing identity, release authorization and clean installation tests required. |

## Claim status

- **U1 / U3:** open. Experimental capture and selector compile; crop mapping, overlay exclusion, permission flow, scene freshness and desktop behavior require the [manual matrix](manual-tests.md).
- **U2:** open. Exclusive Carbon wrapper compiles. No background shortcut, collision, alternate-layout or permission behavior claim.
- **U4:** supported on this host by signed sandbox runtime handoff to TextEdit, visual content, exact UTF-8 and retained-file checks. Other default editors and OS versions remain open.
- **U5:** native Vision supports the current synthetic baseline on this host. Deployment-floor coverage and unsupported-payload fixtures remain open; G1 is not fully accepted.
- **U6:** session identity invariants pass. End-to-end late-callback/launch tests and performance remain open.
- **U7:** local signed build exists. Distribution and runtime sandbox acceptance remain open.

## Platform source checks

The installed SDK headers for `SCStreamConfiguration.sourceRect`, `SCContentFilter.pointPixelScale`, application exclusion, the macOS 14 screenshot method, and Vision revision 4 were inspected; the whole application then compiled against those signatures. Apple documents the [content-filter API](https://developer.apple.com/documentation/screencapturekit/sccontentfilter) and [asynchronous NSWorkspace handoff](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:configuration:completionhandler:)). These checks establish API usage, not G0 behavior. The implementation uses the reviewed macOS 14 screenshot path, not the newer screenshot configuration API.
