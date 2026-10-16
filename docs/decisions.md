# Implementation decisions — 14 October 2026

## A0 scope and naming

The current folder was empty except for the five planning documents and has no Git metadata. It is the isolated app workspace requested by the plan. Use **QRSnap** for the app/project instead of the illustrative `ScreenQR` name. Choose `local.benny.QRSnap` as the provisional local bundle identity; changing identity later requires fresh permission/signing tests. No unrelated files were present or modified.

A0 supplies an experimental selector/capture adapter, a local app bundle and explicit test actions. It is not the final A2/A3/A4 implementation. Automatic QR dispatch is intentionally absent from this proof; D5 remains the intended production behavior. The only external handoff action opens disclosed synthetic text after a button click. A1 pure logic and fixture work can continue independently under the plan's G0 exception.

## Build with available tools

Evidence: selected developer directory is Command Line Tools, no full Xcode app is installed, and `swift test` reports `no such module 'XCTest'`. The application itself compiles using Swift 6.3.3 against SDK 26.5 and an arm64 macOS 14 target.

Provide the requested one-app/one-test Xcode project, plus an Apple-only `swiftc` build script. Reuse the XCTest methods in a small standalone runner for this machine. This is a development-tool fallback, not a reduction in runtime acceptance requirements. The standalone test shim is confined to tests and excluded from the Xcode and SwiftPM targets.

The build uses a local ad-hoc signature with App Sandbox and Hardened Runtime enabled. No Developer ID identity, release archive, notarization, or installed app is claimed. Signing credentials were not accessed. Full Xcode execution and controlled signed runtime testing remain prerequisites for G0/G6.

## Coordinate convention is provisional

The selector uses a flipped AppKit view, so `convert(_:from:)` produces local top-left points directly. Global display origins are retained in the topology snapshot for change detection, never multiplied into capture coordinates. Pixel output uses outward rounding: floor minimum edges, ceil maximum edges, clamp to display pixel bounds, then divide by `filter.pointPixelScale` for `sourceRect`. Unit tests prove this arithmetic only. Real marker experiments must establish the AppKit/ScreenCaptureKit mapping before G0/G2 can pass.

The proof fails if it cannot identify itself for app exclusion. No delay or hide-and-wait workaround is added. The overlay remains visible during capture for the exclusion experiment.

## Separate classification from handler lookup

`PayloadClassification.externalCandidate` is unresolved until the OS boundary looks up a handler. It cannot by itself authorize a launch. `Route.confirmedExternalURI` carries handler metadata for the later explicit confirmation UI. `blockedText` keeps `file:`, `javascript:` and `data:` separate from automatically opened ordinary text; Wi-Fi strings remain text even if a matching handler happens to exist. Original decoded strings are retained separately from trimmed routing candidates.

## Test graphics access

The agent command sandbox prevented Core Image fixture rendering and caused Vision requests to fail. The same generator and compiled tests succeeded when run with macOS graphics-service access. Those commands used only synthetic images and temporary text files, with no screen capture, permission request or app handoff. This evidence applies to fixture decoding in the test process; it does not establish runtime behavior of the sandboxed application. The app's sandbox entitlement was retained unchanged.

## Explicit text export — 16 October 2026

A3 requires Copy/Save recovery after a text write or launch failure. The result window uses `NSSavePanel` with a generic `.txt` filename and writes the original UTF-8 value only after the user selects a destination. This adds `com.apple.security.files.user-selected.read-write` alongside `com.apple.security.app-sandbox`; it does not grant arbitrary filesystem access. CI now checks that exact two-key entitlement set. The installed SDK declares the save-panel APIs below the macOS 14 floor.

Each save completion is tied to a result-presentation identity, which remains valid after the scan session ends but is invalidated on dismissal or replacement. A cancelled/stale panel cannot write; write failure leaves the original text available for recovery. This capability is used by the explicit synthetic preview as well as the reusable result controller. The previous authorized screen-capture executable and its grant remain unchanged. Hosted controller tests are separate from the [signed sandbox Save/cancel check](result-windows.md#signed-preview-runtime), which passed on the named host. Native failure/stale-sheet, clipboard and broader accessibility checks remain open.
