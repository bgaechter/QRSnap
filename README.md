# QRSnap

Native macOS menu-bar QR reader, targeting macOS 14 and later. **Current milestone: A0 feasibility proof plus independent A1 core implementation. G0 remains open.**

Start with the [planning package](00-READ-ME.md), [implementation plan](03-ai-agent-implementation-plan.md), and [current evidence](docs/claims.md). The five source documents were converted to linked Markdown without dropping requirements. Exact originals are retained in [docs/originals](docs/originals); hashes and the conversion check are in [docs/evidence](docs/evidence).

## Build and test

Apple Swift 6 and the macOS SDK are required. The commands below use only Apple frameworks and do not download packages.

```sh
./scripts/build-app.sh
./scripts/test.sh
```

The build produces `build/QRSnap.app` for the host architecture with App Sandbox, Hardened Runtime, and a **local ad-hoc signature**. It does not launch the app, request permission, or provide Developer ID/notarization. `SIGNING_IDENTITY` can select an existing identity for a deliberate signed test. `ARCH=x86_64` selects an Intel build; Intel execution has not been tested.

`test.sh` compiles the same test methods as the XCTest target into a standalone runner, so Command Line Tools can execute them without XCTest. `./scripts/test.sh --core-only` runs 17 routing, geometry, session and storage tests. The full suite also runs Vision against 17 synthetic fixture images. macOS graphics-service access is required: an agent's command sandbox can block Core Image/Vision even though the installed frameworks compile. Run the fixture tests from a normal local terminal or authorize the narrowly scoped test command. This does not require screen-recording permission and does not change the app's entitlements.

With a full Xcode installation selected, use `QRSnap.xcodeproj` and its shared `QRSnap` scheme, or:

```sh
xcodebuild -project QRSnap.xcodeproj -scheme QRSnap -configuration Debug build
xcodebuild -project QRSnap.xcodeproj -scheme QRSnap -destination 'platform=macOS' test
```

These Xcode commands have **not been executed** on the current Command Line Tools installation. The project has one app target and one hosted test target. `Package.swift` offers optional `swift test` validation where XCTest is installed; it builds the shared sources as a test module, not as an extra framework in the app.

## Try the feasibility proof

Open `build/QRSnap.app` when ready to run the [manual checks](docs/manual-tests.md). It adds a QR icon to the menu bar and opens a small controls window with Scan and text-test actions. Reopen it with **Show test controls…**; launching the app alone requests no access or capture.

1. Put a synthetic fixture from `QRSnapTests/Fixtures` in Preview or another application. QRSnap excludes its own windows from capture.
2. Choose **Scan QR code…**. The app explains screen access before offering to request it. Granting, denying, revoking, and relaunching need separate manual verification.
3. Drag within one display, including the code's border. Escape or a click without a rectangle cancels. A preview shows the captured pixels, dimensions, display ID, and decoded observations. Inspect the image for crop accuracy and overlay contamination; close it to release the image.
4. **Enable test shortcut (⌃⇧Q)** explicitly registers Control-Shift-Q for this process. Toggle it off or quit to unregister. The menu remains available if registration fails. Background invocation, alternate keyboard layouts and conflict handling still need runtime evidence.
5. **Open synthetic text in default app…** creates a disclosed, retained UTF-8 test file and asks the default `.txt` handler to open it. Verify the bytes and editor display separately; a handoff callback only reports OS acceptance.

The proof displays scan results. Automatic URL/text dispatch, custom-scheme confirmation, production settings, result chooser and full coordinator integration are later milestones. The pure classifier already implements the planned policy, but the scan UI does not launch decoded content yet.

## Retention and limits

Captured pixels stay in memory, including the proof preview until it closes. Screenshot files are not written. The only intentionally persistent app documents are text files under Application Support / `local.benny.QRSnap` / `Scanned Text` (inside the app container when sandboxed). **Files remain until the user removes them.** The menu exposes their folder. Their names are random UUIDs; UTF-8 content is preserved. Other applications have their own retention policies.

This build makes no app-originated network requests and contains no analytics or payload logging. The initial selection limit is 16 million output pixels, subject to G0 memory measurements. A gesture cannot span displays. Drag selection is not fully accessible to nonvisual users. The [local runtime record](docs/runtime-verification.md) verifies a synthetic TextEdit handoff on this host. Screen access still reports unavailable after authorization and relaunch, so crop/exclusion checks remain blocked. macOS 14 compatibility, external displays, Spaces, Stage Manager, the full permission matrix, other default apps and release signing remain unverified.

## Project layout

- `QRSnap/`: AppKit feasibility UI, capture adapter, shared models, pure classification/geometry, serial Vision decoder, and text storage.
- `QRSnapTests/`: common XCTest/standalone assertions and synthetic fixtures.
- `scripts/`: local build, standalone tests, deterministic project generation, and fixture generation.
- `docs/`: implementation decisions, contracts, evidence and manual checks.

Regenerate the project after adding source/test files with `python3 scripts/generate-xcode-project.py`. Regenerate fixtures from the repository root with `xcrun swift scripts/generate-fixtures.swift`; the fixture generator uses Core Image and writes only synthetic PNGs and their manifest.
