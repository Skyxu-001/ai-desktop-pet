import XCTest
@testable import PetRuntime

final class InferenceGateTests: XCTestCase {

func test_completedRequestUsesRevisionAndEnforcesCooldown() throws {
    var gate = InferenceGate()
    let request = try XCTUnwrap(gate.begin(now: 10, revision: 2))
    XCTAssertTrue(gate.begin(now: 11, revision: 2) == nil)
    XCTAssertTrue(gate.finish(request, currentRevision: 2, now: 13, succeeded: true))
    XCTAssertTrue(gate.begin(now: 21.9, revision: 2) == nil)
    XCTAssertTrue(gate.begin(now: 22, revision: 2) != nil)
}

func test_timeoutKeepsSlotUntilPhysicalCompletionAndRejectsLateResult() throws {
    var gate = InferenceGate()
    let request = try XCTUnwrap(gate.begin(now: 10, revision: 2))
    XCTAssertTrue(!gate.expire(now: 29.9))
    XCTAssertTrue(gate.expire(now: 30))
    XCTAssertTrue(!gate.expire(now: 31))
    XCTAssertTrue(gate.begin(now: 100, revision: 2) == nil)
    XCTAssertTrue(!gate.finish(request, currentRevision: 2, now: 100, succeeded: true))
    XCTAssertTrue(gate.begin(now: 129.9, revision: 2) == nil)
    XCTAssertTrue(gate.begin(now: 130, revision: 2) != nil)
}

func test_invalidationAndPauseRejectResultEvenWhenWorldRevisionIsUnchanged() throws {
    var gate = InferenceGate()
    let old = try XCTUnwrap(gate.begin(now: 0, revision: 1))
    gate.invalidate()
    XCTAssertTrue(!gate.finish(old, currentRevision: 1, now: 2, succeeded: true))
    gate.setSuspended(true)
    XCTAssertTrue(gate.begin(now: 100, revision: 1) == nil)
    gate.setSuspended(false)
    let resumed = try XCTUnwrap(gate.begin(now: 100, revision: 1))
    gate.setSuspended(true)
    gate.setSuspended(false)
    XCTAssertTrue(!gate.finish(resumed, currentRevision: 1, now: 105, succeeded: true))
}

func test_staleCompletionCannotFreeNewRequestSlot() throws {
    var gate = InferenceGate()
    let old = try XCTUnwrap(gate.begin(now: 0, revision: 1))
    XCTAssertTrue(!gate.finish(old, currentRevision: 2, now: 1, succeeded: true))
    let current = try XCTUnwrap(gate.begin(now: 40, revision: 2))
    XCTAssertTrue(!gate.finish(old, currentRevision: 2, now: 41, succeeded: true))
    XCTAssertTrue(gate.active == current)
    XCTAssertTrue(gate.finish(current, currentRevision: 2, now: 42, succeeded: true))
}

}
