# QRSnap

Scan a QR code on your screen and open it in the default app. Native macOS menu-bar app for **macOS 14+**.

## Use

1. Open QRSnap and choose **Scan QR code…**.
2. Allow screen access when prompted. Quit and reopen QRSnap if macOS requires it.
3. Drag around a QR code in another app, including its border. **Escape** cancels.

Enable **Control-Shift-Q** or choose another shortcut in **Settings…**. The shortcut starts disabled; menu scanning is always available. Shortcuts use physical key positions.

| Content | Action |
| --- | --- |
| HTTP/HTTPS link | Opens in your default browser. |
| Text or an unknown link type | Opens as a UTF-8 file in your default text app. |
| Registered app link | Asks before opening. |
| `file:`, `javascript:`, `data:` | Offers text actions only. |
| Multiple codes | Lets you choose one. |

Failed scans offer recovery. **Tab / Shift-Tab** moves between controls; **Space** activates them. Rectangle selection requires a pointer and stays on one display.

## Privacy

Screenshots stay in memory. No analytics or payload logging. Scanned text files remain until you delete them; find them under **Show scanned text files…**. Copy and Save run only when selected.

## Build and test

Requires a Mac with Swift 6 and the macOS SDK.

```sh
./scripts/build-app.sh
open build/QRSnap.app
./scripts/test.sh --core-only
./scripts/test.sh
```

The build is ad-hoc signed. Rebuilding can invalidate screen access; use `APP_OUTPUT_PATH` to preserve an authorized app. Full Xcode can build and test `QRSnap.xcodeproj`. See [development and CI](docs/ci.md).

## Status

Manually live tested. See the [validation record](docs/mvp-live-runtime.md) and [remaining compatibility checks](docs/manual-tests.md). Developer ID signing, notarization and clean-install release validation remain pending.

[Product plan](01-product-and-technical-plan.md) · [Implementation evidence](docs/claims.md) · [MIT License](LICENSE)
