# Adversarial Review: Native macOS screen QR reader

**Reading under review**: A native menu-bar utility should let a user select a screen rectangle with screenshot-like interaction and open its QR payload in a system-default application. The design should be small enough for AI agents to implement without inventing APIs or silently broadening scope.

**Strongest objection**: “Open the QR code with the default application” is not a complete dispatch contract. A QR can contain arbitrary text, no text representation, or an application-specific URI; accepting any string Foundation can parse as a URL can send the wrong content to another application. The reviewed plan therefore defines a typed dispatch policy and text-file lifecycle before UI implementation. Reproducing the screenshot interaction across permissions and desktop modes remains the largest unverified platform risk.

## Findings

### Premise

**[MINOR — evidence absent] Productivity benefit is unmeasured** — D16: the requirement establishes what the user wants, not how often it will be used or how much time it saves. Do not turn “one gesture is convenient” into an unsupported ROI claim. Resolution: keep the utility small; evaluate it with the requester after one working vertical slice. An external product comparison is optional and has not been performed.

### Assumptions

**[MAJOR — resolved in design; runtime open] Raw text has no single default handler contract** — The naive plan would pass every payload directly to NSWorkspace. Resolution in D5–D6: distinguish web URLs, other URIs and text; create a UTF-8 .txt document and ask the OS to open it. Falsifier: a signed prototype cannot open its created file in the current default editor, or mutates Unicode. Required evidence: U4, including sandboxed execution and two editors on controlled test accounts.

**[MAJOR — open] A documented capture API does not prove a reliable rectangle capture** — D11–D12 rely on display identity, points-to-pixels mapping, origin conversion, overlay exclusion and scene timing. A one-display demo does not establish those behaviours. Consequence: wrong screen area, clipped QR or capture of the selector itself. Resolution: synthetic corner-marker experiments and the T3 matrix before treating coordinate formulas as facts. Do not substitute arbitrary delays for a failed exclusion test.

**[MAJOR — open] Hot-key registration is not proof of permission-free operation or conflict detection** — V7 confirms a symbol and limited collision semantics, not “works everywhere without prompts.” Consequence: nonfunctional background invocation or unnecessary Accessibility access. Resolution: U2 on a signed app with clean permissions, another foreground app, a conflicting helper shortcut and a non-US keyboard layout. Keep the menu command as a fallback. Never claim all shortcut conflicts can be detected.

**[MAJOR — open] Overlay behaviour across full-screen and Spaces is not established by collection flags** — AppKit documents the flags; it does not certify this panel configuration in all target desktop modes. Consequence: the shortcut switches Spaces, puts the overlay behind the target or fails to receive Escape. Resolution: U3 recording of the actual panel implementation in the declared OS matrix. A macOS 14-only test does not prove behaviour on later releases.

### Complexity

**[MINOR — simplified] An app framework, streaming engine or OCR stack would add unearned complexity** — The request needs one still frame and a QR decoder. D8/D13/D19/D20 keep one app, a serial Vision worker and thin OS adapters. Add no daemon, continuous stream, cloud service, database, second QR library or repository-wide architecture framework without a measured failing case that requires it.

**[MINOR — bounded] Exact replication of Apple's screenshot tool is too broad** — The user named a rectangular selection interaction, not every screenshot feature. D3 explicitly includes drag/release/Escape and supports any display, but not cross-display stitching, window-selection mode, screenshot thumbnails or timed capture. This is a proposed v1 boundary, not a verified statement that users do not need those features.

### Ambiguity & uncertainty

**[MAJOR — resolved in policy] Automatically launching every URI delegates hidden side effects** — The string may be an application command, not a browser destination. D5 automatically opens HTTP/HTTPS and text, previews other registered schemes and declines active/local schemes. This reduces unintended dispatch; it does not make web URLs safe or authenticate a destination. Required tests: custom handlers, control characters, whitespace and encoded input. If the requester later wants all schemes to auto-open, record that as a separate deliberate policy change rather than broadening a regex.

**[MAJOR — resolved in design; runtime open] Temporary-file cleanup can break the receiving editor** — “Delete after open succeeds” confuses handoff with completed use. D6 deliberately retains unique text documents until user removal and exposes their folder. Consequence accepted: text scans persist, possibly containing secrets. Required evidence: exact retention disclosure and T7 filesystem/log inspection. No claim of zero storage is permitted.

**[MAJOR — open] Screen permission and distribution are part of functionality** — A debug executable with prior consent is insufficient evidence for a newly signed build. D14/D15 require grant/deny/revoke/relaunch tests and a signed sandboxed probe. API permission keys do not grant access, and notarization is not runtime QA or App Store approval. If signing credentials or an OS test machine are unavailable, report the specific release blocker.

**[MINOR — resolved as targets] “Fast” and “supports QR codes” are not measurable** — T4/T6 define a baseline corpus, timing boundaries, limits and percentile targets. These numbers are proposed acceptance criteria, not benchmark results. Baseline success cannot establish that blurry, partially hidden, binary or arbitrarily dense codes will work.

### Failure modes

**[MAJOR — resolved in contract] A cancelled scan can still launch from a late callback** — D9 requires session invalidation and a final validity check before NSWorkspace. The launch request itself is the irreversible handoff boundary. Required evidence: delayed fake capture/decode completions after Escape, timeout and a new session; all must launch nothing for the old session.

**[MINOR — explicit limit] Protected content and unavailable hardware cannot be covered by optimistic wording** — Some software prevents screenshots; Apple documents this. An unavailable second monitor is an unrun test, not a pass. Distinguish capture failures from an ordinary successful image containing no QR. Do not claim the app can bypass protection or reliably diagnose every black frame. [V12]

## Pre-mortem

1. “It worked on the developer's Mac.” The shipped build had a new signing identity, no prior screen consent and a different full-screen desktop setup. Users saw no selector or black images. The team had treated successful compilation as an end-to-end test. Preventive gate: signed fresh-permission tests and an explicit OS/display matrix.

2. A scan contained an app-specific URI. The utility opened it without revealing the destination, while another plain-text scan disappeared after its temporary file was deleted. The team had implemented “just open it” without modelling payload types or ownership of the generated document. Preventive gate: dispatch table and retention contract tests before integration.

3. An external monitor above the main display produced a flipped or offset crop. A timed-out scan later opened the wrong link because its callback was still active. Preventive gate: one geometry adapter, synthetic markers, display-ID matching and cancelled-session launch tests.

## Questions the author must answer

These are implementation gates for the assigned agents, not questions that block the user from receiving this plan.

1. Does the signed sandboxed G0 app capture only the intended region with its own overlay excluded on every supported OS? Supply the environment, expected marker bounds and actual output.
2. Can the selected hot-key wrapper activate from another foreground app without Accessibility/Input Monitoring permission? What is its demonstrated conflict behaviour?
3. Can a panel select and cancel in another application's full-screen Space without switching away? Which tested flags/activation settings achieved this?
4. Can the current .txt default handler read a document created inside the app's chosen storage location? Has Unicode and retention been checked?
5. What do the named timing targets actually measure on a reference machine? Which corpus and OS versions were run, failed or unavailable?
6. Does cancellation prevent every delayed side effect before the dispatch boundary? Supply tests with intentionally delayed callbacks.

## What survives

Apple's native frameworks provide the necessary capture, QR-detection and application-handoff primitives. Their chosen signatures compile against a macOS 14 deployment target in this environment. A single-process design with a pure routing policy, a geometry adapter and gated runtime spikes is defensible. Claims of seamless permissions, universal desktop compatibility, guaranteed decoding or measured speed do not yet survive review.

Verdict: proceed with the bounded feasibility milestone. Do not present the complete implementation as verified until the runtime gates have evidence.
