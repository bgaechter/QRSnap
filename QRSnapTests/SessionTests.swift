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

@MainActor final class SessionTests: XCTestCase {
    func testBusyActivationAndCancelledCompletions() throws {
        var state = SessionLifecycle()
        let old = try XCTUnwrap(state.begin())
        XCTAssertNil(state.begin())
        XCTAssertTrue(state.advance(old, from: .selecting, to: .capturing))
        XCTAssertTrue(state.finish(old))
        let fresh = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.advance(old, from: .capturing, to: .decoding))
        XCTAssertFalse(state.finish(old))
        XCTAssertTrue(state.contains(fresh))
    }
    func testOpeningGateCanOnlyBeClaimedOnce() throws {
        var state = SessionLifecycle()
        let token = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.advance(token, from: .selecting, to: .opening))
        XCTAssertTrue(state.advance(token, from: .selecting, to: .capturing))
        XCTAssertTrue(state.advance(token, from: .capturing, to: .decoding))
        XCTAssertTrue(state.advance(token, from: .decoding, to: .reviewing))
        XCTAssertTrue(state.advance(token, from: .reviewing, to: .opening))
        XCTAssertFalse(state.advance(token, from: .reviewing, to: .opening))
        XCTAssertTrue(state.finish(token))
    }
    func testTimeoutInvalidatesEveryInFlightPhase() throws {
        for limit in 0...3 {
            var state = SessionLifecycle()
            let token = try XCTUnwrap(state.begin())
            let transitions: [(SessionLifecycle.Phase, SessionLifecycle.Phase)] = [(.selecting, .capturing), (.capturing, .decoding), (.decoding, .reviewing)]
            for (a, b) in transitions.prefix(limit) { XCTAssertTrue(state.advance(token, from: a, to: b)) }
            state.finish(token)
            XCTAssertFalse(state.contains(token))
            XCTAssertFalse(state.advance(token, from: .reviewing, to: .opening))
            XCTAssertEqual(state.phase, .idle)
        }
    }
}
