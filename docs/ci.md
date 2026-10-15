# macOS pull-request validation

The `macOS validation` workflow runs on pull requests, including stacked PRs targeting a feature branch, and pushes to `main`. Pull requests test GitHub's proposed merge commit. A manual run is available on the default branch. At introduction, the CI change was stacked on `feature/payload-dispatch` ([PR #3](https://github.com/bgaechter/QRSnap/pull/3)), which depended on `feature/scan-coordinator` ([PR #2](https://github.com/bgaechter/QRSnap/pull/2)). Those changes are now integrated into `main`; their historical hosted results are retained below.

The stable `PR validation` job checks that the committed project matches its generator, runs the complete standalone suite with synthetic Vision fixtures, builds the ad-hoc signed app, audits its signature and entitlements, builds and runs the app-hosted XCTest target, then archives and verifies the Xcode Release app. Failures remain failures; there is no automatic fallback to core-only tests or disabled sandboxing. Logs and XCTest result bundles are retained for seven days as workflow artifacts. A separate `QRSnap-adhoc-pr-<tested-commit>-<attempt>` artifact contains the verified Release app ZIP. Build products and caches stay in the runner's checkout.

## Required merge gate

[`../.github/rulesets/main.json`](../.github/rulesets/main.json) defines the repository rule for `main`: changes require a pull request, the branch must be up to date with its base, and the exact `PR validation` check must pass. The check is bound to GitHub Actions (app ID `15368`, verified from this repository's successful check run). Force pushes and branch deletion are blocked, with no bypass actors. Zero approving reviews are required so the repository owner can merge their own validated PRs; this rule does not require a second contributor.

**Committing this JSON does not activate branch protection.** Repository rules are a separate GitHub setting, and the connected GitHub App does not provide administration access. After the renamed check appears and passes on this implementation PR, an administrator can open **Settings → Rules → Rulesets → New ruleset → Import a ruleset**, select `main.json`, review it and save it with enforcement **Active**. This can be enabled before merging the implementation PR.

Alternatively, from a checkout containing this file, using an administrator's authenticated GitHub CLI with repository Administration write permission:

```sh
gh api --method POST repos/bgaechter/QRSnap/rulesets \
  --input .github/rulesets/main.json
gh api repos/bgaechter/QRSnap/rulesets
```

Import/create it once; update the existing ruleset instead of creating duplicates. Verify the saved rule targets only `refs/heads/main`, is active, and requires `PR validation` from GitHub Actions with strict status checks. Keep that job name stable across runner/Xcode upgrades. All PR bases remain enabled in the workflow for stacked changes. Merge queues are not enabled; add the `merge_group` trigger before adopting them.

## Release archive and reviewer artifact

`bash scripts/ci-check.sh archive` runs `xcodebuild archive` with the shared `QRSnap` scheme and Release configuration in a unique `.build/ci/archive-*` directory. It verifies the actual app under `QRSnap.xcarchive/Products/Applications`, including the original Xcode signature, exact App Sandbox entitlements and macOS 14.0 deployment floor. The separate optimized command-line build remains covered by the `app` stage.

Xcode can disable Hardened Runtime for ad-hoc signing. After auditing the original archive, the archive stage explicitly applies an ad-hoc signature with Hardened Runtime and the repository's sandbox entitlements, then strictly verifies that final app again. This checks the final packaging/signing operation without implying that Xcode supplied the final runtime flag. Original and final signature/entitlement reports are retained with the logs.

The final app is zipped using `ditto --keepParent` to preserve executable permissions and the bundle layout. Download the `QRSnap-adhoc-pr-<tested-commit>-<attempt>` artifact from the workflow run, then extract its inner `QRSnap-adhoc-pr.zip`. Uploading the app requires successful validation; diagnostic logs are retained even when a stage fails. Local archive reruns use fresh directories and preserve earlier archives and ZIPs; stage and signature logs are refreshed for the latest invocation.

The app is an ad-hoc PR test build for the architectures recorded by Xcode, not a Developer ID-signed or notarized distribution. Packaging does not launch it, request screen access, or accept any manual runtime gate. Developer ID signing, notarization, clean-install testing and G0/G6 acceptance remain separate release work.

## Environment and reproduction

The workflow selects `macos-15` (Apple silicon) and Xcode 16.4 through `DEVELOPER_DIR`. GitHub currently lists both the [runner label](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [Xcode installation path](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md). These images change; the environment step records the actual OS, architecture, compiler, SDK and checked-out commit. A missing selected Xcode installation fails explicitly and needs a reviewed workflow update. This job does not establish macOS 14 or Intel runtime compatibility.

On a Mac with full Xcode installed and its initial setup completed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/ci-check.sh
```

Individual stages are `environment`, `project`, `fixtures`, `app`, `xcode` and `archive`, for example `bash scripts/ci-check.sh project`. Project checks regenerate in a temporary copy and preserve local project edits. Artifacts are written under `.build/ci`; the command-line build also uses `build/QRSnap.app`. The `xcode` stage uses [`xcodebuild test`](https://developer.apple.com/library/archive/technotes/tn2339/_index.html), which builds the app and test bundle before running tests. XCTest and Vision need a working macOS GUI/graphics environment; Command Line Tools alone do not satisfy the Xcode stages.

## Permissions and evidence boundaries

The workflow uses an ephemeral GitHub-hosted runner, `contents: read`, and no repository secrets or signing certificate. Checkout does not persist credentials. [Checkout v7.0.1](https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1) and [upload-artifact v7.0.2](https://github.com/actions/upload-artifact/commit/cf430e030ddbb5b0abf93d22962f4752f3646cd9) are pinned to their official release commits, verified on 14 October 2026. Publishing this workflow requires repository write access that permits workflow-file changes; a GitHub App needs the corresponding [Workflows permission](https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents). Fork runs may require a maintainer's standard GitHub Actions approval.

The XCTest host launches the feasibility app. Its startup builds the menu; screen capture, the global shortcut and synthetic external-app handoff require explicit menu actions and are not invoked by these tests. CI neither requests screen-recording consent nor changes privacy settings or default applications. Preserve this property when changing app startup or tests. Only committed synthetic fixture data belongs in this job.

Passing CI would provide compiler, generated-project, synthetic-fixture, local signature and XCTest evidence on the recorded runner. It would not accept G0: selection/crop accuracy, overlay exclusion, privacy consent/revocation, shortcut behavior, default-handler access, display/Spaces behavior and deployment-floor compatibility still require the manual matrix. Ad-hoc signing is not Developer ID distribution or notarization.

At introduction, hosted CI and XCTest were **NOT RUN**. The first hosted run is now recorded below; the development Mac still selects Command Line Tools and has no full Xcode.

Local introduction checks on 14 October 2026: shell/YAML syntax, generated-project equality, preservation of deliberately stale project edits, and the explicit missing-Xcode failure path passed. The app stage passed its ad-hoc signature/sandbox/runtime audit; the standalone fixture stage passed 19 methods with zero assertion failures on macOS 26.5.2 arm64 with Swift 6.3.3. These results do not establish the selected hosted runner result.

## First hosted run and SDK compatibility fix

[Run 38634192586](https://github.com/bgaechter/QRSnap/actions/runs/38634192586), on PR #4 at source commit `8e2b6b464bf33ea8ff930c43af37f1dda6a7fc98`, used macOS 15.7.9 arm64, Xcode 16.4, Swift 6.1.2 and the macOS 15.5 SDK. Environment/project checks and all 19 standalone methods passed. App compilation failed because the SDK imports `SCShareableContent` without a `Sendable` conformance and its asynchronous return crosses into `ScreenCaptureService`'s main-actor context. Signature validation and hosted XCTest were consequently **NOT RUN**.

The follow-up uses `@preconcurrency import ScreenCaptureKit` only in the capture adapter, as suggested by that compiler diagnostic. This is a [Swift migration mechanism](https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/CommonProblems.md#preconcurrency-import) that relaxes diagnostics for an imported framework; it does not make the imported type `Sendable` or establish thread safety. Application-side access to the returned content is read-only, stays in the main-actor capture invocation, and only selects the display/application used to construct the framework's filter. These references are not stored in application state or passed to another application task. The filter/configuration remain invocation-local; only the resulting `CapturedFrame` leaves the adapter. Preserve these constraints when editing capture code and reconsider the import once supported SDKs provide the required annotations.

Moving capture to another isolation domain or replacing the async API with a callback/continuation bridge would change more of the adapter without resolving the missing framework contract. This change therefore keeps existing isolation, cancellation checks, permission preflight, sandbox configuration and runtime gates, without adding an unchecked conformance or raising the SDK requirement. Runtime capture acceptance remains a separate G0 requirement.

The follow-up hosted run below now verifies the Xcode 16.4 build/signature checks and XCTest. Local `ci-check.sh project` and `ci-check.sh app` both passed after the import change, including the generated-project comparison, app compilation, ad-hoc signature, sandbox, hardened-runtime and deployment-floor audits. These checks use Swift 6.3.3 and cannot prove the older-toolchain result. The app was not launched and the separate runtime-verification worktree was not changed.

## Combined core dependency

The CI branch merges published dispatcher/coordinator tip `102b2796b4b2da10334b116adab349d078e443db` while preserving the CI compatibility fix as its first-parent history. Both the generated Xcode project and the standalone runner include all 42 methods: 17 original core methods, 13 dispatcher methods, 10 coordinator methods and two Vision fixture methods. The earlier 19-method results above are historical results for the initial feasibility source.

The dependency's [combined-core verification](dispatch-handoff.md#combined-core-verification) records 42 standalone methods passing on the development Mac. The next hosted run must validate this combined source with Xcode 16.4, including the app-hosted XCTest target. The coordinator and dispatcher still await production composition; merging them into the CI branch does not enable automatic routing or accept any G0/G3/G4 runtime gate.

After merging this dependency, `ci-check.sh project` and `ci-check.sh app` both passed locally: the combined generated project is current, and the complete app builds with the compatibility import and passes the signature/entitlement audits. No standalone rerun was needed for this import-only adapter change; the dependency retains its 42-method evidence. The app was not launched. Hosted validation of the combined tree passed in the follow-up run below.

## Combined hosted result

[Run 38634996862](https://github.com/bgaechter/QRSnap/actions/runs/38634996862) completed successfully on 14 October 2026 for source commit `1f4fdbfb92b4ad97d1e61100fdf6020fe7acf04f`. It tested the proposed merge into then-current main (the PR was subsequently retargeted to its dispatcher dependency). Environment: macOS 15.7.9 arm64, Xcode 16.4, Swift 6.1.2, SDK 15.5. Generated-project checks, **42 standalone methods with zero failures**, app build/signature/entitlement audit and **42 hosted XCTest methods with zero failures** all passed. Results and logs were uploaded as workflow artifacts; [sanitized summary](evidence/hosted-ci.json) records the result permanently.

The command-line app build was separately verified with App Sandbox and Hardened Runtime. Xcode reported that it disabled Hardened Runtime for its ad-hoc-signed XCTest host; the hosted tests therefore do not prove behavior under that protection or release signing. No test invoked screen capture or external dispatch. G0, macOS 14/Intel execution, production UI composition, timing, accessibility and release acceptance remain open. The later evidence-only commit changes documentation, not the tested implementation.
