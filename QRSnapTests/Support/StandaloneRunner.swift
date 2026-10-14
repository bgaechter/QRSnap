#if STANDALONE_TESTS
import Foundation

// Small CLT-only runner for the identical assertions used by the XCTest target.
// No compatibility claim is made for XCTest execution on this machine.
@MainActor class XCTestCase {}
@MainActor enum TestResults { static var failures = 0; static var count = 0 }
struct TestFailure: Error {}
@MainActor func XCTFail(_ message: String = "Failure", file: StaticString = #filePath, line: UInt = #line) {
    TestResults.failures += 1
    print("FAIL \(file):\(line) \(message)")
}
@MainActor private func expect(_ condition: () throws -> Bool, _ message: String, file: StaticString, line: UInt) {
    do { if try !condition() { XCTFail(message, file: file, line: line) } }
    catch { XCTFail("Assertion threw: \(error)", file: file, line: line) }
}
@MainActor func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "Expected true", file: StaticString = #filePath, line: UInt = #line) {
    expect({ try value() }, message, file: file, line: line)
}
@MainActor func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "Expected false", file: StaticString = #filePath, line: UInt = #line) {
    expect({ try !value() }, message, file: file, line: line)
}
@MainActor func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "Values differ", file: StaticString = #filePath, line: UInt = #line) {
    expect({ try a() == b() }, message, file: file, line: line)
}
@MainActor func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "Values should differ", file: StaticString = #filePath, line: UInt = #line) {
    expect({ try a() != b() }, message, file: file, line: line)
}
@MainActor func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    expect({ try value() == nil }, "Expected nil", file: file, line: line)
}
@MainActor func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    expect({ try value() != nil }, "Unexpected nil", file: file, line: line)
}
@MainActor func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let unwrapped = try value() else { XCTFail("Unexpected nil", file: file, line: line); throw TestFailure() }
    return unwrapped
}
@MainActor func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    do { _ = try value(); XCTFail("Expected error", file: file, line: line) } catch { handler(error) }
}

@main struct StandaloneTests {
    @MainActor static func run(_ name: String, _ body: () async throws -> Void) async {
        let before = TestResults.failures
        TestResults.count += 1
        do { try await body() } catch { XCTFail("\(name) threw \(error)") }
        print("\(before == TestResults.failures ? "PASS" : "FAIL") \(name)")
    }
    @MainActor static func main() async {
        let routing = RoutingTests(), geometry = GeometryTests(), session = SessionTests(), storage = TextDocumentStoreTests()
        await run("routing.web", routing.testWebURLsPreserveEscapesAndTrimOnlyRoutingCandidate)
        await run("routing.text", routing.testTextIsNeverGuessedOrMutated)
        await run("routing.malformed", routing.testMalformedWebDestinationsRemainText)
        await run("routing.blocked", routing.testBlockedSchemesCannotBecomeLaunches)
        await run("routing.custom", routing.testCustomSchemesOnlyBecomeCandidates)
        await run("routing.nil-and-limit", routing.testNilEmptyAndResourceGuardAreDistinct)
        await run("geometry.directions", geometry.testAllDragDirectionsUseTheSameLocalRectangle)
        await run("geometry.portrait-shift", geometry.testShiftedPortraitDisplayClipsLocally)
        await run("geometry.click-small", geometry.testClickCancelsAndSmallSelectionIsTypedFailure)
        await run("geometry.rounding", geometry.testOutwardPixelRoundingAtDifferentScales)
        await run("geometry.limits", geometry.testInvalidInputsAndMemoryLimit)
        await run("geometry.order", geometry.testReadingOrderUsesTopLeftAndRetainsPhysicalDuplicates)
        await run("session.stale", session.testBusyActivationAndCancelledCompletions)
        await run("session.once", session.testOpeningGateCanOnlyBeClaimedOnce)
        await run("session.timeout", session.testTimeoutInvalidatesEveryInFlightPhase)
        await run("storage.bytes-permissions-retention", storage.testUniquePrivateDocumentsPreserveExactUTF8AndRemainOnDisk)
        await run("storage.failure", storage.testWriteFailureIsTypedAndDoesNotOverwriteExistingFile)
        if !CommandLine.arguments.contains("--core-only") {
            let decoder = DecoderFixtureTests()
            await run("vision.baseline", decoder.testSupportedBaselineAndNegativeImages)
            await run("vision.characterization", decoder.testCharacterizationRecordsObservedCounts)
        }
        print("\(TestResults.count) tests, \(TestResults.failures) assertion failures")
        exit(TestResults.failures == 0 ? 0 : 1)
    }
}
#endif
