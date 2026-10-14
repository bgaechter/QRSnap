# Initial implementation handoff

**Task IDs:** A0 started; independent A1 work implemented. No Git commit exists in this folder. Source fingerprint: `evidence/source-sha256.json`.

**Implemented:** five Markdown document conversions with archived originals; one app/test Xcode project; Command Line Tools build/test scripts; frozen typed contracts; routing policy; local selection geometry; session validity/phase guards; serial Vision decoder; exact UTF-8 document storage; synthetic fixtures; a menu-bar feasibility app with explicit permission, shortcut and synthetic handoff actions and an in-memory capture report.

**Verified:** full application compilation, strict local ad-hoc signature verification, project/plist syntax, document preservation, 19 standalone test methods, exact baseline Vision fixture decoding, four characterization observations. See `claims.md` and raw logs.

**Not run:** full Xcode/XCTest, GUI launch, signed capture/permission/shortcut/Spaces/display tests, external editor handoff, macOS 14 and Intel execution, timing and memory measurements, VoiceOver, release signing/notarization. The current build does not automatically open decoded content.

**Findings:** CLT does not provide XCTest here; the same assertions run through the standalone harness. Agent command sandbox blocks graphics-service access; narrowly scoped synthetic tests pass with that access. App Sandbox stays enabled. Geometry arithmetic passes but platform mapping remains provisional. See `decisions.md`.

**Next dependency:** G0 manual runtime experiments in `manual-tests.md`. Full production A2–A4 behavior must wait for the affected G0 evidence; independent fixture expansion and pure-core improvements can continue. No overall acceptance gate has been silently marked complete.
