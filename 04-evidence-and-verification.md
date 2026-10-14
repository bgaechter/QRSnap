# CLAIM REGISTER AND VERIFICATION RECORD
Checked: 14 October 2026

## Verification Actually Performed

Read primary Apple documentation and the installed Apple SDK headers.
Typechecked a small, nonexecuted Swift capability probe with:
  xcrun swiftc -typecheck -swift-version 6 -target arm64-apple-macosx14.0
The probe references ScreenCaptureKit capture/filter/scale APIs, Vision QR request revision 4,
NSWorkspace opening, HIToolbox registration, NSPanel collection behaviour and capture-permission symbols.
Result: exit code 0, no compiler diagnostics.
Environment: macOS 26.5.2 (build 25F84), Apple Swift 6.3.3, arm64;
selected developer directory /Library/Developer/CommandLineTools.
The probe had no entry point and was not executed. No app was implemented or launched.
This verifies source signatures/availability with this SDK and target, not behaviour on macOS 14,
older Swift toolchains, x86_64 hardware, a sandboxed app bundle or a fresh permission state.

## R1 — User Requirement
Native macOS app; keyboard-invoked rectangle selection like screenshot selection;
decode visible QR; open URLs/text through system-default applications. Source: user's request.
Everything labelled D or T in the plan is a proposal or test requirement, not a verified fact.

## Verified claims (intentionally narrow)

**V1.** Command-Shift-4 invokes crosshair selection, release captures and Escape cancels. [S1]
Implication: use the interaction as reference, but choose a separate app shortcut.

**V2.** SCScreenshotManager has a one-frame CGImage capture method using content filter and configuration;
the selected method is available from macOS 14. [S2, L1, compile probe]
Not proved: latency, prompt behaviour or compatibility of this whole app.

**V3.** SCStreamConfiguration sourceRect is documented in logical display points; output width/height
are in pixels. SCContentFilter provides pointPixelScale from macOS 14. [S3, L2]
Not proved: our AppKit-to-capture transform on every monitor arrangement.

**V4.** Apple documents excluding applications from display content and a system sharing picker for
windows, apps and displays; the reviewed sources do not establish a free-form screenshot rectangle
picker. [S4, S5, L2]
Not proved: live overlay exclusion and selection timing in our exact app.

**V5.** VNDetectBarcodesRequest returns barcode observations and supports choosing symbologies;
payloadStringValue is optional and may be unavailable. Revision 4 and QR-only configuration
typecheck at macOS 14; installed headers mark revision 4 available from macOS 14. [S6, S7, L3]
Not proved: successful decoding of our fixture corpus or arbitrary images.

**V6.** NSWorkspace provides default-handler lookup and URL/file handoff, including an asynchronous
open method and error callback. These APIs deal in URLs/files, not a universal “open arbitrary
string in editor” operation. [S8, L4, compile probe]
Inference: create a .txt document for plain text, then use default file handling.
Not proved: sandbox storage access from the user's particular editor or its text interpretation.

**V7.** RegisterEventHotKey is in the installed SDK. The header documents global registration,
non-thread-safety, kEventHotKeyExclusive and a collision error for another exclusive registration.
It also allows nonexclusive registrations; therefore it does NOT establish detection of every
conflicting shortcut. The selected symbols typecheck. [L5]
Not proved: no additional input permissions, future OS behaviour or non-US keyboard semantics.

**V8.** AppKit exposes fullScreenAuxiliary; the documented intent is sharing a Space with a full-screen
window. The proposed NSPanel/collection-behaviour declarations typecheck. [S9, compile probe]
Not proved: our nonactivating panel receives keys or appears correctly across all desktop modes.

**V9.** Apple documents screen-recording consent for capture. Its current ScreenCaptureKit overview
calls for a screen-capture usage description; its Mac sample notes restart after permission grant.
Preflight/request symbols are present in CoreGraphics. [S5, S10, L6]
Not proved: identical prompts or relaunch requirements across every supported OS version.
Do not treat an Info.plist description or code-signature entitlement as a grant of TCC consent.

**V10.** Apple documents Developer ID signing, Hardened Runtime and notarization for direct distribution;
notarization is distinct from App Review. [S11]
Not proved: the app has been signed, notarized, distributed or approved for the Mac App Store.

**V11.** The specific core API probe passed a Swift 6 typecheck with arm64 macOS 14 as deployment target.
Evidence: local tool exit code 0, empty typecheck log, recorded environment above.
Not proved: compilation of a finished application or any runtime behaviour.

**V12.** Apple states some apps may prevent screenshots of their windows. [S1]
Implication: do not promise capture of all content or bypassing protected windows.

## Unresolved Claims And Falsification Tests

**U1.** “The signed sandboxed app can obtain permission and capture the selected region.”
Owner A0/A2. Run fresh grant, denial, revocation and relaunch tests; compare a synthetic marker
crop with the selection. Falsified by denied/misleading state, overlay pixels, wrong region or
capture failure despite valid setup. Gate: G0/G2, target OS matrix.

**U2.** “The shortcut wrapper is adequate without Accessibility/Input Monitoring.”
Owner A0. Test a signed app while another application is foreground, clean permission settings,
competing registration and alternate keyboard layout. Registration success alone does not pass.
Gate: G0; retain menu fallback and revise the shortcut approach if evidence fails.

**U3.** “The selector and coordinate mapping work on all advertised display/desktop configurations.”
Owner A0/A2/A5. T3 marker and desktop-mode matrix. Falsified by a crop offset beyond the explicit
rounding tolerance, incorrect display, unintended Space change, stuck panel or unreliable Escape.
Gate: G0/G2/G5; untested configurations must not be advertised as tested.

**U4.** “The default text application can read and preserve our file in the chosen sandbox design.”
Owner A0/A3. Open generated ASCII, multiline and Unicode .txt files through NSWorkspace in a
signed sandboxed app. Verify original file bytes and observed handler behaviour. Do not delete
immediately. Falsified by unreadable files, changed content, wrong handler or lost document.
Gate: G0/G3.

**U5.** “Native Vision is sufficiently reliable for the supported baseline.”
Owner A1/A5. Run exact-payload fixtures on declared OS versions, distinguish no result, nil string
and multiple results. Record small/dense/damaged failure boundaries. Gate: G1/G5.

**U6.** “The app meets responsiveness and cancellation targets.”
Owner A4/A5. Measure defined intervals and inject late asynchronous results. A single stale launch
after cancellation falsifies correctness; failing the p95 target falsifies that performance claim.
Gate: G4/G5. Performance numbers in the plan are targets only.

**U7.** “The chosen sandbox, architectures and release settings are shippable.”
Owner A0/A6. Build/sign/package, run on intended OS/architectures and validate fresh installation.
Audit actual entitlements and privacy declarations. Missing credentials/hardware is NOT RUN.
Gate: G0/G6; compile-only evidence is insufficient.

## Primary Web Sources

### S1. [Apple Support — Take a screenshot on Mac](https://support.apple.com/en-ie/102646)

### S2. [Apple Developer — SCScreenshotManager captureImage(contentFilter:configuration:completionHandler:)](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(contentfilter:configuration:completionhandler:))

### S3. [Apple Developer — SCStreamConfiguration sourceRect](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect)
The web renderer required JavaScript; the factual units were checked in installed header L2.

### S4. [Apple Developer WWDC23 — What's new in ScreenCaptureKit, picker and screenshot sections](https://developer.apple.com/videos/play/wwdc2023/10136/)

### S5. [Apple Developer — Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)

### S6. [Apple Developer — VNDetectBarcodesRequest](https://developer.apple.com/documentation/vision/vndetectbarcodesrequest)

### S7. [Apple Developer — VNBarcodeObservation payloadStringValue](https://developer.apple.com/documentation/vision/vnbarcodeobservation/payloadstringvalue)

### S8. [Apple Developer — NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)

### S9. [Apple Developer — fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)

### S10. [Apple Developer — ScreenCaptureKit overview](https://developer.apple.com/documentation/screencapturekit)

### S11. [Apple Developer — Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Local Primary Sdk Evidence

SDK root: /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks
L1. ScreenCaptureKit.framework/Headers/SCScreenshotManager.h:133–152
L2. ScreenCaptureKit.framework/Headers/SCStream.h:112–180, 210–269
L3. Vision.framework/Headers/VNDetectBarcodesRequest.h (availability, symbologies, revision 4)
L4. AppKit.framework/Headers/NSWorkspace.h:35–43 (default handler and async callback)
L5. Carbon.framework/Frameworks/HIToolbox.framework/Headers/CarbonEvents.h:15428–15491
L6. CoreGraphics.framework/Headers/CGWindow.h:294–298

Source timestamps describe when the planning checks occurred. Recheck API/deployment and release
requirements against the toolchain actually selected for implementation. Do not inherit an old
verification result as proof of a future release's behaviour.
