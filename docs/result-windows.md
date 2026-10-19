# Result interaction windows — 16 October 2026

[PR #9](https://github.com/bgaechter/QRSnap/pull/9) was reviewed at `fd9cd81f574e753e0eca2d5d064fe2c6088223a0` without blocking findings or unresolved threads. Its [required validation](https://github.com/bgaechter/QRSnap/actions/runs/38957956879) passed, including 58 hosted XCTest methods and the ad-hoc Release archive. It was merged as `c710a8a0875019cac6373efe33f52035ee4e981a`.

This follow-up implements A3 confirmation/failure views and the reusable result chooser. It starts from that merge in branch `feature/result-windows`, worktree `/Users/benny/.codex/worktrees/result-windows/QRSnap`. The named-host G0 text-storage/handoff evidence supports this independent work; full G0/G3/G4 acceptance remains open.

## Implemented behavior

- One chooser entry per observation, preserving duplicate strings, nil text and empty text. Previews are bounded independently of original payloads.
- Custom URI confirmation displays the destination and handler and offers Open, Open as text and Cancel. It returns the workflow's request ID so a superseded confirmation cannot approve a new handler.
- Blocked text and retained-text failures offer explicit Copy and Save. Original Unicode, whitespace and empty strings are preserved. Save uses a generic filename and a native save panel; failures keep the payload available.
- No-code/unsupported/capture errors have distinct recovery messages and Retry/Cancel. Terminal recovery data belongs to its presentation even after the workflow session has ended.
- Window actions carry session/request IDs. Presentation identity guards delayed controls and Save callbacks; programmatic dismissal does not cancel a replacement scan. The windows retain decoded values, never screenshot images.

**Preview result workflow…** in the menu and controls window drives the real `ScanWorkflow` through fake capture/decoder/storage/launcher boundaries. It supplies fixed synthetic observations and intentionally simulates write/open failures to expose recovery paths. It does not request screen access, capture the desktop, create automatic documents or open applications. Copy and Save remain real, explicit user actions. The existing Scan command still shows capture evidence; actual screen scans do not yet use these result windows or launch decoded content.

The requested MIT `LICENSE` is included with a QRSnap contributors copyright notice.

## Validation boundary

The [58-method standalone suite](evidence/result-windows-tests.log), [generated project/plist checks](evidence/result-windows-project.log), and [application build/signature audit](evidence/result-windows-app.log) pass. Eleven additional hosted AppKit tests exercise the actual controls with injected clipboard, save-panel and file-write boundaries: duplicate observations, stale controls/callbacks, exact Unicode/empty text, cancellation, retry and reentrancy. Full Xcode is unavailable locally; actual execution of these 11 tests belongs to the PR's hosted CI check, not the standalone count.

App Sandbox and Hardened Runtime remain enabled, with exactly one additional narrow capability: user-selected file read/write for explicit Save. [Decision and consequence](decisions.md#explicit-text-export--16-october-2026). The frozen screen-permission runtime binary is preserved.

## Signed preview runtime

The final local candidate was launched on macOS 26.5.2 (25F84), arm64, with ad-hoc CDHash `b4b78a2addfad2837bfffe91ed8df88010caa417` and executable SHA-256 `e0cf8233b790c9b16fecc2849ecc4d70ca60df7146fb2fb73446dd8b6b725acf`. [Machine-readable record](evidence/result-windows-runtime.json) includes source hashes, exact entitlements and the separate earlier preview snapshot.

- **PASS, synthetic GUI:** disclosed preview, seven separate chooser entries (including duplicates, nil and empty), visibly flattened previews, retained Unicode text, Retry, displayed custom destination/handler, simulated launch-failure recovery and Escape dismissal.
- **PASS, native sandbox Save:** a chosen new file in `/private/tmp` contains exactly 65 UTF-8 bytes, including leading spaces, Unicode, line breaks and a trailing tab. SHA-256: `af1be108a9d22560f31d7e0e79d60c133c8a29dd4816549c857afb0dd81a9a1b`. A second native Save was cancelled; the original text remained available and the window showed “Save cancelled.”
- **PASS on the earlier snapshot:** blocked text offered text actions without a destination Open action; Escape dismissed it. The final controller differs only by flattening the bounded chooser label. The final candidate independently repeated chooser, confirmation, recovery, native Save/cancel and Escape checks above.
- **NOT RUN in signed GUI:** real clipboard Copy, native write failure/stale-sheet replacement, full keyboard/VoiceOver coverage. Injected controller tests cover the corresponding state and byte-preservation contracts; they are not native runtime evidence.

No screen access or external launch was requested by the preview. No screenshot was written to disk. The previously authorized capture executable still hashes to `2e2469336d23901082c47560c7de4ee8154668dc9fee5072afc868b5d15cc338`; its grant and system defaults were unchanged. These results do not establish actual screen-scan-to-open composition or wider OS/display compatibility.

## Remaining gates

The [G0 manual matrix](manual-tests.md) remains open: macOS 14/Intel; external, 1×, portrait and negative-origin displays; attach/detach; fresh OS denial; alternate keyboard layout; arbitrary Space changes/Stage Manager; alternate editors; exact right-origin marker checks and held-drag freshness; GUI capture-cancellation races; timing/memory and accessibility. This PR adds no capture compatibility result.

Next workflow dependency: connect the result controller to the real permission/selection/capture flow and verify actual HTTPS, Unicode text, chooser and URI-confirmation behavior on a signed candidate, while preserving the remaining compatibility limits. Settings/configurable shortcut and complete keyboard/VoiceOver validation remain pending. Developer ID signing, notarization/stapling and clean installation are separate release gates.
