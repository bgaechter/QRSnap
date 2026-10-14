import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Synthetic images only. Run from repository root. No screen APIs or app handoff.
let directory = URL(fileURLWithPath: "QRSnapTests/Fixtures", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let context = CIContext()
struct Fixture: Codable {
    let file: String
    let kind: String
    let payloads: [String]
}
var manifest: [Fixture] = []
func canvas(width: Int, height: Int) -> CGContext {
    let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
    c.interpolationQuality = .none
    return c
}
func qr(_ payload: String, scale: Int = 8, inverted: Bool = false) -> CGImage {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(Data(payload.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    var ci = filter.outputImage!
    if inverted { ci = ci.applyingFilter("CIColorInvert") }
    guard let base = context.createCGImage(ci, from: ci.extent) else {
        fatalError("Core Image could not render synthetic QR fixture; extent: \(ci.extent)")
    }
    let border = 4 * scale
    let width = base.width * scale + 2 * border
    let c = canvas(width: width, height: width)
    if inverted { c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: width, height: width)) }
    c.draw(base, in: CGRect(x: border, y: border, width: base.width * scale, height: base.height * scale))
    return c.makeImage()!
}
func write(_ name: String, _ image: CGImage, _ payloads: [String], kind: String = "baseline") {
    let url = directory.appendingPathComponent(name + ".png")
    let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, image, nil)
    precondition(CGImageDestinationFinalize(writer))
    manifest.append(Fixture(file: url.lastPathComponent, kind: kind, payloads: payloads))
}
let values: [(String, String)] = [
    ("https", "https://example.com/qr"), ("http", "http://example.com/"),
    ("unicode", "Grüezi · 日本語 · العربية · 🐱"), ("multiline", "First line\nSecond line\r\n  trailing spaces  \n"),
    ("escapes", "https://example.com/a%2Fb?q=hello%20world#part"),
    ("custom", "qrsnap-test://example/confirm?value=1"), ("mailto", "mailto:qr@example.com"),
    ("credentials-text", "Synthetic token: test-only-123\nNever a real secret"),
    ("wifi-text", "WIFI:T:WPA;S:Synthetic;P:test-only;;")
]
for (name, payload) in values { write(name, qr(payload), [payload]) }
let rotatedPayload = "https://example.com/rotated"
let base = qr(rotatedPayload)
let rotation = canvas(width: base.height, height: base.width)
rotation.translateBy(x: CGFloat(base.height), y: 0); rotation.rotate(by: .pi / 2)
rotation.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
write("rotated", rotation.makeImage()!, [rotatedPayload])
write("inverted", qr("https://example.com/inverted", inverted: true), ["https://example.com/inverted"])
let top = qr("https://example.com/top"), bottom = qr("https://example.com/bottom")
let multiple = canvas(width: max(top.width, bottom.width) + 100, height: top.height + bottom.height + 160)
multiple.draw(top, in: CGRect(x: 50, y: bottom.height + 110, width: top.width, height: top.height))
multiple.draw(bottom, in: CGRect(x: 50, y: 50, width: bottom.width, height: bottom.height))
write("multiple", multiple.makeImage()!, ["https://example.com/top", "https://example.com/bottom"])
write("no-code", canvas(width: 300, height: 240).makeImage()!, [], kind: "negative")
let clipped = base.cropping(to: CGRect(x: 0, y: 0, width: base.width / 3, height: base.height / 3))!
write("cropped", clipped, [], kind: "characterization")
let dense = String(repeating: "Dense synthetic payload 0123456789; ", count: 30)
write("dense", qr(dense, scale: 3), [dense], kind: "characterization")
write("small", qr("https://example.com/small", scale: 1), ["https://example.com/small"], kind: "characterization")
let damaged = canvas(width: base.width, height: base.height)
damaged.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
damaged.setFillColor(CGColor(gray: 1, alpha: 1))
damaged.fill(CGRect(x: base.width / 3, y: 0, width: base.width / 3, height: base.height))
write("damaged", damaged.makeImage()!, [], kind: "characterization")
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
print("Generated \(manifest.count) synthetic fixtures")
