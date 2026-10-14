#if !STANDALONE_TESTS
import XCTest
#endif
#if STANDALONE_TESTS
import Foundation
#elseif SWIFT_PACKAGE
@testable import QRSnapCore
#else
@testable import QRSnap
#endif

@MainActor final class RoutingTests: XCTestCase {
    func testWebURLsPreserveEscapesAndTrimOnlyRoutingCandidate() {
        for value in ["https://example.com/a%2Fb?q=x%20y#z", "HTTP://example.com/", "https://[::1]/", "https://localhost:8080/"] {
            guard case .webURL(let url) = PayloadClassifier.classify(" \n" + value + "\t ") else {
                return XCTFail("Expected valid synthetic URL")
            }
            XCTAssertEqual(url.absoluteString, value)
        }
    }
    func testTextIsNeverGuessedOrMutated() {
        for value in ["", "  \nGrüezi 🐱\r\n  ", "www.example.com", "WIFI:T:WPA;S:test;P:synthetic;;", "BEGIN:VCARD\nEND:VCARD"] {
            XCTAssertEqual(PayloadClassifier.classify(value), .plainText(value))
        }
    }
    func testMalformedWebDestinationsRemainText() {
        for value in ["https:", "https:/example.com", "https:///path", "https://", "https://a..com", "https://-bad.com", "https://a_b.com", "https://999.1.2.3", "https://example.com:99999", "https://example.com/a b", "https://example.com/\u{0}", "https://example.com/%zz", "https://exa%mple.com", "https://example.com\nattacker", "https://[bad]/"] {
            XCTAssertEqual(PayloadClassifier.classify(value), .plainText(value), "Malformed destination was routed: \(value.debugDescription)")
        }
    }
    func testBlockedSchemesCannotBecomeLaunches() {
        for value in ["file:///tmp/test.txt", "file:///tmp/with spaces.txt", "JAVASCRIPT:alert(1)", "data:text/plain,synthetic"] {
            XCTAssertEqual(PayloadClassifier.classify(value), .blockedText(value))
        }
    }
    func testCustomSchemesOnlyBecomeCandidates() {
        for value in ["mailto:qr@example.com", "tel:+123456789", "qrsnap-test://example/action", "unknown:synthetic"] {
            guard case .externalCandidate(let url) = PayloadClassifier.classify(value) else { return XCTFail("Expected candidate") }
            XCTAssertEqual(url.absoluteString, value)
        }
    }
    func testNilEmptyAndResourceGuardAreDistinct() {
        XCTAssertEqual(PayloadClassifier.classify(nil), .unsupported)
        XCTAssertEqual(PayloadClassifier.classify(""), .plainText(""))
        XCTAssertEqual(PayloadClassifier.classify(String(repeating: "🐱", count: 16385)), .unsupported)
        let boundary = String(repeating: "a", count: 65536)
        XCTAssertEqual(PayloadClassifier.classify(boundary), .plainText(boundary))
    }
}
