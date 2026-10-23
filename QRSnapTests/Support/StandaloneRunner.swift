#if STANDALONE_TESTS
import Foundation

// Small CLT-only runner for the identical assertions used by the XCTest target.
// No compatibility claim is made for XCTest execution on this machine.
@MainActor class XCTestCase {}
@MainActor enum TestResults { static var failures = 0; static var count = 0 }
struct TestFailure: Error {}
// Write test names and assertions directly so a native trap cannot hide the
// active test behind stdio buffering when CI pipes the runner into a log.
@MainActor private func testLog(_ message: String) {
    FileHandle.standardOutput.write(Data("\(message)\n".utf8))
}
@MainActor func XCTFail(_ message: String = "Failure", file: StaticString = #filePath, line: UInt = #line) {
    TestResults.failures += 1
    testLog("FAIL \(file):\(line) \(message)")
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
        testLog("RUN \(name)")
        do { try await body() } catch { XCTFail("\(name) threw \(error)") }
        testLog("\(before == TestResults.failures ? "PASS" : "FAIL") \(name)")
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
        let dispatch = PayloadDispatcherTests()
        await run("dispatch.testWebPreparationHasNoSideEffectsAndDispatchOpensOnce", dispatch.testWebPreparationHasNoSideEffectsAndDispatchOpensOnce)
        await run("dispatch.testRegisteredSchemesRequireExplicitConfirmation", dispatch.testRegisteredSchemesRequireExplicitConfirmation)
        await run("dispatch.testChangedHandlerRequiresNewConfirmationAndMissingHandlerRetainsText", dispatch.testChangedHandlerRequiresNewConfirmationAndMissingHandlerRetainsText)
        await run("dispatch.testUnknownSchemesAndMalformedURLsOpenOriginalText", dispatch.testUnknownSchemesAndMalformedURLsOpenOriginalText)
        await run("dispatch.testBlockedSchemesOnlyOpenAsTextAfterExplicitAction", dispatch.testBlockedSchemesOnlyOpenAsTextAfterExplicitAction)
        await run("dispatch.testUnicodeWhitespaceAndEmptyTextArePreserved", dispatch.testUnicodeWhitespaceAndEmptyTextArePreserved)
        await run("dispatch.testStorageAndLaunchFailuresRetainOriginalAndWrittenDocument", dispatch.testStorageAndLaunchFailuresRetainOriginalAndWrittenDocument)
        await run("dispatch.testMissingWebAndTextHandlersRetainOriginalWithoutLaunching", dispatch.testMissingWebAndTextHandlersRetainOriginalWithoutLaunching)
        await run("dispatch.testCancellationBeforePreparationAndDispatchHasNoSideEffects", dispatch.testCancellationBeforePreparationAndDispatchHasNoSideEffects)
        await run("dispatch.testCancellationAfterStorageOrHandlerLookupPreventsLaunch", dispatch.testCancellationAfterStorageOrHandlerLookupPreventsLaunch)
        await run("dispatch.testPendingOpenRejectsDuplicateAndLateCompletionIsCancelled", dispatch.testPendingOpenRejectsDuplicateAndLateCompletionIsCancelled)
        await run("dispatch.testTaskCancellationPreventsDispatchEvenWithCurrentPredicate", dispatch.testTaskCancellationPreventsDispatchEvenWithCurrentPredicate)
        await run("dispatch.testUnsupportedAndForeignPreparedPayloadsNeverDispatch", dispatch.testUnsupportedAndForeignPreparedPayloadsNeverDispatch)
        let coordinator = ScanCoordinatorTests()
        await run("coordinator.testBusyInvocationAndSelectionIdentityAreGuarded", coordinator.testBusyInvocationAndSelectionIdentityAreGuarded)
        await run("coordinator.testCancellationDiscardsLateCaptureAndKeepsNewSession", coordinator.testCancellationDiscardsLateCaptureAndKeepsNewSession)
        await run("coordinator.testCancelledDecodeCannotReplaceNewSessionResults", coordinator.testCancelledDecodeCannotReplaceNewSessionResults)
        await run("coordinator.testTimeoutDuringCaptureDiscardsLateCompletionAndAllowsRetry", coordinator.testTimeoutDuringCaptureDiscardsLateCompletionAndAllowsRetry)
        await run("coordinator.testTimeoutDuringDecodeDiscardsLateResults", coordinator.testTimeoutDuringDecodeDiscardsLateResults)
        await run("coordinator.testProgressIsDelayedAndReviewingStopsDeadline", coordinator.testProgressIsDelayedAndReviewingStopsDeadline)
        await run("coordinator.testNoQRAndErrorsCleanUpAndPermitAnotherScan", coordinator.testNoQRAndErrorsCleanUpAndPermitAnotherScan)
        await run("coordinator.testDisplayChangeCancelsSelectionCaptureDecodeAndReview", coordinator.testDisplayChangeCancelsSelectionCaptureDecodeAndReview)
        await run("coordinator.testSingleAndMultipleResultsPreserveObservationsAndOpeningIsOnceOnly", coordinator.testSingleAndMultipleResultsPreserveObservationsAndOpeningIsOnceOnly)
        await run("coordinator.testEventReentrancyCannotPublishCancelledResultsOrInvalidateRetry", coordinator.testEventReentrancyCannotPublishCancelledResultsOrInvalidateRetry)
        let workflow = ScanWorkflowTests()
        await run("workflow.testSingleWebAndUnicodeTextCompleteThroughBothComponents", workflow.testSingleWebAndUnicodeTextCompleteThroughBothComponents)
        await run("workflow.testMultipleObservationsPreserveDuplicatesAndLockTheChoice", workflow.testMultipleObservationsPreserveDuplicatesAndLockTheChoice)
        await run("workflow.testHandlerChangeRequiresNewConfirmationAndRejectsOldRequest", workflow.testHandlerChangeRequiresNewConfirmationAndRejectsOldRequest)
        await run("workflow.testBlockedAndExternalRequestsOpenOriginalOnlyAsExplicitText", workflow.testBlockedAndExternalRequestsOpenOriginalOnlyAsExplicitText)
        await run("workflow.testNoObservationAndSelectedNilPayloadHaveDistinctFailures", workflow.testNoObservationAndSelectedNilPayloadHaveDistinctFailures)
        await run("workflow.testFailuresRetainExactPayloadAndCreatedDocument", workflow.testFailuresRetainExactPayloadAndCreatedDocument)
        await run("workflow.testUnknownSchemeUsesTextFallbackThroughWorkflow", workflow.testUnknownSchemeUsesTextFallbackThroughWorkflow)
        await run("workflow.testCancellationDuringLookupOrStoragePreventsHandoff", workflow.testCancellationDuringLookupOrStoragePreventsHandoff)
        await run("workflow.testCancelledCaptureAndTimedOutDecodeCannotDispatchIntoNewSession", workflow.testCancelledCaptureAndTimedOutDecodeCannotDispatchIntoNewSession)
        await run("workflow.testPendingHandoffAndLateCompletionCannotFinishReplacementSession", workflow.testPendingHandoffAndLateCompletionCannotFinishReplacementSession)
        await run("workflow.testDisplayChangeInvalidatesConfirmationAndAllStaleActions", workflow.testDisplayChangeInvalidatesConfirmationAndAllStaleActions)
        await run("workflow.testReentrantChoiceConfirmationAndFinishHandlersPreserveNewSession", workflow.testReentrantChoiceConfirmationAndFinishHandlersPreserveNewSession)
        await run("workflow.testCancelledCallerCannotStrandChoiceOrStartConfirmedDispatch", workflow.testCancelledCallerCannotStrandChoiceOrStartConfirmedDispatch)
        let markers = G0MarkerEvidenceTests()
        await run("g0.markers-and-phase", markers.testKnownMarkerEdgesAndFramePhase)
        await run("g0.non-fixture", markers.testNonFixtureDoesNotClaimMarkerEvidence)
        let decoderCancellation = DecoderCancellationTests()
        await run("decoder.cancellation-before-decode", decoderCancellation.testAlreadyCancelledTaskNeverSchedulesWork)
        await run("decoder.cancellation-before-continuation", decoderCancellation.testCancelBeforeContinuationInstallationReleasesFrameAndResumesOnce)
        await run("decoder.queued-cancellation", decoderCancellation.testQueuedCancellationReleasesPixelsBeforeItsQueuePositionRuns)
        await run("decoder.request-creation-cancellation", decoderCancellation.testCancelDuringRequestCreationReleasesFrameAndPreventsPerform)
        await run("decoder.active-cancellation", decoderCancellation.testActiveCancellationReturnsBeforeWorkerAndDiscardsLateCompletion)
        await run("decoder.cancelled-backlog", decoderCancellation.testCancelledBacklogDoesNotRunRequestsAheadOfFreshDecode)
        await run("decoder.results-and-failure", decoderCancellation.testCompletionPreservesPixelsOrientationOrderAndTypedFailure)
        await run("decoder.completion-race", decoderCancellation.testConcurrentCancellationAndCompletionResumeOnlyOnce)
        if !CommandLine.arguments.contains("--core-only") {
            let decoder = DecoderFixtureTests()
            await run("vision.baseline", decoder.testSupportedBaselineAndNegativeImages)
            await run("vision.empty-unsupported", decoder.testEmptyAndUnsupportedObservationsRemainDistinct)
            await run("vision.characterization", decoder.testCharacterizationRecordsObservedCounts)
        }
        testLog("\(TestResults.count) tests, \(TestResults.failures) assertion failures")
        exit(TestResults.failures == 0 ? 0 : 1)
    }
}
#endif
