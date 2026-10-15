# A1 empty and unsupported QR fixture evidence — 15 October 2026

**The real-image empty/binary observation gap is covered on the tested host. G0 remains open.** This task changes fixture generation, fixture expectations and tests; it does not change production decoding, routing, App Sandbox, deployment target, permissions or the authorized runtime app.

PR #7 was already merged as `91198dca4a405c61fc6f495f28f02ce92ded3efc` when this task began. A read-only review found no blocking defect in its bounded feasibility tooling, and its final [hosted CI run](https://github.com/bgaechter/QRSnap/actions/runs/38643505628) was green. The diagnostic timeout limitation remains documented. This independent A1 work follows the plan's explicit allowance for core/fixture progress while the broader G0 matrix is incomplete.

## What was missing

`QRDecoder` already preserved Vision's optional `payloadStringValue`, but fixture expectations used `[String]` and could not represent a detected observation with nil text. The generator also accepted only String input. Expectations now use `[String?]`, distinguishing `[]` (no observation), `[null]` (one unsupported-text observation) and `[""]` (one empty-text observation). The generator accepts Data without changing the existing text fixtures.

| Committed synthetic image | Encoder input | Expected Vision/decoder result | Contract checked |
| --- | --- | --- | --- |
| `empty.png` | Zero bytes | One observation, empty string | Empty text remains `.plainText("")`. |
| `binary.png` | Hex `fffe80c000` | One observation, nil string | The observation survives decoding and classifies as `.unsupported`. |
| `mixed-text-binary.png` | Synthetic HTTPS text above the same binary code | Two observations, text then nil, distinct IDs | Unsupported observations are not dropped; reading order is preserved. |
| Existing `no-code.png` | Blank canvas | No observations | No QR remains distinct from an unsupported QR. |

The fixture manifest records exact synthetic input bytes. These are observations for these images and named environments, not a claim that every non-UTF-8 payload returns nil or that Vision can decode every QR.

## Fixture integrity

The test also checks each edge fixture's encoded bytes through `CIQRCodeDescriptor.errorCorrectedPayload`. Apple's SDK describes this as the error-corrected **codeword** sequence, including the encoded segment structure, rather than just the original message. A probe on this host found that Vision's optional `payloadData` matched those codewords; directly comparing that field with encoder input would be an invalid assertion.

The fixture-only helper accepts versions 1–9, byte mode, an eight-bit byte count, the exact declared bytes and a following terminator. It rejects other representations instead of trying to become a general decoder. The segment layout is consistent with [Project Nayuki's primary QR implementation](https://github.com/nayuki/QR-Code-generator/blob/master/python/qrcodegen.py) (`encode_segments` and `QrSegment.Mode.BYTE`); no dependency or encoder implementation was copied into the app. The SDK contract is documented by [Apple's QR descriptor API](https://developer.apple.com/documentation/coreimage/ciqrcodedescriptor/errorcorrectedpayload).

Raw-byte checks compare a multiset because Vision's enumeration order is unspecified; the production decoder's top-to-bottom ordering is checked separately with exact optional strings. No test opens an application, requests screen access or captures a display.

## Validation and outstanding gates

- Native Core Image generated all 20 committed images. The 17 existing PNG files were byte-for-byte unchanged; three new images were added.
- Full standalone suite: **45 methods, zero assertion failures**, including the new Vision/descriptor/classification method. [Test log](evidence/decoder-edge-tests.log).
- Generated project, shared scheme and plists: PASS. [Project log](evidence/decoder-edge-project.log). Fixtures are copied as one resource directory, so no individual project entries were required.
- [Source/fixture hashes and environment](evidence/decoder-edge-fixtures.json) identify the run: macOS 26.5.2 arm64, Swift 6.3.3, Command Line Tools. Local XCTest is NOT RUN because full Xcode is unavailable. Hosted PR validation is recorded separately when available.
- Production sources and entitlements are unchanged. The prior sandboxed runtime app and its grant were not rebuilt or touched.

G0/G2 still require the named external/1×/portrait/topology display configurations, macOS 14/Intel, remaining permission/layout cases, arbitrary Space transitions and Stage Manager. Production composition, measured timing/memory, accessibility and release acceptance remain open. See the [manual matrix](manual-tests.md) and [runtime record](screen-permission-runtime.md). This fixture result does not promote any of those runtime gates to PASS.
