# macOS pull-request validation

The `macOS validation` workflow runs on pull requests, including stacked PRs targeting a feature branch, and pushes to `main`. Pull requests test GitHub's proposed merge commit. A manual run is available once the workflow is on the default branch. The CI change is initially stacked on `feature/initial-feasibility`.

The job checks that the committed project matches its generator, runs the complete standalone suite with synthetic Vision fixtures, builds the ad-hoc signed app, audits its signature and entitlements, then builds and runs the app-hosted XCTest target. Failures remain failures; there is no automatic fallback to core-only tests or disabled sandboxing. Logs and XCTest result bundles are retained for seven days as workflow artifacts. Build products and caches stay in the runner's checkout.

## Environment and reproduction

The workflow selects `macos-15` (Apple silicon) and Xcode 16.4 through `DEVELOPER_DIR`. GitHub currently lists both the [runner label](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [Xcode installation path](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md). These images change; the environment step records the actual OS, architecture, compiler, SDK and checked-out commit. A missing selected Xcode installation fails explicitly and needs a reviewed workflow update. This job does not establish macOS 14 or Intel runtime compatibility.

On a Mac with full Xcode installed and its initial setup completed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/ci-check.sh
```

Individual stages are `environment`, `project`, `fixtures`, `app` and `xcode`, for example `bash scripts/ci-check.sh project`. Project checks regenerate in a temporary copy and preserve local project edits. Artifacts are written under `.build/ci`; the command-line build also uses `build/QRSnap.app`. The `xcode` stage uses [`xcodebuild test`](https://developer.apple.com/library/archive/technotes/tn2339/_index.html), which builds the app and test bundle before running tests. XCTest and Vision need a working macOS GUI/graphics environment; Command Line Tools alone do not satisfy the Xcode stage.

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

The compatibility change's selected Xcode 16.4 build/signature result and hosted XCTest are **NOT RUN** until the follow-up CI run finishes. Local `ci-check.sh project` and `ci-check.sh app` both passed after the import change, including the generated-project comparison, app compilation, ad-hoc signature, sandbox, hardened-runtime and deployment-floor audits. These checks use Swift 6.3.3 and cannot prove the older-toolchain result. The app was not launched and the separate runtime-verification worktree was not changed.
