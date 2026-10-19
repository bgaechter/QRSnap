# QRSnap

A native macOS menu-bar app that reads a QR code from a selected area of your screen and opens its contents in the appropriate default application. Requires **macOS 14 or later**.

The MVP connects screen permission, drag selection, capture, Vision decoding, result windows and application handoff. It includes persistent, configurable keyboard shortcuts and recovery actions. The build uses Apple frameworks only, with App Sandbox and Hardened Runtime enabled.

## Build and run

Use a Mac with Apple Swift 6 and the macOS SDK:

```sh
./scripts/build-app.sh
open build/QRSnap.app
```

The script produces an **ad-hoc signed development app** for the host architecture. It does not launch the app or request permission by itself. This is not a Developer ID-signed or notarized distribution.

You can also download the `QRSnap-adhoc-pr-…` artifact from a successful [GitHub Actions run](https://github.com/bgaechter/QRSnap/actions), then extract its inner `QRSnap-adhoc-pr.zip`. Review the source and validation result for that build. macOS may restrict opening a downloaded ad-hoc app; building locally or using an authorized stable signing identity is preferable for ongoing use.

With full Xcode, open `QRSnap.xcodeproj` and select the shared **QRSnap** scheme. The `build-app.sh` script accepts `SIGNING_IDENTITY` to select an existing identity for a deliberate signed build; configure Xcode signing separately. An ad-hoc rebuild changes the app's identity and can invalidate an existing Screen Recording grant. Keep the authorized test app intact when making another build:

```sh
APP_OUTPUT_PATH="$PWD/build/validation/QRSnap.app" ./scripts/build-app.sh
```

Use **Screen access…** for current permission guidance. The [historical screen-access diagnosis](docs/screen-permission-runtime.md) explains why System Settings can show a grant while a changed binary still fails; its diagnostic menu belongs to that earlier build. Do not disable the sandbox or reset system privacy settings to make a build work.

## Use QRSnap

1. Open the app and choose **Scan QR code…** in its window or QR menu-bar menu.
2. If needed, read the explanation and explicitly continue to macOS screen permission. Review **System Settings → Privacy & Security → Screen & System Audio Recording**. You may need to quit/reopen the exact app you authorized, then choose Scan again.
3. Drag around the entire QR code, including its border, in another application's window. Selection stays on one display. Press **Escape** or use **Cancel current scan** to cancel.
4. QRSnap routes the result according to the table below. A scan that fails presents a recovery window with Retry/Cancel and, when text is available, Copy/Save.

| QR content | Behavior |
| --- | --- |
| One valid HTTP/HTTPS URL | Opens once in the default browser. |
| Plain text, empty text, unknown URI, Wi-Fi/vCard text, or a bare `www` address | Writes the original UTF-8 text to a retained document and opens the default `.txt` application. It does not join Wi-Fi networks or import contacts. |
| Registered app URI, such as `mailto:` | Shows the destination and handler for confirmation; Open as text is also available. A changed handler requires a new confirmation. |
| `file:`, `javascript:`, or `data:` | Offers explicit text actions; never launches that destination directly. |
| Multiple QR observations | Lists each separately, including duplicates and unsupported observations; opens only the one you choose. |
| No code, unsupported payload, or oversized text | Explains the problem and offers recovery. |

**Settings…** lets you enable or disable the global shortcut and record a replacement. The default is **Control-Shift-Q**, initially disabled until you enable it. Preferences persist across launches. If registration conflicts, the settings window explains the failure and the Scan menu remains available. Shortcuts bind to physical keys; their displayed names use US key positions and may differ on other layouts. There is no launch-at-login helper or global keyboard monitoring.

Opening the app does not start a scan, request screen permission or open decoded content. Only your explicit scan starts capture. An enabled, previously saved shortcut is restored at launch.

## Privacy and retained text

- Captured pixels stay in memory and are released after processing; screenshots are not saved. QRSnap excludes its own windows from capture, so display QR content in another app.
- No app-originated network requests, analytics, payload logs or scan history database. A browser or other receiving application may make network requests and retain its own history.
- Text documents opened by QRSnap remain under its sandboxed Application Support directory, `local.benny.QRSnap/Scanned Text`, **until you remove them**. Use **Show scanned text files…** to find them. Filenames are random UUIDs and UTF-8 content is preserved.
- Copy changes the clipboard only when selected. Save exports the original text to a user-chosen file using the narrow user-selected file entitlement. Cancelled or superseded Save callbacks do not write a file.
- Cancellation invalidates work and stale controls before a new scan. It cannot retract an external application handoff already submitted to macOS.

## Validation and current limits

[CI](docs/ci.md) checks deterministic project generation, the standalone core/Vision suite, app signature and exact entitlements, hosted XCTest, and the Xcode Release archive. Its `PR validation` check produces logs, `.xcresult` results and an ad-hoc reviewer app. The standalone suite and hosted suite have different counts because AppKit integration/settings/window tests run only under hosted XCTest.

```sh
./scripts/test.sh --core-only
./scripts/test.sh
# Full Xcode required:
bash scripts/ci-check.sh
```

Vision fixture tests need macOS graphics services; an agent command sandbox can prevent them from running. Tests use synthetic QR content and injected capture/launch boundaries; they do not request Screen Recording access or open another application. See the [MVP implementation record](docs/mvp.md) for the exact CI results and evidence boundary.

Previous named-host checks on macOS 26.5.2 / Apple silicon verified sandboxed screen capture, 2× crop mapping, overlay exclusion, screen-permission recovery, shortcut conflict handling and TextEdit handoff. The new combined MVP has automated integration coverage; a live, signed **screen scan → default application** smoke test of this exact candidate remains to be recorded. Earlier component checks do not establish that final runtime result.

Other limits remain explicit: macOS 14 and native Intel execution; external/1×/portrait/negative-origin displays; the full permission, keyboard-layout, Spaces and Stage Manager matrix; alternate default editors; performance/memory profiling and complete VoiceOver coverage. Drag selection requires a pointer. Captures are limited to 16 million pixels, decoded text to 64 KiB, and capture/decode processing to five seconds. There is no arbitrary damaged/blurred QR recovery guarantee. Developer ID signing, notarization and clean-install release validation remain separate work. [Manual verification matrix](docs/manual-tests.md).

## Development

- `QRSnap/App`: menu, settings, production composition, result windows and OS handoff adapter.
- `QRSnap/Scan`, `Selection`, `Capture`, `Decode`, `Routing`: session coordination, region selection, ScreenCaptureKit, Vision and payload policy.
- `QRSnapTests`: deterministic contracts, AppKit integration tests and synthetic QR fixtures.
- `scripts`: local builds/tests, project generation and development fixture tools.
- `docs`: design contracts, historical evidence, current validation and remaining runtime checks.

After adding sources/tests, regenerate the project with `python3 scripts/generate-xcode-project.py`. Historical planning documents and their [originals](docs/originals) are retained; start with [the planning package](00-READ-ME.md) and [current evidence](docs/claims.md).

## License

[MIT License](LICENSE).
