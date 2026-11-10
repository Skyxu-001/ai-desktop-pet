import XCTest
@testable import PetCore

final class PlayfulWorldTests: XCTestCase {
    func testDragMotionDoesNotFlushRecentCompletedActions() throws {
        var world = PetWorld()
        try world.submit(plan: PetPlan(intent: "热身", steps: [.init(verb: .hop, target: .pet), .init(verb: .spin, target: .pet), .init(verb: .bow, target: .pet)]), revision: 0)
        world.advance(seconds: 30)
        for index in 0..<30 { world.move(target: .ball, to: Double(index) / 30) }
        XCTAssertTrue(world.snapshot.recentEvents.contains("hop pet"))
        XCTAssertTrue(world.snapshot.recentEvents.contains("spin pet"))
        XCTAssertTrue(world.snapshot.recentEvents.contains("bow pet"))
        XCTAssertEqual(world.snapshot.recentEvents.filter { $0 == "moved ball" }.count, 1)
    }
    func testRestArrivesHomeBeforeSettlingDown() throws {
        var world = PetWorld()
        try world.submit(plan: PetPlan(intent: "回窝休息", steps: [PetStep(verb: .rest, target: .home)]), revision: 0)
        world.advance(seconds: 1.5)
        XCTAssertEqual(world.snapshot.petX, 0.1, accuracy: 0.0001)
        XCTAssertNotNil(world.currentPlan)
    }
    func testDigReachesBoxBeforePawing() throws {
        var world = PetWorld()
        try world.submit(plan: PetPlan(intent: "刨纸箱", steps: [PetStep(verb: .dig, target: .box)]), revision: 0)
        world.advance(seconds: 2)
        XCTAssertEqual(world.snapshot.petX, world.snapshot.boxX, accuracy: 0.0001)
        world.advance(seconds: 1)
        XCTAssertEqual(world.snapshot.petX, world.snapshot.boxX, accuracy: 0.0001)
        XCTAssertNotNil(world.currentPlan)
    }
    func testNewGesturesAreExecutableAndDigApproachesBox() throws {
        let spin = try XCTUnwrap(ActionVerb(rawValue: "spin"))
        let bow = try XCTUnwrap(ActionVerb(rawValue: "bow"))
        let dig = try XCTUnwrap(ActionVerb(rawValue: "dig"))
        var world = PetWorld()
        try world.submit(plan: PetPlan(intent: "纸箱探险", steps: [
            PetStep(verb: spin, target: .pet), PetStep(verb: bow, target: .pet),
            PetStep(verb: dig, target: .box)
        ]), revision: 0)
        world.advance(seconds: 30)
        XCTAssertNil(world.currentPlan)
        XCTAssertEqual(world.snapshot.petX, world.snapshot.boxX)
        XCTAssertEqual(world.snapshot.recentEvents.suffix(3), ["spin pet", "bow pet", "dig box"])
    }

    func testGesturesRejectWrongTargetsAtomically() throws {
        for name in ["spin", "bow", "dig"] {
            let verb = try XCTUnwrap(ActionVerb(rawValue: name))
            var world = PetWorld()
            let previous = world.snapshot
            XCTAssertThrowsError(try world.submit(plan: PetPlan(intent: "错误动作", steps: [PetStep(verb: verb, target: .ball)]), revision: 0))
            XCTAssertEqual(world.snapshot, previous)
            XCTAssertNil(world.currentPlan)
        }
    }
}
