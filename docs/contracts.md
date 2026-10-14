# A0 shared contracts

These interfaces are fixed for the next milestone. Definitions live in `QRSnap/Scan/ScanModels.swift`; proposed pixel semantics remain subject to G0.

| Value / boundary | Contract |
| --- | --- |
| `DisplayGeometry` | Display ID, full global bottom-left point frame, backing scale. Topology snapshots are sorted by display ID and compared before/after capture. |
| `Selection` | Session UUID, selected display, topology snapshot and display-local top-left rectangle in logical points. |
| `CapturedFrame` | In-memory `CGImage`, explicit orientation and actual pixel dimensions. No persistence. `.up` is validated on synthetic PNGs; captured-screen orientation needs G0. |
| `DecodedItem` | Stable index within one decode, optional original string, normalized bottom-left Vision bounds. Nil text, empty text and zero observations are distinct. Duplicate payloads keep separate observations. |
| `PayloadClassification` | Pure web URL / external URI candidate / original plain text / blocked text / unsupported. No handler queries or launch side effects. |
| `Route` | Final web URL, confirmed external URI plus handler metadata, original plain/blocked text, or typed unsupported reason. |
| `ScreenCapturing` | Main actor, asynchronous one-shot capture; throws typed failure. |
| `QRDecoding` | Sendable asynchronous boundary; native decoder owns a request per serial-queue job and returns immutable observations. |
| `ScreenPermissionChecking` | Main actor preflight and explicit request. A request return is not a claim that capture succeeds. |
| `PayloadLaunching` | Main actor handler lookup and asynchronous handoff result. To be implemented/injected in A3/A4. |
| `TextDocumentStoring` | Create and retain a unique UTF-8 `.txt` document; file failures become `fileWriteFailed`. |
| `SessionLifecycle` | One active UUID, legal phase progression, invalidated on cancellation/timeout. Final opening transition can be claimed only once. This value is not a complete production coordinator. |

No image bytes, payloads, URLs, or window titles are logged by the application. Error values carry categories, not decoded data. UI preview limits do not mutate the `DecodedItem` payload. Production copy/save and handoff must use the original value.
