import AppKit
import Foundation
import PetCore
import SpriteKit
import XCTest
import PetUI
@testable import DesktopPet

final class PetControllerTests: XCTestCase {
    func testBasicModeStillHasVisibleAutonomousActivity() async {
        await MainActor.run {
            let controller = PetController(modelEnabled: false, memoryURL: nil)
            controller.tick(now: ProcessInfo.processInfo.systemUptime + 30)
            XCTAssertNotNil(controller.world.currentPlan)
            controller.shutdown()
        }
    }
    func testHeldDragPreventsModelRequestAfterReactionWindow() async {
        await MainActor.run {
            let controller = PetController(modelEnabled: true, memoryURL: nil)
            controller.interact(.dragBegan)
            controller.interact(.move(.ball, 0.7))
            controller.tick(now: ProcessInfo.processInfo.systemUptime + 100)
            XCTAssertEqual(controller.requests, 0)
            controller.shutdown()
        }
    }

    func testDragEndAllowsNewRequestAfterReactionWindow() async {
        await MainActor.run {
            let controller = PetController(modelEnabled: true, memoryURL: nil)
            controller.interact(.dragBegan)
            controller.interact(.move(.ball, 0.7))
            let now = ProcessInfo.processInfo.systemUptime
            controller.tick(now: now + 100)
            XCTAssertEqual(controller.requests, 0)
            controller.interact(.dragEnded)
            controller.tick(now: now + 101)
            XCTAssertEqual(controller.requests, 1)
            controller.shutdown()
        }
    }

    func testHidingInterruptsActivityWithoutChangingPauseStateOrWritingResumed() async {
        await MainActor.run {
            let controller = PetController(modelEnabled: false, memoryURL: nil)
            controller.interact(.pet)
            XCTAssertNotNil(controller.world.currentPlan)
            let previousRevision = controller.world.snapshot.revision

            controller.setHidden(true)

            XCTAssertTrue(controller.hidden)
            XCTAssertFalse(controller.world.isPaused)
            XCTAssertNil(controller.world.currentPlan)
            XCTAssertGreaterThan(controller.world.snapshot.revision, previousRevision)
            XCTAssertEqual(controller.world.snapshot.recentEvents.last, "hidden")
            XCTAssertFalse(controller.world.snapshot.recentEvents.contains("resumed"))
            controller.shutdown()
        }
    }

    func testHidingAnAlreadyPausedPetDoesNotDuplicatePausedEvent() async {
        await MainActor.run {
            let controller = PetController(modelEnabled: false, memoryURL: nil)
            controller.interact(.togglePaused)
            controller.setHidden(true)

            XCTAssertTrue(controller.world.isPaused)
            XCTAssertEqual(controller.world.snapshot.recentEvents.last, "hidden")
            XCTAssertEqual(controller.world.snapshot.recentEvents.filter { $0 == "paused" }.count, 1)
            controller.shutdown()
        }
    }

    func testMouseUpCommitsFinalDraggedBallPositionAndEndsDrag() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
            view.presentScene(scene)
            scene.render(snapshot: WorldSnapshot(), step: nil, progress: 0,
                         intent: "", mode: .basic, time: 0)
            var interactions: [PetInteraction] = []
            scene.onInteract = { interactions.append($0) }

            func event(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 80),
                                   modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }

            scene.mouseDown(with: event(.leftMouseDown, x: 76 + 358 * 0.55))
            scene.mouseDragged(with: event(.leftMouseDragged, x: 400))
            scene.mouseUp(with: event(.leftMouseUp, x: 400))

            XCTAssertEqual(interactions.count, 5)
            if interactions.count == 5 {
                if case .dragBegan = interactions[0] {} else { XCTFail("missing drag begin") }
                if case .move(.ball, let x) = interactions[3] {
                    XCTAssertEqual(x, 324.0 / 358.0, accuracy: 0.0001)
                } else { XCTFail("missing final ball move") }
                if case .dragEnded = interactions[4] {} else { XCTFail("missing drag end") }
            }
        }
    }

    func testMouseDownOnBallInterruptsExistingActivityBeforeAnyDragMotion() async {
        await MainActor.run {
            let controller = PetController(modelEnabled: false, memoryURL: nil)
            controller.interact(.pet)
            XCTAssertNotNil(controller.world.currentPlan)
            let revision = controller.world.snapshot.revision

            let scene = PetScene()
            let view = SKView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
            view.presentScene(scene)
            scene.render(snapshot: controller.world.snapshot, step: nil, progress: 0,
                         intent: "", mode: .basic, time: 0)
            scene.onInteract = { controller.interact($0) }
            let down = NSEvent.mouseEvent(with: .leftMouseDown,
                                         location: NSPoint(x: 76 + 358 * 0.55, y: 80),
                                         modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            scene.mouseDown(with: down)

            XCTAssertNil(controller.world.currentPlan)
            XCTAssertGreaterThan(controller.world.snapshot.revision, revision)
            let now = ProcessInfo.processInfo.systemUptime
            for index in 0..<20 { controller.tick(now: now + Double(index) * 0.2) }
            XCTAssertTrue(controller.world.snapshot.completedActivities.isEmpty)
            XCTAssertEqual(controller.world.snapshot.ballX ?? -1, 0.55, accuracy: 0.0001)
            scene.cancelInteraction()
            controller.shutdown()
        }
    }

    func testClickingBallEdgeWithoutDragDoesNotJumpToClickPoint() async {
        await MainActor.run {
            let controller = PetController(modelEnabled: false, memoryURL: nil)
            let scene = PetScene()
            let view = SKView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
            view.presentScene(scene)
            scene.render(snapshot: controller.world.snapshot, step: nil, progress: 0,
                         intent: "", mode: .basic, time: 0)
            scene.onInteract = { controller.interact($0) }
            let edgeX = 76 + 358 * 0.55 + 12
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: NSPoint(x: edgeX, y: 80),
                                   modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            scene.mouseDown(with: event(.leftMouseDown))
            scene.mouseUp(with: event(.leftMouseUp))

            XCTAssertEqual(controller.world.snapshot.ballX ?? -1, 0.55, accuracy: 0.0001)
            controller.shutdown()
        }
    }
}
