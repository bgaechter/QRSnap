# QRSnap steering instructions

## Repository workflow

- Use `git@github.com:bgaechter/QRSnap.git` as `origin`.
- Keep `main` as the integration branch. Implement changes on descriptive `feature/<task>` branches; use `fix/<task>` for focused fixes.
- Open GitHub pull requests for changes and keep each PR focused on a coherent task. Include the concrete behavior change, validation actually performed, and remaining runtime gates. Push branch updates as work progresses. Attach created PRs to the Codex chat when that capability is available.
- Use a dedicated Git worktree for each implementation task. Run independent tasks in parallel with subagents, each assigned its own branch/worktree and explicit file ownership. Never have agents edit the same checkout concurrently.
- Inspect the worktree list and working status before starting. Reuse the matching task worktree; preserve uncommitted work. Prefer Codex-managed worktrees when available. Keep generated builds and caches local to their worktree.
- Coordinate shared contracts, project generation, build scripts and final integration through one integrator. Communicate interface changes before dependent work begins.
- When work depends on an unmerged feature, use an explicitly documented stacked branch/PR; set the PR base to that dependency. Do not duplicate unrelated changes or silently target `main` with a stacked diff.
- Do not force-push, rewrite others' history, discard uncommitted work, or bypass branch protection. The initial empty repository may receive a single metadata-only `main` bootstrap commit so the initial source can be reviewed in a PR.
- Before handing off, run relevant tests/build checks, commit the task changes, push the feature branch, and report PR links, worktree paths, and unresolved dependencies. Retain active worktrees needed for review; archive only worktrees no longer needed.

## Product and evidence

- Read `01-product-and-technical-plan.md`, `03-ai-agent-implementation-plan.md`, and current `docs/claims.md` before implementation. Preserve payload routing, text retention, macOS deployment floor and sandbox requirements.
- Follow milestone dependencies. Independent core logic and tests may progress while G0 is open; do not describe production capture, routing integration or release gates as accepted without runtime evidence.
- Distinguish compilation, synthetic fixture tests, mocked side-effect tests, signed GUI runtime checks and release validation. Record NOT RUN for missing environments.
- Use synthetic QR content and harmless example URLs. Keep screenshots in memory and payloads out of logs. Do not change system defaults, privacy settings or launch-at-login settings to make tests pass.
- Keep this file current when the user changes the working style. User instructions in the active conversation take precedence.

## Local development

- `./scripts/build-app.sh` builds and ad-hoc signs the sandboxed feasibility app without launching it.
- `./scripts/test.sh --core-only` runs independent contract tests with Command Line Tools. `./scripts/test.sh` includes Vision fixtures and requires macOS graphics-service access; this is separate from the app's sandbox and screen permission.
- `python3 scripts/generate-xcode-project.py` regenerates the one-app/one-test Xcode project after source/test additions. Full Xcode/XCTest validation must be recorded separately when available.
- Keep original planning documents and their provenance. Update implementation evidence rather than rewriting historical planning claims as if they were new results.
