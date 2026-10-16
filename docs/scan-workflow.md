# Scan-to-open core composition — 16 October 2026

PR #8 was reviewed at `769445378fa603d4d4381f40360355fb9a875245`, with no blocking findings or unresolved review threads and a successful required [PR validation run](https://github.com/bgaechter/QRSnap/actions/runs/38801517656). It was merged as `46386346ff5f75a16955b9314ba74e9ce393bb7b`. This follow-up starts from that merged commit in `feature/scan-open-workflow`, worktree `/Users/benny/.codex/worktrees/scan-open-workflow/QRSnap`.

## Behavior implemented

`ScanWorkflow` connects the real coordinator and dispatcher through injected capture, decoder, storage and launcher boundaries. A single HTTP(S) observation dispatches automatically; original text goes through retained document storage. Multiple observations, including duplicate strings and nil text, require a choice before any dispatch preparation. Only the selected observation can proceed.

Known external URI handlers require confirmation, with Open as text available as an alternative. Blocked schemes require an explicit text action. Unknown schemes retain the original string as text. A changed handler generates a new confirmation request ID; callbacks from the previous prompt cannot approve it. One prepared payload is reused throughout the chosen observation's actions.

The coordinator's opening gate is claimed immediately before the launcher, after handler resolution and storage. Storage failures, missing handlers and unsupported payloads terminate without pretending a handoff occurred. Terminal failures include the original text and any completed document URL for later recovery UI. Cancellation invalidates prompts/tasks before publishing the terminal event; late completions cannot finish a replacement scan. A handoff already submitted to another application cannot be retracted.

The launcher factory receives a repeatable session-validity predicate. A host must pass it to `WorkspacePayloadLauncher` (or an equivalent adapter checking immediately at the OS call). It must check screen permission before `beginSelection`, present/dismiss token-scoped UI, and display confirmations using their request IDs. Core events carry payloads for UI, never for logging.

## Validation and limits

The integrated standalone suite passed **58 methods with zero assertion failures**, including **13 new workflow methods** and the existing Vision fixtures. [Test log](evidence/scan-workflow-tests.log). The [app build/signature audit](evidence/scan-workflow-build.log) and [generated-project/plist checks](evidence/scan-workflow-project.log) passed. Environment and source hashes are in the [evidence record](evidence/scan-workflow.json). Local full Xcode/XCTest is **NOT RUN** because this host selects Command Line Tools; the PR's hosted validation check records its own result separately.

Independent review found and the tests cover a cancelled-caller edge case: failed preparation must terminate the still-current session rather than consume its choices and leave it busy. Cancelled confirmation/text actions also cannot schedule a new dispatch task. The final reviewed source has no remaining blocking findings.

Core integration uses synthetic observations and fake OS boundaries; it does not open applications or exercise screen permission. The app's existing feasibility controls remain unchanged and do not automatically open decoded content. Production window composition, chooser/confirmation/recovery views, Copy/Save controls, settings and signed scan-to-open GUI evidence remain pending. This is independent core progress, not G4 acceptance.

App Sandbox, Hardened Runtime, macOS 14 deployment floor, routing policy and text retention are unchanged. The build stays in this task's worktree. The screen-permission worktree's authorized binary and its grant are untouched.

## Remaining G0 gates

The [runtime record](screen-permission-runtime.md) and [manual matrix](manual-tests.md) remain authoritative. This task adds no new G0 runtime pass:

- **NOT RUN:** macOS 14/Intel; external/1×/portrait/negative-origin displays and attach/detach/topology changes.
- **NOT RUN:** fresh-identity OS denial, alternate keyboard layout, arbitrary Space switching and Stage Manager, other default text editors.
- **Incomplete:** pointer-free exact right-origin marker bounds and content change during a held drag; GUI cancellation during capture and repeated-hotkey races.
- **NOT RUN:** 30-run timing, peak memory/leak and 16-megapixel validation, complete keyboard/VoiceOver checks.
- **Separate release gates:** Developer ID signing, notarization/stapling and clean installation/first-grant validation.

Existing named-host sandbox capture, 2× marker mapping, overlay exclusion, post-invocation freshness, physical shortcut, full-screen Space cancellation, revoke/recover and TextEdit retention results remain the earlier recorded evidence. Mocked workflow tests do not extend those results to other environments.
