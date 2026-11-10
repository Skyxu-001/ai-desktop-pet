import XCTest
import PetCore
@testable import PetModel

final class ModelAffordanceTests: XCTestCase, @unchecked Sendable {
    private enum TestFailure: Error { case expressionRefused }
    func testExpressionRefusalDoesNotDiscardValidatedActions() async throws {
        let result = try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
            if request.index == 2 { throw TestFailure.expressionRefused }
            return ModelDecision(action: request.index == 0 ? "hop" : "rest", drawing: .puppy, accent: .dots, mood: .happy)
        }
        XCTAssertEqual(result.plan.steps.count, 2)
        XCTAssertEqual(result.decisionCount, 3)
        XCTAssertEqual(Set(result.expressionFallbackFields ?? []), Set(["thought", "emoji"]))
        XCTAssertTrue(result.rawOutput.contains("expressionRefused"))
        XCTAssertEqual(result.expressionError, "expressionRefused")
        XCTAssertEqual(result.doodleSource, "composed")
    }
    func testExpressionCancellationIsNeverRecoveredAsFallback() async {
        do {
            _ = try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
                if request.index == 2 { throw CancellationError() }
                return ModelDecision(action: request.index == 0 ? "hop" : "rest")
            }
            XCTFail("Cancelled expression must cancel the whole activity")
        } catch is CancellationError {
        } catch { XCTFail("Unexpected error: \(error)") }
    }
    func testEveryOfferedActionIsExecutableWithoutBall() throws {
        var world = PetWorld()
        world.setBallPresent(false)
        try assertExecutableChoices(world)
    }
    func testEveryOfferedActionIsExecutableWhileHoldingBall() throws {
        var world = PetWorld()
        try world.submit(plan: PetPlan(intent: "拿起球", steps: [PetStep(verb: .carry, target: .ball)]), revision: world.snapshot.revision)
        world.advance(seconds: 10)
        try assertExecutableChoices(world)
    }
    func testFreshWorldDoesNotOfferPrematurePlacement() throws {
        try assertExecutableChoices(PetWorld())
    }
    func testRecentActualActionsPreventRepetitionEvenWhenThoughtVaries() {
        let snapshot = WorldSnapshot(
            recentEvents: ["look ball", "moved box", "look box", "petted"],
            completedActivities: ["今天的球像月亮"]
        )
        let choices = ModelPlanner.candidates(for: snapshot)
        XCTAssertFalse(choices.contains(.lookAtBall))
        XCTAssertFalse(choices.contains(.lookAtBox))
        XCTAssertTrue(choices.contains(.pushBall))
    }
    func testThoughtTextDoesNotPretendAnActionWasExecuted() {
        let snapshot = WorldSnapshot(completedActivities: ["看看我的球"])
        XCTAssertTrue(ModelPlanner.candidates(for: snapshot).contains(.lookAtBall))
    }
    func testSequentialPlanningSimulatesPickupBeforeOfferingPlacement() async throws {
        let result = try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
            XCTAssertEqual(request.snapshot.completedActivities, [], "Speculative actions must not invent completed activity memories")
            switch request.index {
            case 0:
                XCTAssertFalse(request.actions.contains("placeBallInBox"))
                XCTAssertFalse(request.actions.contains("stop"))
                return ModelDecision(action: "pickUpBall", thought: "给球找个纸箱车库", emoji: "🚗", drawing: .puppy, accent: .sparkle, mood: .happy, inputTokens: 100, outputTokens: 20)
            case 1:
                XCTAssertTrue(request.snapshot.heldBall)
                XCTAssertTrue(request.actions.contains("placeBallInBox"))
                XCTAssertFalse(request.actions.contains("pickUpBall"))
                return ModelDecision(action: "placeBallInBox", inputTokens: 80, outputTokens: 8)
            default:
                XCTAssertFalse(request.snapshot.heldBall)
                XCTAssertFalse(request.actions.contains("placeBallInBox"))
                XCTAssertTrue(request.actions.isEmpty)
                return ModelDecision(thought: "给球找个纸箱车库", emoji: "🚗", inputTokens: 80, outputTokens: 5)
            }
        }
        XCTAssertEqual(result.plan.steps, [PetStep(verb: .carry, target: .ball), PetStep(verb: .drop, target: .box)])
        XCTAssertEqual(result.plan.expression?.thought, "给球找个纸箱车库")
        XCTAssertEqual(result.plan.expression?.emoji, "🚗")
        XCTAssertEqual(result.decisionCount, 3)
        XCTAssertEqual(result.inputTokens, 260)
        XCTAssertEqual(result.outputTokens, 33)
        XCTAssertEqual(result.expressionFallbackFields, [])
        var world = PetWorld()
        try world.submit(plan: result.plan, revision: world.snapshot.revision)
        world.advance(seconds: 30)
        XCTAssertNil(world.currentPlan)
        XCTAssertEqual(world.snapshot.ballX, world.snapshot.boxX)
    }
    func testLaterInvalidActionRejectsEntireActivity() async throws {
        do {
            _ = try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
                ModelDecision(action: request.index == 0 ? "hop" : "placeBallInBox", thought: "跳一下试试", emoji: "✨", drawing: .puppy, accent: .sparkle, mood: .happy)
            }
            XCTFail("Invalid later decision must not become a successful one-step activity")
        } catch PlanningError.invalidAction {
        }
    }
    func testPlanningUsesTwoActionDecisionsAndOneExpressionCall() async throws {
        let result = try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
            XCTAssertLessThan(request.index, 3)
            if request.index == 2 {
                XCTAssertTrue(request.actions.isEmpty)
                return ModelDecision(thought: "转个圈再伸个懒腰", emoji: "🐶")
            }
            let choices = ["spinAround", "stretch"]
            for previous in choices.prefix(request.index) {
                XCTAssertFalse(request.actions.contains(previous))
            }
            return ModelDecision(action: choices[request.index], thought: "纸箱边的热身时间", emoji: "🐶", drawing: .puppy, accent: .sparkle, mood: .happy)
        }
        XCTAssertEqual(result.plan.steps, [PetStep(verb: .spin, target: .pet), PetStep(verb: .bow, target: .pet)])
        XCTAssertEqual(result.decisionCount, 3)
    }
    func testModelMayStopAfterARealContinuationDecision() async throws {
        let result = try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
            ModelDecision(action: request.index == 0 ? "rest" : "stop", thought: "把今天折成一个小盹", emoji: "💤", drawing: .puppy, accent: .sparkle, mood: .happy)
        }
        XCTAssertEqual(result.decisionCount, 3)
        XCTAssertEqual(result.plan.steps, [PetStep(verb: .rest, target: .home)])
    }
    func testCancelledPlanningNeverCallsModel() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ModelPlanner().generate(snapshot: WorldSnapshot()) { _ in
                XCTFail("Cancelled planning must not start model generation")
                return ModelDecision(action: "hop")
            }
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must be returned")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    func testExpressionRemovesControlsWithoutLosingEmojiOrComposedDoodle() async throws {
        let result = try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
            ModelDecision(
                action: request.index == 0 ? "hop" : "stop",
                thought: "\u{001B}\u{202E}" + String(repeating: "汪", count: 100),
                emoji: "abc🐕‍🦺✨🎾⭐️",
                drawing: .puppy, accent: .sparkle, mood: .happy
            )
        }
        let expression = try XCTUnwrap(result.plan.expression)
        XCTAssertLessThanOrEqual(expression.thought.count, 25)
        XCTAssertTrue(expression.thought.hasSuffix("…"))
        XCTAssertFalse(expression.thought.contains("\u{001B}"))
        XCTAssertFalse(expression.thought.contains("\u{202E}"))
        XCTAssertEqual(expression.emoji, "🐕‍🦺✨🎾")
        XCTAssertEqual(result.doodleSource, "composed")
        XCTAssertEqual(expression.doodle.split(separator: "\n").count, 3)
        XCTAssertEqual(result.expressionFallbackFields, [])
        XCTAssertEqual(Set(result.expressionAdjustedFields ?? []), Set(["thought", "emoji"]))
    }
    func testMissingExpressionHasExplicitFallbackMetadata() async throws {
        let result = try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
            ModelDecision(action: request.index == 0 ? "hop" : "stop", thought: "\n\t", emoji: "letters123")
        }
        let expression = try XCTUnwrap(result.plan.expression)
        XCTAssertFalse(expression.thought.isEmpty)
        XCTAssertEqual(expression.emoji, "🐾")
        XCTAssertFalse(expression.doodle.isEmpty)
        XCTAssertEqual(result.doodleSource, "fallback")
        XCTAssertEqual(Set(result.expressionFallbackFields ?? []), Set(["thought", "emoji", "doodle"]))
    }
    func testEnglishThoughtIsNotDisplayedAsOriginalChineseExpression() async throws {
        let result = try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
            ModelDecision(action: request.index == 0 ? "hop" : "stop", thought: "Tiny whirlwind: let the ball escape through", emoji: "🐾✨", drawing: .puppy, accent: .sparkle, mood: .happy)
        }
        XCTAssertEqual(result.plan.expression?.thought, "想给自己加一点弹力")
        XCTAssertEqual(result.expressionFallbackFields, ["thought"])
    }
    func testBallDrawingIsNotOfferedWhenBallIsAbsent() async throws {
        let result = try await ModelPlanner().generate(snapshot: WorldSnapshot(ballX: nil)) { request in
            if request.index == 0 {
                XCTAssertEqual(request.drawings.count, 3)
                XCTAssertFalse(request.drawings.contains(.ball))
                XCTAssertEqual(request.accents.count, 2)
                return ModelDecision(action: "hop", drawing: request.drawings[0], accent: request.accents[0], mood: request.moods[0])
            }
            if request.index == 1 { return ModelDecision(action: "rest") }
            return ModelDecision(thought: "跳完了就去毯子休息", emoji: "🐶")
        }
        XCTAssertEqual(result.doodleSource, "composed")
        XCTAssertFalse(result.plan.steps.contains { $0.target == .ball })
    }
    func testTaskCancellationDuringFailedExpressionDoesNotRescuePlan() async {
        let task = Task {
            try await ModelPlanner().generate(snapshot: WorldSnapshot()) { request in
                if request.index == 2 {
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw TestFailure.expressionRefused
                }
                return ModelDecision(action: request.index == 0 ? "hop" : "rest")
            }
        }
        do { _ = try await task.value; XCTFail("Must preserve task cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    private func assertExecutableChoices(_ world: PetWorld) throws {
        let choices = ModelPlanner.candidates(for: world.snapshot)
        XCTAssertGreaterThan(choices.count, 1)
        for choice in choices {
            var copy = world
            XCTAssertNoThrow(try copy.submit(plan: PetPlan(intent: "观察动作", steps: [choice.step]), revision: copy.snapshot.revision), "invalid choice \(choice)")
        }
    }
}
