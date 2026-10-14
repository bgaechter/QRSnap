// swift-tools-version: 6.0
import PackageDescription

// CLI validation of the shared sources; the Xcode app compiles these in one target.
let package = Package(
    name: "QRSnap",
    platforms: [.macOS(.v14)],
    products: [.library(name: "QRSnapCore", targets: ["QRSnapCore"])],
    targets: [
        .target(name: "QRSnapCore", path: "QRSnap",
                exclude: ["App", "Capture", "Selection/SelectionOverlay.swift"],
                sources: ["Scan", "Selection/GeometryAdapter.swift", "Selection/G0MarkerEvidence.swift", "Routing", "Decode"]),
        .testTarget(name: "QRSnapCoreTests", dependencies: ["QRSnapCore"],
                    path: "QRSnapTests", exclude: ["Support"], resources: [.copy("Fixtures")])
    ]
)
