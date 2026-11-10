import AppKit
import PetCore
import PetUI
import SpriteKit
import XCTest
@testable import DesktopPet

final class PetSceneLayoutTests: XCTestCase {
    func testDraggingFromBallEdgePreservesPointerOffset() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            scene.render(snapshot: WorldSnapshot(ballX: 0.65), step: nil, progress: 0,
                         intent: "", mode: .basic, time: 0)
            let laterCenter = scene.interactionPoint(for: .ball)!
            scene.render(snapshot: WorldSnapshot(ballX: 0.55), step: nil, progress: 0,
                         intent: "", mode: .basic, time: 0)
            let firstCenter = scene.interactionPoint(for: .ball)!
            var finalBallX: Double?
            scene.onInteract = {
                if case .move(.ball, let x) = $0 { finalBallX = x }
            }
            let start = CGPoint(x: firstCenter.x + 12, y: firstCenter.y)
            let end = CGPoint(x: laterCenter.x + 12, y: laterCenter.y)
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: start))
            scene.mouseDragged(with: Self.event(.leftMouseDragged, scene: scene, point: end))
            scene.mouseUp(with: Self.event(.leftMouseUp, scene: scene, point: end))
            XCTAssertEqual(finalBallX ?? -1, 0.65, accuracy: 0.0001)
        }
    }

    func testHeldBallCanBeTakenFromTheDogsMouth() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            scene.render(snapshot: WorldSnapshot(ballX: 0.25, heldBall: true),
                         step: nil, progress: 0, intent: "", mode: .basic, time: 0)
            let point = scene.interactionPoint(for: .ball)!
            var draggedBall = false
            var pettedDog = false
            scene.onInteract = {
                if case .move(.ball, _) = $0 { draggedBall = true }
                if case .pet = $0 { pettedDog = true }
            }
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: point))
            XCTAssertTrue(draggedBall)
            XCTAssertFalse(pettedDog)
            scene.cancelInteraction()
        }
    }

    func testHandleAndHideOnlyRouteTheirOwnControls() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            scene.render(snapshot: WorldSnapshot(), step: nil, progress: 0,
                         intent: "", mode: .basic, time: 0)
            var windowDrags = 0
            var hides = 0
            var interactions = 0
            scene.onWindowDrag = { _ in windowDrags += 1 }
            scene.onHide = { hides += 1 }
            scene.onInteract = { _ in interactions += 1 }
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: scene.windowHandlePoint))
            XCTAssertEqual(windowDrags, 1)
            XCTAssertEqual(interactions, 0)
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: scene.hidePoint))
            XCTAssertEqual(hides, 1)
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: scene.interactionPoint(for: .ball)!))
            XCTAssertEqual(windowDrags, 1)
            XCTAssertEqual(hides, 1)
            XCTAssertGreaterThan(interactions, 0)
            scene.cancelInteraction()
        }
    }

    func testBoxGripRemainsAccessibleWhenBallOverlapsIt() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            scene.render(snapshot: WorldSnapshot(ballX: 0.8, boxX: 0.8), step: nil,
                         progress: 0, intent: "", mode: .basic, time: 0)
            var movedBox = false
            scene.onInteract = { if case .move(.box, _) = $0 { movedBox = true } }
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: scene.interactionPoint(for: .box)!))
            XCTAssertTrue(movedBox)
            scene.cancelInteraction()
        }
    }

    func testExpressionShowsEmojiAndThreeMonospacedLinesWithoutClipping() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            scene.render(snapshot: WorldSnapshot(), step: nil, progress: 0,
                         intent: "fallback", mode: .playing, time: 0,
                         expression: PetExpression(thought: "纸箱是我的宇宙飞船", emoji: "🚀", doodle: "x\nxxxxx\nxxxxxxxxxxxxxxxxxx"))
            let emoji = scene.childNode(withName: "//expression.emoji") as! SKLabelNode
            let thought = scene.childNode(withName: "//expression.thought") as! SKLabelNode
            XCTAssertEqual(emoji.text, "🚀")
            XCTAssertEqual(thought.text, "纸箱是我的宇宙飞船")
            var columnAnchors: [CGFloat] = []
            for index in 0..<3 {
                let line = scene.childNode(withName: "//expression.doodle.\(index)") as! SKLabelNode
                XCTAssertFalse((line.text ?? "").isEmpty)
                XCTAssertEqual(line.fontName, "Menlo-Regular")
                XCTAssertEqual(line.horizontalAlignmentMode, .left)
                columnAnchors.append(line.position.x)
                let center = line.convert(.zero, to: scene)
                let frame = line.frame.offsetBy(dx: center.x - line.position.x, dy: center.y - line.position.y)
                XCTAssertTrue(scene.frame.contains(frame))
            }
            XCTAssertEqual(Set(columnAnchors).count, 1)
            let first = scene.childNode(withName: "//expression.doodle.0") as! SKLabelNode
            let last = scene.childNode(withName: "//expression.doodle.2") as! SKLabelNode
            XCTAssertEqual(first.frame.minX, last.frame.minX, accuracy: 0.01)
            XCTAssertEqual(scene.size, CGSize(width: 520, height: 280))
        }
    }

    func testDraggingOutsideSceneRetainsOwnershipUntilMouseUp() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            scene.render(snapshot: WorldSnapshot(), step: nil, progress: 0,
                         intent: "", mode: .basic, time: 0)
            var finalX: Double?
            var dragEnded = 0
            scene.onInteract = {
                if case .move(.ball, let x) = $0 { finalX = x }
                if case .dragEnded = $0 { dragEnded += 1 }
            }
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: scene.interactionPoint(for: .ball)!))
            scene.mouseExited(with: Self.event(.mouseMoved, scene: scene, point: CGPoint(x: 540, y: 80)))
            XCTAssertEqual(dragEnded, 0)
            scene.mouseDragged(with: Self.event(.leftMouseDragged, scene: scene, point: CGPoint(x: 540, y: 80)))
            scene.mouseUp(with: Self.event(.leftMouseUp, scene: scene, point: CGPoint(x: 540, y: 80)))
            XCTAssertEqual(finalX ?? -1, 1, accuracy: 0.0001)
            XCTAssertEqual(dragEnded, 1)
        }
    }

    func testForegroundDogIsPettableWhenItOverlapsTheBox() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            scene.render(snapshot: WorldSnapshot(petX: 0.8, ballX: nil, boxX: 0.8),
                         step: nil, progress: 0, intent: "", mode: .idle, time: 0)
            let dogArt = scene.childNode(withName: "//dog.art")!
            var pets = 0
            var boxMoves = 0
            scene.onInteract = {
                if case .pet = $0 { pets += 1 }
                if case .move(.box, _) = $0 { boxMoves += 1 }
            }
            // Both visible belly and lower cheek used to be claimed by the box.
            for local in [CGPoint(x: -8, y: 4), CGPoint(x: 31, y: 38)] {
                scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: dogArt.convert(local, to: scene)))
                scene.mouseUp(with: Self.event(.leftMouseUp, scene: scene, point: dogArt.convert(local, to: scene)))
            }
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: scene.interactionPoint(for: .pet)!))
            XCTAssertEqual(pets, 3)
            XCTAssertEqual(boxMoves, 0)
        }
    }

    func testVisibleBoxGripRemainsDraggableUnderAnOverlappingDog() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            scene.render(snapshot: WorldSnapshot(petX: 0.8, ballX: 0.8, boxX: 0.8),
                         step: nil, progress: 0, intent: "", mode: .idle, time: 0)
            let grip = scene.childNode(withName: "//box.grip")
            XCTAssertNotNil(grip)
            guard let grip else { return }
            XCTAssertFalse(grip.isHidden)
            let point = scene.interactionPoint(for: .box)!
            XCTAssertTrue(grip.contains(point))
            var boxMoved: Double?
            var pets = 0
            scene.onInteract = {
                if case .move(.box, let x) = $0 { boxMoved = x }
                if case .pet = $0 { pets += 1 }
            }
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: point))
            let end = scene.point(for: .box, at: 0.4)
            scene.mouseDragged(with: Self.event(.leftMouseDragged, scene: scene, point: end))
            scene.mouseUp(with: Self.event(.leftMouseUp, scene: scene, point: end))
            XCTAssertEqual(boxMoved ?? -1, 0.4, accuracy: 0.0001)
            XCTAssertEqual(pets, 0)
        }
    }

    func testPausedPetStillAllowsUserToFinishMovingTheBall() async {
        await MainActor.run {
            let controller = PetController(modelEnabled: false, memoryURL: nil)
            controller.interact(.togglePaused)
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            scene.onInteract = { controller.interact($0) }
            scene.render(snapshot: controller.world.snapshot, step: nil, progress: 0,
                         intent: "", mode: .paused, time: 0)
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: scene.interactionPoint(for: .ball)!))
            scene.render(snapshot: controller.world.snapshot, step: nil, progress: 0,
                         intent: "", mode: .paused, time: 1)
            let end = scene.point(for: .ball, at: 0.8)
            scene.mouseDragged(with: Self.event(.leftMouseDragged, scene: scene, point: end))
            scene.mouseUp(with: Self.event(.leftMouseUp, scene: scene, point: end))
            XCTAssertEqual(controller.world.snapshot.ballX ?? -1, 0.8, accuracy: 0.0001)
            XCTAssertTrue(controller.world.isPaused)
            controller.shutdown()
        }
    }

    func testTakingHeldBallAtRightBoundaryImmediatelyClampsItsGroundPosition() async {
        await MainActor.run {
            let scene = PetScene()
            let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.presentScene(scene)
            var world = PetWorld(snapshot: WorldSnapshot(petX: 1, ballX: 1, heldBall: true))
            scene.render(snapshot: world.snapshot, step: nil, progress: 0,
                         intent: "", mode: .idle, time: 0)
            var receivedX: Double?
            scene.onInteract = {
                if case .move(let target, let x) = $0 {
                    receivedX = x
                    world.move(target: target, to: x)
                }
            }
            let mouth = scene.interactionPoint(for: .ball)!
            scene.mouseDown(with: Self.event(.leftMouseDown, scene: scene, point: mouth))
            XCTAssertEqual(receivedX ?? -1, 1, accuracy: 0.0001)
            scene.render(snapshot: world.snapshot, step: nil, progress: 0,
                         intent: "", mode: .idle, time: 0)
            XCTAssertEqual(scene.interactionPoint(for: .ball)!.x, 434, accuracy: 0.01)
            let shifted = CGPoint(x: mouth.x - 35.8, y: mouth.y)
            scene.mouseDragged(with: Self.event(.leftMouseDragged, scene: scene, point: shifted))
            scene.mouseUp(with: Self.event(.leftMouseUp, scene: scene, point: shifted))
            XCTAssertEqual(world.snapshot.ballX ?? -1, 0.9, accuracy: 0.0001)
        }
    }

    func testDropAnimatesWalkingAndFacesItsDestination() async {
        await MainActor.run {
            let scene = PetScene()
            let step = PetStep(verb: .drop, target: .box)
            let snapshot = WorldSnapshot(petX: 0.8, boxX: 0.2, heldBall: true)
            scene.render(snapshot: snapshot, step: step, progress: 0.3,
                         intent: "", mode: .playing, time: 0.1)
            let foot = scene.childNode(withName: "//dog.foot.left")!
            let art = scene.childNode(withName: "//dog.art")!
            let first = foot.position
            XCTAssertLessThan(art.xScale, 0)
            scene.render(snapshot: snapshot, step: step, progress: 0.4,
                         intent: "", mode: .playing, time: 0.2)
            XCTAssertNotEqual(foot.position, first)
        }
    }

    func testRestWalksWithOpenEyesThenSleepsAfterArriving() async {
        await MainActor.run {
            let scene = PetScene()
            let step = PetStep(verb: .rest, target: .home)
            scene.render(snapshot: WorldSnapshot(petX: 0.5), step: step, progress: 0.3,
                         intent: "", mode: .resting, time: 0.1)
            let eye = scene.childNode(withName: "//dog.eye.left")!
            let foot = scene.childNode(withName: "//dog.foot.left")!
            let art = scene.childNode(withName: "//dog.art")!
            XCTAssertEqual(eye.yScale, 1)
            XCTAssertLessThan(art.xScale, 0)
            let first = foot.position
            scene.render(snapshot: WorldSnapshot(petX: 0.3), step: step, progress: 0.5,
                         intent: "", mode: .resting, time: 0.2)
            XCTAssertNotEqual(foot.position, first)
            scene.render(snapshot: WorldSnapshot(petX: 0.1), step: step, progress: 0.8,
                         intent: "", mode: .resting, time: 0.3)
            XCTAssertEqual(eye.yScale, 0.11, accuracy: 0.001)
            let sleepingFoot = foot.position
            scene.render(snapshot: WorldSnapshot(petX: 0.1), step: step, progress: 0.9,
                         intent: "", mode: .resting, time: 0.5)
            XCTAssertEqual(foot.position, sleepingFoot)
        }
    }

    @MainActor
    private static func event(_ type: NSEvent.EventType, scene: PetScene, point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: scene.convertPoint(toView: point),
                           modifierFlags: [], timestamp: 0, windowNumber: 0,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
}
