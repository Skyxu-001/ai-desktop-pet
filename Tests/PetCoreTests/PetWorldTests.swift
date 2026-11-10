import XCTest
@testable import PetCore

final class PetWorldTests: XCTestCase {
    private func plan(_ intent: String = "play", _ steps: PetStep...) -> PetPlan {
        PetPlan(intent: intent, steps: steps)
    }

    private func step(_ verb: ActionVerb, _ target: TargetID) -> PetStep {
        PetStep(verb: verb, target: target)
    }

    func testMissingBallRejectsCarryWithoutChangingWorld() throws {
        var world = PetWorld()
        world.setBallPresent(false)
        let before = world.snapshot

        XCTAssertThrowsError(try world.submit(plan: plan("play", step(.carry, .ball)), revision: before.revision))
        XCTAssertEqual(world.snapshot, before)
        XCTAssertNil(world.currentPlan)
    }

    func testDropWithoutPriorCarryRejectsWholePlan() throws {
        var world = PetWorld()
        let before = world.snapshot

        XCTAssertThrowsError(try world.submit(
            plan: plan("play", step(.approach, .ball), step(.drop, .box)),
            revision: before.revision
        ))
        XCTAssertEqual(world.snapshot, before)
        XCTAssertNil(world.currentStep)
    }

    func testLaterInvalidStepCannotExecuteEarlierStep() throws {
        var world = PetWorld()
        let before = world.snapshot

        XCTAssertThrowsError(try world.submit(
            plan: plan("play", step(.push, .ball), step(.hop, .box)),
            revision: before.revision
        ))
        world.advance(seconds: 100)
        XCTAssertEqual(world.snapshot, before)
    }

    func testStaleRevisionAfterMoveRemovePetPauseAndReset() throws {
        let interventions: [(inout PetWorld) -> Void] = [
            { $0.move(target: .box, to: 0.4) },
            { $0.setBallPresent(false) },
            { $0.pet() },
            { $0.setPaused(true) },
            { $0.reset() }
        ]
        for intervene in interventions {
            var world = PetWorld()
            let oldRevision = world.snapshot.revision
            intervene(&world)
            XCTAssertGreaterThan(world.snapshot.revision, oldRevision)
            XCTAssertThrowsError(try world.submit(
                plan: plan("play", step(.hop, .pet)), revision: oldRevision
            ))
            XCTAssertNil(world.currentPlan)
        }
    }

    func testHidingInterruptsPlanAndRecordsOnlyAHiddenEvent() throws {
        var world = PetWorld()
        try world.submit(plan: plan("play", step(.hop, .pet)), revision: world.snapshot.revision)
        let revision = world.snapshot.revision

        world.interruptForHiding()

        XCTAssertNil(world.currentPlan)
        XCTAssertFalse(world.isPaused)
        XCTAssertGreaterThan(world.snapshot.revision, revision)
        XCTAssertEqual(world.snapshot.recentEvents.last, "hidden")
        XCTAssertTrue(world.snapshot.completedActivities.isEmpty)
    }

    func testMoveCancelsPartialActionWithoutRecordingCompletion() throws {
        var world = PetWorld()
        try world.submit(plan: plan("play", step(.carry, .ball)), revision: world.snapshot.revision)
        world.advance(seconds: 0.5)
        XCTAssertGreaterThan(world.stepProgress, 0)

        world.move(target: .box, to: 0.6)
        world.advance(seconds: 100)

        XCTAssertNil(world.currentPlan)
        XCTAssertFalse(world.snapshot.heldBall)
        XCTAssertTrue(world.snapshot.completedActivities.isEmpty)
        XCTAssertFalse(world.snapshot.recentEvents.contains { $0.contains("carry") })
    }

    func testPauseFreezesAndCancelsCurrentAction() throws {
        var world = PetWorld()
        try world.submit(plan: plan("play", step(.approach, .ball)), revision: world.snapshot.revision)
        world.advance(seconds: 0.5)
        world.setPaused(true)
        let paused = world.snapshot

        world.advance(seconds: 100)
        XCTAssertEqual(world.snapshot, paused)
        XCTAssertNil(world.currentPlan)
        XCTAssertEqual(world.stepProgress, 0)
        XCTAssertTrue(world.isPaused)
    }

    func testNonFiniteMovementAndAdvanceCannotPoisonState() throws {
        var world = PetWorld()
        let before = world.snapshot
        world.move(target: .ball, to: .nan)
        world.move(target: .box, to: .infinity)
        XCTAssertEqual(world.snapshot, before)

        try world.submit(plan: plan("play", step(.approach, .ball)), revision: world.snapshot.revision)
        world.advance(seconds: .nan)
        world.advance(seconds: .infinity)
        world.advance(seconds: -1)
        XCTAssertEqual(world.stepProgress, 0)
        XCTAssertEqual(world.snapshot.petX, before.petX)
    }

    func testMovementClampsCoordinatesAndReleasesDraggedBall() throws {
        var world = PetWorld()
        world.move(target: .box, to: -3)
        XCTAssertEqual(world.snapshot.boxX, 0)
        world.move(target: .ball, to: 4)
        XCTAssertEqual(world.snapshot.ballX, 1)
        try world.submit(plan: plan("play", step(.carry, .ball)), revision: world.snapshot.revision)
        world.advance(seconds: 100)
        XCTAssertTrue(world.snapshot.heldBall)

        world.move(target: .ball, to: 0.3)
        XCTAssertFalse(world.snapshot.heldBall)
        XCTAssertEqual(world.snapshot.ballX, 0.3)
    }

    func testPushAtRightBoundaryStillRollsWithinBounds() throws {
        var world = PetWorld()
        world.move(target: .ball, to: 1)
        try world.submit(plan: plan("play", step(.push, .ball)), revision: world.snapshot.revision)
        world.advance(seconds: 10)
        XCTAssertLessThan(world.snapshot.ballX ?? -1, 1)
        XCTAssertGreaterThanOrEqual(world.snapshot.ballX ?? -1, 0)
    }

    func testPushApproachesBeforeRollingAndFollowsBallThroughCompletion() throws {
        var world = PetWorld()
        try world.submit(plan: plan("play", step(.push, .ball)), revision: world.snapshot.revision)

        world.advance(seconds: 0.5)
        XCTAssertEqual(world.snapshot.ballX ?? -1, 0.55, accuracy: 0.0001)
        XCTAssertGreaterThan(world.snapshot.petX, 0.25)
        XCTAssertLessThan(world.snapshot.petX, 0.55)

        world.advance(seconds: 1.3)
        XCTAssertGreaterThan(world.snapshot.ballX ?? -1, 0.55)
        XCTAssertLessThanOrEqual(abs(world.snapshot.petX - (world.snapshot.ballX ?? -1)), 0.06)

        world.advance(seconds: 10)
        XCTAssertNil(world.currentPlan)
        XCTAssertLessThanOrEqual(abs(world.snapshot.petX - (world.snapshot.ballX ?? -1)), 0.06)
    }

    func testBoundaryPushApproachesBeforeRollingLeftAndFollowsBall() throws {
        var world = PetWorld()
        world.move(target: .ball, to: 1)
        try world.submit(plan: plan("play", step(.push, .ball)), revision: world.snapshot.revision)

        world.advance(seconds: 0.5)
        XCTAssertEqual(world.snapshot.ballX ?? -1, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(world.snapshot.petX, 0.25)

        world.advance(seconds: 1.3)
        XCTAssertLessThan(world.snapshot.ballX ?? -1, 1)
        XCTAssertLessThanOrEqual(abs(world.snapshot.petX - (world.snapshot.ballX ?? -1)), 0.06)

        world.advance(seconds: 10)
        XCTAssertEqual(world.snapshot.ballX ?? -1, 0.85, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(abs(world.snapshot.petX - (world.snapshot.ballX ?? -1)), 0.06)
    }

    func testCarryThenDropMovesBallToBoxAndRecordsFinishedActivity() throws {
        var world = PetWorld()
        try world.submit(
            plan: plan("deliver", step(.carry, .ball), step(.drop, .box)),
            revision: world.snapshot.revision
        )
        world.advance(seconds: 100)

        XCTAssertNil(world.currentPlan)
        XCTAssertFalse(world.snapshot.heldBall)
        XCTAssertEqual(world.snapshot.petX, 0.8, accuracy: 0.0001)
        XCTAssertEqual(world.snapshot.ballX ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(world.snapshot.completedActivities, ["deliver"])
    }

    func testActivityOnlyAppearsAfterLastStepReallyFinishes() throws {
        var world = PetWorld()
        try world.submit(
            plan: plan("deliver", step(.carry, .ball), step(.drop, .box)),
            revision: world.snapshot.revision
        )
        world.advance(seconds: 3)
        XCTAssertTrue(world.snapshot.heldBall)
        XCTAssertTrue(world.snapshot.completedActivities.isEmpty)
        XCTAssertEqual(world.currentStep, step(.drop, .box))

        world.advance(seconds: 100)
        XCTAssertEqual(world.snapshot.completedActivities, ["deliver"])
    }

    func testBusyOrPausedSubmissionLeavesExistingStateUnchanged() throws {
        var world = PetWorld()
        try world.submit(plan: plan("play", step(.hop, .pet)), revision: world.snapshot.revision)
        let existingPlan = world.currentPlan
        XCTAssertThrowsError(try world.submit(plan: plan("play", step(.rest, .home)), revision: world.snapshot.revision))
        XCTAssertEqual(world.currentPlan, existingPlan)

        world.setPaused(true)
        let paused = world.snapshot
        XCTAssertThrowsError(try world.submit(plan: plan("play", step(.rest, .home)), revision: paused.revision))
        XCTAssertEqual(world.snapshot, paused)
    }

    func testPlanShapeAndTargetsAreValidated() throws {
        let invalid: [PetPlan] = [
            plan("", step(.hop, .pet)),
            plan(String(repeating: "x", count: 161), step(.hop, .pet)),
            plan(String(repeating: " ", count: 161) + "x", step(.hop, .pet)),
            plan("empty"),
            plan("long", step(.look, .pet), step(.look, .ball), step(.hop, .pet), step(.rest, .home)),
            plan("wrong", step(.push, .box)),
            plan("wrong", step(.carry, .pet)),
            plan("wrong", step(.drop, .ball)),
            plan("wrong", step(.hop, .home)),
            plan("wrong", step(.rest, .box))
        ]
        for candidate in invalid {
            var world = PetWorld()
            XCTAssertThrowsError(try world.submit(plan: candidate, revision: world.snapshot.revision))
            XCTAssertNil(world.currentPlan)
        }
    }

    func testHugeDeltaFinishesBoundedPlanAndIgnoresFurtherTicks() throws {
        var world = PetWorld()
        try world.submit(
            plan: plan("bounce", step(.hop, .pet), step(.look, .box), step(.rest, .home)),
            revision: world.snapshot.revision
        )
        let revision = world.snapshot.revision
        world.advance(seconds: .greatestFiniteMagnitude)
        XCTAssertNil(world.currentPlan)
        XCTAssertEqual(world.snapshot.completedActivities, ["bounce"])
        XCTAssertEqual(world.snapshot.revision, revision)
        let finished = world.snapshot
        world.advance(seconds: .greatestFiniteMagnitude)
        XCTAssertEqual(world.snapshot, finished)
    }

    func testSnapshotRevisionStaysStableDuringAnimation() throws {
        var world = PetWorld()
        let revision = world.snapshot.revision
        try world.submit(plan: plan("play", step(.approach, .ball)), revision: revision)
        world.advance(seconds: 0.5)
        XCTAssertGreaterThan(world.snapshot.petX, 0.25)
        XCTAssertEqual(world.snapshot.revision, revision)
    }

    func testEventAndActivityHistoryStayBounded() throws {
        var world = PetWorld()
        for index in 0..<20 {
            try world.submit(plan: plan("hop \(index)", step(.hop, .pet)), revision: world.snapshot.revision)
            world.advance(seconds: 10)
        }
        XCTAssertEqual(world.snapshot.completedActivities.count, 12)
        XCTAssertEqual(world.snapshot.completedActivities.first, "hop 8")
        XCTAssertLessThanOrEqual(world.snapshot.recentEvents.count, 8)
    }
}
