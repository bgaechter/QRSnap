import Foundation
import Vision

public final class QRDecoder: QRDecoding, Sendable {
    private let queue = DispatchQueue(label: "QRSnap.vision", qos: .userInitiated)
    public init() {}

    public func decode(_ frame: CapturedFrame) async throws -> [DecodedItem] {
        try Task.checkCancellation()
        let result: [DecodedItem] = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let items = try autoreleasepool {
                        let request = VNDetectBarcodesRequest()
                        request.revision = VNDetectBarcodesRequestRevision4
                        request.symbologies = [.qr]
                        let handler = VNImageRequestHandler(cgImage: frame.image, orientation: frame.orientation)
                        try handler.perform([request])
                        return (request.results ?? []).enumerated().map {
                            DecodedItem(id: $0.offset, payload: $0.element.payloadStringValue,
                                        bounds: $0.element.boundingBox)
                        }
                    }
                    continuation.resume(returning: GeometryAdapter.readingOrder(items))
                } catch {
                    continuation.resume(throwing: ScanFailure.decodeFailed)
                }
            }
        }
        try Task.checkCancellation()
        return result
    }
}
