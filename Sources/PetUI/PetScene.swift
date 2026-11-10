import AppKit
import PetCore
import SpriteKit

public enum PetInteraction {
    case dragBegan
    case dragEnded
    case move(TargetID, Double)
    case pet
    case toggleBall
    case togglePaused
}

public enum PetDisplayMode: Equatable {
    case thinking
    case playing
    case idle
    case resting
    case basic
    case paused
}

/// A fixed-size illustrated world. The host view can resize; `.aspectFit` keeps
/// the artwork and hit areas in the same 520 × 280 scene coordinates.
@MainActor
public final class PetScene: SKScene {
    public var onInteract: ((PetInteraction) -> Void)?
    public var onWindowDrag: ((NSEvent) -> Void)?
    public var onHide: (() -> Void)?

    /// Scene-coordinate anchors for the host view and accessibility adapters.
    public var ballTogglePoint: CGPoint { CGPoint(x: ballButtonFrame.midX, y: ballButtonFrame.midY) }
    public var pausePoint: CGPoint { CGPoint(x: pauseButtonFrame.midX, y: pauseButtonFrame.midY) }
    public var windowHandlePoint: CGPoint { CGPoint(x: windowHandleFrame.midX, y: windowHandleFrame.midY) }
    public var hidePoint: CGPoint { CGPoint(x: hideFrame.midX, y: hideFrame.midY) }

    public func interactionPoint(for target: TargetID) -> CGPoint? {
        switch target {
        case .ball:
            if !heldBall.isHidden { return heldBall.convert(.zero, to: self) }
            return ballRoot.isHidden ? nil : ballRoot.position
        case .box: return boxGrip.position
        case .pet: return dogArt.convert(CGPoint(x: 18, y: 58), to: self)
        case .home: return CGPoint(x: worldX(0.1), y: 62)
        }
    }

    /// Anchors for placing an unheld object at a normalized world position.
    public func point(for target: TargetID, at normalizedX: Double) -> CGPoint {
        let x = worldX(normalizedX)
        switch target {
        case .ball: return CGPoint(x: x, y: 80)
        case .box: return CGPoint(x: x, y: 51)
        case .pet: return CGPoint(x: x + 18 * 0.72, y: 98 + 58 * 0.72)
        case .home: return CGPoint(x: x, y: 62)
        }
    }

    private enum Palette {
        static let paper = NSColor(calibratedRed: 0.985, green: 0.969, blue: 0.933, alpha: 1)
        static let ink = NSColor(calibratedRed: 0.28, green: 0.26, blue: 0.23, alpha: 1)
        static let muted = NSColor(calibratedRed: 0.53, green: 0.51, blue: 0.46, alpha: 1)
        static let line = NSColor(calibratedRed: 0.87, green: 0.82, blue: 0.73, alpha: 1)
        static let cream = NSColor(calibratedRed: 0.98, green: 0.81, blue: 0.59, alpha: 1)
        static let creamLight = NSColor(calibratedRed: 1, green: 0.91, blue: 0.72, alpha: 1)
        static let ear = NSColor(calibratedRed: 0.69, green: 0.43, blue: 0.30, alpha: 1)
        static let earInner = NSColor(calibratedRed: 0.80, green: 0.55, blue: 0.43, alpha: 1)
        static let nose = NSColor(calibratedRed: 0.32, green: 0.25, blue: 0.24, alpha: 1)
        static let pink = NSColor(calibratedRed: 0.94, green: 0.67, blue: 0.59, alpha: 1)
        static let coral = NSColor(calibratedRed: 0.94, green: 0.47, blue: 0.35, alpha: 1)
        static let coralLight = NSColor(calibratedRed: 1, green: 0.73, blue: 0.53, alpha: 1)
        static let grass = NSColor(calibratedRed: 0.53, green: 0.66, blue: 0.49, alpha: 1)
        static let rug = NSColor(calibratedRed: 0.80, green: 0.85, blue: 0.72, alpha: 1)
        static let box = NSColor(calibratedRed: 0.78, green: 0.61, blue: 0.42, alpha: 1)
        static let boxLight = NSColor(calibratedRed: 0.90, green: 0.74, blue: 0.54, alpha: 1)
        static let boxDark = NSColor(calibratedRed: 0.64, green: 0.46, blue: 0.32, alpha: 1)
    }

    private let scenery = SKNode()
    private let floatingUI = SKNode()
    private let dogRoot = SKNode()
    private let dogArt = SKNode()
    private let ballRoot = SKNode()
    private let boxRoot = SKNode()
    private let boxGrip = SKNode()
    private let dogShadow = SKShapeNode(ellipseOf: CGSize(width: 100, height: 15))
    private let ballShadow = SKShapeNode(ellipseOf: CGSize(width: 39, height: 8))
    private let boxShadow = SKShapeNode(ellipseOf: CGSize(width: 87, height: 10))
    private let tail = SKNode()
    private let leftEar = SKNode()
    private let rightEar = SKNode()
    private let frontLeftFoot = SKNode()
    private let frontRightFoot = SKNode()
    private let backFoot = SKNode()
    private let leftEye = SKNode()
    private let rightEye = SKNode()
    private let heldBall = SKNode()
    private let intentBubble = SKNode()
    private let intentLabel = SKLabelNode(fontNamed: "PingFangSC-Medium")
    private let emojiLabel = SKLabelNode(fontNamed: "AppleColorEmoji")
    private let doodleLabels = (0..<3).map { _ in SKLabelNode(fontNamed: "Menlo-Regular") }
    private let doodleDivider = SKShapeNode(rectOf: CGSize(width: 1, height: 38))
    private let dust = SKNode()
    private let statusLabel = SKLabelNode(fontNamed: "PingFangSC-Medium")
    private let statusDot = SKShapeNode(circleOfRadius: 3.5)
    private let ballButtonLabel = SKLabelNode(fontNamed: "PingFangSC-Medium")
    private let pauseButtonLabel = SKLabelNode(fontNamed: "PingFangSC-Medium")

    private let ballButtonFrame = CGRect(x: 330, y: 10, width: 86, height: 29)
    private let windowHandleFrame = CGRect(x: 14, y: 245, width: 342, height: 25)
    private let hideFrame = CGRect(x: 478, y: 245, width: 28, height: 25)
    private let pauseButtonFrame = CGRect(x: 425, y: 10, width: 81, height: 29)
    private var dragTarget: TargetID?
    private var dragX: CGFloat?
    private var dragOffsetX: CGFloat = 0
    private var didDrag = false
    private var lastMode: PetDisplayMode?
    private var lastBallPresent: Bool?

    public override init() {
        super.init(size: CGSize(width: 520, height: 280))
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = Palette.paper
        buildScene()
    }

    required init?(coder: NSCoder) {
        nil
    }

    public func setTransparent(_ enabled: Bool) {
        scenery.isHidden = enabled
        backgroundColor = enabled ? .clear : Palette.paper
        // Controls and the dog's small thought bubble remain available in both modes.
    }

    public func cancelInteraction() {
        endDrag(commitAt: nil)
    }

    public func render(
        snapshot: WorldSnapshot,
        step: PetStep?,
        progress: Double,
        intent: String,
        mode: PetDisplayMode,
        time: Double,
        expression: PetExpression? = nil
    ) {
        let t = time.isFinite ? time : 0
        let p = progress.isFinite ? min(max(progress, 0), 1) : 0
        let petX = worldX(snapshot.petX)
        let ballX = snapshot.ballX.map(worldX)
        let boxX = worldX(snapshot.boxX)

        let walking = mode != .paused && (step.map {
            $0.verb == .approach || $0.verb == .push || $0.verb == .carry || $0.verb == .drop ||
            ($0.verb == .dig && p < 0.5) ||
            ($0.verb == .rest && p < 0.75 && abs(snapshot.petX - 0.1) > 0.002)
        } ?? false)
        let spinning = mode != .paused && step?.verb == .spin
        let bow = mode != .paused && step?.verb == .bow ? CGFloat(sin(.pi * p)) : 0
        let digging = mode != .paused && step?.verb == .dig && p >= 0.5
        let sleeping = step?.verb == .rest ? p >= 0.75 : mode == .resting
        let hop = mode != .paused && step?.verb == .hop ? CGFloat(sin(.pi * p) * 12) : 0
        let breath = CGFloat(sin(t * 2.2) * 1.5)
        let stride = walking ? CGFloat(sin(t * 16) * 7) : 0
        let bodyBob = walking ? abs(stride) * 0.23 : 0
        let dogX = dragTarget == .pet ? (dragX ?? petX) : petX
        dogRoot.position = CGPoint(x: dogX, y: 98 + hop + breath + bodyBob - (sleeping ? 12 : 0) - bow * 5)
        dogShadow.position = CGPoint(x: dogX, y: 66)
        dogShadow.xScale = max(0.55, 0.76 - hop / 120)
        dogShadow.alpha = 0.16 - hop / 400
        dogArt.yScale = sleeping ? 0.78 : 1 - bow * 0.22
        dogArt.zRotation = bow * -0.10 * (dogArt.xScale < 0 ? -1 : 1)

        if let step, step.verb == .look || step.verb == .dig || walking {
            let targetX: CGFloat
            switch step.target {
            case .ball: targetX = ballX ?? dogX
            case .box: targetX = boxX
            case .home: targetX = worldX(0.1)
            case .pet: targetX = dogX
            }
            if abs(targetX - dogX) > 7 { dogArt.xScale = targetX < dogX ? -1 : 1 }
        }

        if spinning {
            let turn = CGFloat(cos(p * .pi * 2))
            dogArt.xScale = (turn < 0 ? -1 : 1) * max(0.12, abs(turn))
            dogArt.zRotation = CGFloat(sin(p * .pi * 2) * 0.08)
        } else {
            dogArt.xScale = dogArt.xScale < 0 ? -1 : 1
        }

        tail.zRotation = CGFloat(sin(t * (mode == .playing ? 12 : 7))) * (mode == .paused ? 0.025 : sleeping ? 0.10 : 0.36)
        leftEar.zRotation = CGFloat(sin(t * 3.1)) * (sleeping ? 0.035 : 0.10)
        rightEar.zRotation = CGFloat(sin(t * 2.8 + 1.2)) * (sleeping ? 0.03 : 0.075)
        frontLeftFoot.position = CGPoint(x: 8 + bow * 12, y: -28 + (walking ? max(0, stride) : 0) + (digging ? CGFloat(sin(t * 25) * 9) : 0))
        frontRightFoot.position = CGPoint(x: 34 + bow * 12, y: -27 + (walking ? max(0, -stride) : 0) + (digging ? CGFloat(cos(t * 25) * 9) : 0))
        backFoot.position = CGPoint(x: -37, y: -25 + (walking ? max(0, -stride * 0.6) : 0))
        let blink = !sleeping && sin(t * 1.9) > 0.995
        leftEye.yScale = sleeping || blink ? 0.11 : 1
        rightEye.yScale = sleeping || blink ? 0.11 : 1

        boxRoot.position = CGPoint(x: dragTarget == .box ? (dragX ?? boxX) : boxX, y: 91)
        boxShadow.position = CGPoint(x: boxRoot.position.x, y: 66)
        boxGrip.position = CGPoint(x: boxRoot.position.x, y: 51)
        ballRoot.isHidden = ballX == nil || snapshot.heldBall
        if let ballX {
            ballRoot.position = CGPoint(x: dragTarget == .ball ? (dragX ?? ballX) : ballX, y: 80)
            ballShadow.position = CGPoint(x: ballRoot.position.x, y: 66)
            ballShadow.isHidden = snapshot.heldBall
            ballRoot.zRotation = CGFloat(sin(t * 0.8) * 0.06)
        } else {
            ballShadow.isHidden = true
        }
        heldBall.isHidden = !snapshot.heldBall
        heldBall.zRotation = CGFloat(sin(t * 5) * 0.045)

        dust.isHidden = !digging
        dust.position = CGPoint(x: dogX + (dogArt.xScale < 0 ? -30 : 30), y: 73)
        for (index, mote) in dust.children.enumerated() {
            let phase = (t * 3 + Double(index) * 0.31).truncatingRemainder(dividingBy: 1)
            mote.position = CGPoint(x: CGFloat(index - 1) * 8 - CGFloat(phase * 15), y: CGFloat(sin(phase * .pi) * 18))
            mote.alpha = 1 - phase
        }

        updateExpression(expression, fallback: intent)
        updateStatus(mode)
        let ballPresent = ballX != nil || snapshot.heldBall
        if lastBallPresent != ballPresent {
            ballButtonLabel.text = ballPresent ? "拿走球" : "放回球"
            lastBallPresent = ballPresent
        }
        intentBubble.position = CGPoint(x: 260, y: 209)
    }

    public override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        if hideFrame.contains(point) {
            cancelInteraction()
            onHide?()
            return
        }
        if windowHandleFrame.contains(point) {
            cancelInteraction()
            onWindowDrag?(event)
            return
        }
        if pauseButtonFrame.contains(point) {
            onInteract?(.togglePaused)
            return
        }
        if ballButtonFrame.contains(point) {
            onInteract?(.toggleBall)
            return
        }
        // Check the ball in scene coordinates, including when it is in the dog's
        // mouth or the dog has turned around. It must remain easy to take back.
        if let ballPoint = interactionPoint(for: .ball),
           hypot(point.x - ballPoint.x, point.y - ballPoint.y) <= (heldBall.isHidden ? 23 : 16) {
            beginDrag(.ball, at: ballPoint.x, pointerX: point.x)
            return
        }
        if isDogHit(point) {
            onInteract?(.pet)
            return
        }
        let boxPoint = boxRoot.convert(point, from: self)
        if boxGrip.contains(point) || CGRect(x: -45, y: -33, width: 99, height: 91).contains(boxPoint) {
            beginDrag(.box, at: boxRoot.position.x, pointerX: point.x)
        }
    }

    private func isDogHit(_ point: CGPoint) -> Bool {
        // Use the artwork's filled paths, including moving paws and ears, so
        // transparent gaps cannot steal clicks from the box behind the dog.
        var pending = dogArt.children
        while let node = pending.popLast() {
            guard !node.isHidden, node.alpha > 0 else { continue }
            if let shape = node as? SKShapeNode, shape.fillColor.alphaComponent > 0,
               let path = shape.path, path.contains(shape.convert(point, from: self)) {
                return true
            }
            pending.append(contentsOf: node.children)
        }
        return false
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let dragTarget else { return }
        let x = min(max(event.location(in: self).x - dragOffsetX, 76), 434)
        didDrag = true
        dragX = x
        onInteract?(.move(dragTarget, normalizedX(x)))
    }

    public override func mouseUp(with event: NSEvent) {
        let x = min(max(event.location(in: self).x - dragOffsetX, 76), 434)
        endDrag(commitAt: didDrag ? x : nil)
    }

    public override func mouseExited(with event: NSEvent) {
        // AppKit continues sending a held drag to its original view outside the
        // frame. Keep ownership until mouseUp; hide/removal cancels explicitly.
    }

    public override func willMove(from view: SKView) {
        cancelInteraction()
    }

    private func endDrag(commitAt x: CGFloat?) {
        guard let target = dragTarget else { return }
        if let x { onInteract?(.move(target, normalizedX(x))) }
        dragTarget = nil
        dragX = nil
        dragOffsetX = 0
        didDrag = false
        onInteract?(.dragEnded)
    }

    private func beginDrag(_ target: TargetID, at x: CGFloat, pointerX: CGFloat) {
        let boundedX = min(max(x, 76), 434)
        dragOffsetX = pointerX - boundedX
        dragTarget = target
        dragX = boundedX
        didDrag = false
        onInteract?(.dragBegan)
        onInteract?(.move(target, normalizedX(boundedX)))
    }

    private func worldX(_ normalized: Double) -> CGFloat {
        CGFloat(min(max(normalized.isFinite ? normalized : 0.5, 0), 1)) * 358 + 76
    }

    private func normalizedX(_ x: CGFloat) -> Double {
        Double((x - 76) / 358)
    }

    private func updateExpression(_ expression: PetExpression?, fallback: String) {
        let thought = (expression?.thought ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        intentLabel.text = String(thought.prefix(30))
        emojiLabel.text = expression.map { String($0.emoji.prefix(3)) } ?? ""
        let rows = (expression?.doodle ?? "").split(separator: "\n", omittingEmptySubsequences: false)
        for (index, node) in doodleLabels.enumerated() {
            node.text = index < rows.count ? String(rows[index].prefix(18)) : ""
        }
        let hasDoodle = rows.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        doodleDivider.isHidden = !hasDoodle
        intentLabel.preferredMaxLayoutWidth = hasDoodle ? 223 : 358
        intentLabel.position.x = hasDoodle ? -71 : -5
        intentBubble.isHidden = thought.isEmpty && (emojiLabel.text ?? "").isEmpty && !hasDoodle
    }

    private func updateStatus(_ mode: PetDisplayMode) {
        guard mode != lastMode else { return }
        lastMode = mode
        switch mode {
        case .thinking: statusLabel.text = "酝酿点子"; statusDot.fillColor = Palette.coral
        case .playing: statusLabel.text = "自己玩耍"; statusDot.fillColor = Palette.grass
        case .idle: statusLabel.text = "陪着你"; statusDot.fillColor = Palette.grass
        case .resting: statusLabel.text = "打个盹"; statusDot.fillColor = Palette.ear
        case .basic: statusLabel.text = "基础活动"; statusDot.fillColor = Palette.grass
        case .paused: statusLabel.text = "已暂停"; statusDot.fillColor = Palette.muted
        }
        pauseButtonLabel.text = mode == .paused ? "继续" : "暂停"
    }

    private func buildScene() {
        scenery.zPosition = 0
        addChild(scenery)
        buildBackground()
        buildDog()
        buildBall()
        buildBox()
        buildBubble()
        buildControls()
        dust.zPosition = 7
        for _ in 0..<4 { dust.addChild(circle(radius: 2, fill: Palette.box.withAlphaComponent(0.7))) }
        dust.isHidden = true
        addChild(dust)
    }

    private func buildBackground() {
        let frame = shape(rounded: CGRect(x: 5, y: 5, width: 510, height: 270), radius: 18,
                          fill: Palette.paper, stroke: Palette.line, width: 1)
        scenery.addChild(frame)
        let sun = circle(radius: 37, fill: NSColor(calibratedRed: 1, green: 0.88, blue: 0.68, alpha: 0.36))
        sun.position = CGPoint(x: 450, y: 126)
        scenery.addChild(sun)
        let horizon = SKShapeNode(rectOf: CGSize(width: 480, height: 1))
        horizon.position = CGPoint(x: 260, y: 69)
        horizon.fillColor = Palette.line.withAlphaComponent(0.48)
        horizon.strokeColor = .clear
        scenery.addChild(horizon)
        let rug = SKShapeNode(ellipseOf: CGSize(width: 162, height: 21))
        rug.position = CGPoint(x: worldX(0.1), y: 62)
        rug.fillColor = Palette.rug.withAlphaComponent(0.66)
        rug.strokeColor = Palette.grass.withAlphaComponent(0.28)
        rug.lineWidth = 1
        scenery.addChild(rug)
        for x in [29, 183, 260, 312, 460, 488] as [CGFloat] {
            let grass = SKShapeNode(path: grassPath())
            grass.position = CGPoint(x: x, y: 65)
            grass.setScale(0.7)
            grass.strokeColor = Palette.grass.withAlphaComponent(0.48)
            grass.lineWidth = 1.5
            grass.lineCap = .round
            scenery.addChild(grass)
        }
        let hint = label("拖道具 · 摸摸它", size: 10, color: Palette.muted)
        hint.horizontalAlignmentMode = .left
        hint.position = CGPoint(x: 18, y: 24)
        scenery.addChild(hint)
    }

    private func buildDog() {
        dogShadow.fillColor = Palette.ear
        dogShadow.strokeColor = .clear
        dogShadow.alpha = 0.16
        dogShadow.zPosition = 1
        addChild(dogShadow)
        dogRoot.setScale(0.72)
        dogRoot.zPosition = 5
        addChild(dogRoot)
        dogArt.name = "dog.art"
        leftEye.name = "dog.eye.left"
        frontLeftFoot.name = "dog.foot.left"
        dogRoot.addChild(dogArt)

        tail.position = CGPoint(x: -49, y: 13)
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: 5, y: 1))
        tailPath.addCurve(to: CGPoint(x: -21, y: 28), control1: CGPoint(x: -17, y: 0), control2: CGPoint(x: -25, y: 11))
        tailPath.addCurve(to: CGPoint(x: -9, y: 27), control1: CGPoint(x: -22, y: 35), control2: CGPoint(x: -13, y: 34))
        tailPath.addCurve(to: CGPoint(x: 7, y: 14), control1: CGPoint(x: -12, y: 24), control2: CGPoint(x: -4, y: 19))
        tailPath.closeSubpath()
        tail.addChild(shape(path: tailPath, fill: Palette.ear, stroke: Palette.nose.withAlphaComponent(0.25), width: 1))
        dogArt.addChild(tail)

        // Three individual paws allow a gentle alternating stride.
        backFoot.position = CGPoint(x: -37, y: -25)
        backFoot.addChild(shape(rounded: CGRect(x: -12, y: -10, width: 26, height: 25), radius: 11,
                                fill: Palette.ear, stroke: Palette.nose.withAlphaComponent(0.18), width: 1))
        dogArt.addChild(backFoot)
        let body = SKShapeNode(ellipseOf: CGSize(width: 111, height: 72))
        body.position = CGPoint(x: -8, y: 4)
        body.fillColor = Palette.cream
        body.strokeColor = Palette.ear.withAlphaComponent(0.35)
        body.lineWidth = 1.5
        dogArt.addChild(body)
        let belly = SKShapeNode(ellipseOf: CGSize(width: 55, height: 44))
        belly.position = CGPoint(x: 11, y: -6)
        belly.fillColor = Palette.creamLight
        belly.strokeColor = .clear
        dogArt.addChild(belly)

        frontLeftFoot.position = CGPoint(x: 8, y: -28)
        frontRightFoot.position = CGPoint(x: 34, y: -27)
        for foot in [frontLeftFoot, frontRightFoot] {
            foot.addChild(shape(rounded: CGRect(x: -11, y: -14, width: 23, height: 30), radius: 10,
                                fill: Palette.creamLight, stroke: Palette.ear.withAlphaComponent(0.27), width: 1))
            dogArt.addChild(foot)
        }

        let neck = SKShapeNode(ellipseOf: CGSize(width: 61, height: 70))
        neck.position = CGPoint(x: 28, y: 20)
        neck.fillColor = Palette.creamLight
        neck.strokeColor = .clear
        dogArt.addChild(neck)

        leftEar.position = CGPoint(x: -4, y: 52)
        leftEar.addChild(earShape(mirrored: true))
        dogArt.addChild(leftEar)
        let head = SKShapeNode(ellipseOf: CGSize(width: 90, height: 79))
        head.position = CGPoint(x: 31, y: 51)
        head.fillColor = Palette.creamLight
        head.strokeColor = Palette.ear.withAlphaComponent(0.36)
        head.lineWidth = 1.5
        dogArt.addChild(head)
        rightEar.position = CGPoint(x: 59, y: 57)
        rightEar.addChild(earShape(mirrored: false))
        dogArt.addChild(rightEar)

        let muzzle = SKShapeNode(ellipseOf: CGSize(width: 56, height: 39))
        muzzle.position = CGPoint(x: 54, y: 32)
        muzzle.fillColor = NSColor(calibratedRed: 1, green: 0.95, blue: 0.81, alpha: 1)
        muzzle.strokeColor = .clear
        dogArt.addChild(muzzle)
        for (eye, x) in [(leftEye, CGFloat(18)), (rightEye, CGFloat(53))] {
            eye.position = CGPoint(x: x, y: 61)
            eye.addChild(circle(radius: 4.5, fill: Palette.nose))
            dogArt.addChild(eye)
        }
        let shine = circle(radius: 1.25, fill: .white)
        shine.position = CGPoint(x: 54, y: 63)
        dogArt.addChild(shine)
        let cheek = circle(radius: 5, fill: Palette.pink.withAlphaComponent(0.50))
        cheek.position = CGPoint(x: 17, y: 35)
        dogArt.addChild(cheek)
        let nose = SKShapeNode(ellipseOf: CGSize(width: 27, height: 20))
        nose.position = CGPoint(x: 78, y: 40)
        nose.fillColor = Palette.nose
        nose.strokeColor = .clear
        dogArt.addChild(nose)
        let noseGlint = circle(radius: 2.2, fill: .white.withAlphaComponent(0.68))
        noseGlint.position = CGPoint(x: 82, y: 43)
        dogArt.addChild(noseGlint)
        let smilePath = CGMutablePath()
        smilePath.move(to: CGPoint(x: 62, y: 25))
        smilePath.addQuadCurve(to: CGPoint(x: 77, y: 24), control: CGPoint(x: 70, y: 17))
        let smile = SKShapeNode(path: smilePath)
        smile.strokeColor = Palette.nose.withAlphaComponent(0.55)
        smile.lineWidth = 1.4
        smile.lineCap = .round
        dogArt.addChild(smile)

        heldBall.position = CGPoint(x: 96, y: 20)
        heldBall.setScale(0.53)
        heldBall.addChild(ballArt())
        heldBall.isHidden = true
        dogArt.addChild(heldBall)
    }

    private func earShape(mirrored: Bool) -> SKNode {
        let root = SKNode()
        let earPath = CGMutablePath()
        earPath.move(to: CGPoint(x: 0, y: 12))
        earPath.addCurve(to: CGPoint(x: 25, y: -25), control1: CGPoint(x: 19, y: 20), control2: CGPoint(x: 31, y: 7))
        earPath.addCurve(to: CGPoint(x: 5, y: -15), control1: CGPoint(x: 24, y: -35), control2: CGPoint(x: 8, y: -30))
        earPath.closeSubpath()
        let outer = shape(path: earPath, fill: Palette.ear, stroke: Palette.nose.withAlphaComponent(0.22), width: 1)
        root.addChild(outer)
        let inset = SKShapeNode(ellipseOf: CGSize(width: 11, height: 22))
        inset.position = CGPoint(x: 17, y: -10)
        inset.zRotation = -0.25
        inset.fillColor = Palette.earInner.withAlphaComponent(0.75)
        inset.strokeColor = .clear
        root.addChild(inset)
        root.xScale = mirrored ? -1 : 1
        return root
    }

    private func buildBall() {
        ballShadow.fillColor = Palette.ear
        ballShadow.strokeColor = .clear
        ballShadow.alpha = 0.15
        ballShadow.zPosition = 1
        addChild(ballShadow)
        ballRoot.setScale(0.8)
        ballRoot.zPosition = 6
        ballRoot.addChild(ballArt())
        addChild(ballRoot)
    }

    private func ballArt() -> SKNode {
        let root = SKNode()
        let ball = circle(radius: 19, fill: Palette.coral, stroke: Palette.ear.withAlphaComponent(0.32), width: 1.2)
        root.addChild(ball)
        let seamPath = CGMutablePath()
        seamPath.move(to: CGPoint(x: -13, y: 13))
        seamPath.addQuadCurve(to: CGPoint(x: 12, y: -14), control: CGPoint(x: -10, y: -9))
        let seam = SKShapeNode(path: seamPath)
        seam.strokeColor = Palette.coralLight.withAlphaComponent(0.85)
        seam.lineWidth = 3
        seam.lineCap = .round
        root.addChild(seam)
        let glint = SKShapeNode(ellipseOf: CGSize(width: 8, height: 5))
        glint.position = CGPoint(x: -7, y: 10)
        glint.zRotation = -0.4
        glint.fillColor = .white.withAlphaComponent(0.72)
        glint.strokeColor = .clear
        root.addChild(glint)
        return root
    }

    private func buildBox() {
        boxShadow.fillColor = Palette.ear
        boxShadow.strokeColor = .clear
        boxShadow.alpha = 0.15
        boxShadow.zPosition = 1
        addChild(boxShadow)
        boxRoot.setScale(0.78)
        boxRoot.zPosition = 3
        addChild(boxRoot)
        // A visible handle below the box stays reachable when the dog sits in
        // front of it. Its hit area is the visible rounded shape itself.
        boxGrip.name = "box.grip"
        boxGrip.zPosition = 7
        boxGrip.addChild(shape(rounded: CGRect(x: -25, y: -10, width: 50, height: 20), radius: 8,
                               fill: Palette.boxLight.withAlphaComponent(0.95),
                               stroke: Palette.boxDark.withAlphaComponent(0.40), width: 1))
        let gripLabel = label("⠿ 箱子", size: 9, color: Palette.boxDark)
        boxGrip.addChild(gripLabel)
        addChild(boxGrip)

        let inside = shape(path: polygon([(-37, 22), (-28, 36), (29, 36), (38, 22)]),
                           fill: Palette.boxDark, stroke: Palette.boxDark, width: 1)
        boxRoot.addChild(inside)
        let backFlap = shape(path: polygon([(-28, 36), (-21, 52), (24, 52), (29, 36)]),
                             fill: Palette.boxLight, stroke: Palette.boxDark.withAlphaComponent(0.5), width: 1)
        boxRoot.addChild(backFlap)
        let side = shape(path: polygon([(25, 22), (38, 31), (38, -19), (25, -28)]),
                         fill: Palette.box, stroke: Palette.boxDark.withAlphaComponent(0.60), width: 1)
        boxRoot.addChild(side)
        let front = shape(path: polygon([(-37, 22), (25, 22), (25, -28), (-37, -28)]),
                          fill: Palette.boxLight, stroke: Palette.boxDark.withAlphaComponent(0.58), width: 1)
        boxRoot.addChild(front)
        let frontFlap = shape(path: polygon([(-37, 22), (25, 22), (31, 8), (-32, 8)]),
                              fill: Palette.box, stroke: Palette.boxDark.withAlphaComponent(0.40), width: 1)
        boxRoot.addChild(frontFlap)
        let tape = shape(rounded: CGRect(x: -10, y: -28, width: 10, height: 36), radius: 1,
                         fill: Palette.box.withAlphaComponent(0.52))
        boxRoot.addChild(tape)
        let sideFlap = shape(path: polygon([(25, 22), (38, 31), (47, 24), (31, 8)]),
                             fill: Palette.boxLight, stroke: Palette.boxDark.withAlphaComponent(0.38), width: 1)
        boxRoot.addChild(sideFlap)
    }

    private func buildBubble() {
        intentBubble.zPosition = 10
        let background = shape(rounded: CGRect(x: -240, y: -32, width: 480, height: 66), radius: 14,
                               fill: .white.withAlphaComponent(0.91),
                               stroke: Palette.line.withAlphaComponent(0.68), width: 1)
        intentBubble.addChild(background)
        emojiLabel.name = "expression.emoji"
        emojiLabel.fontSize = 25
        emojiLabel.verticalAlignmentMode = .center
        emojiLabel.position = CGPoint(x: -211, y: 1)
        intentBubble.addChild(emojiLabel)
        intentLabel.name = "expression.thought"
        intentLabel.fontSize = 12.5
        intentLabel.fontColor = Palette.ink
        intentLabel.verticalAlignmentMode = .center
        intentLabel.numberOfLines = 2
        intentLabel.lineBreakMode = .byCharWrapping
        intentLabel.position = CGPoint(x: -71, y: 1)
        intentBubble.addChild(intentLabel)
        doodleDivider.position = CGPoint(x: 56, y: 1)
        doodleDivider.fillColor = Palette.line.withAlphaComponent(0.6)
        doodleDivider.strokeColor = .clear
        intentBubble.addChild(doodleDivider)
        for (index, node) in doodleLabels.enumerated() {
            node.name = "expression.doodle.\(index)"
            node.fontSize = 10.5
            node.fontColor = Palette.ear
            node.verticalAlignmentMode = .center
            node.horizontalAlignmentMode = .left
            node.position = CGPoint(x: 75, y: 17 - CGFloat(index) * 13)
            intentBubble.addChild(node)
        }
        intentBubble.isHidden = true
        addChild(intentBubble)
    }

    private func buildControls() {
        floatingUI.zPosition = 20
        addChild(floatingUI)
        floatingUI.addChild(shape(rounded: windowHandleFrame, radius: 8,
                                 fill: .white.withAlphaComponent(0.60)))
        let title = label("⠿  小狗的角落", size: 12, color: Palette.ink, bold: true)
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: 23, y: windowHandleFrame.midY)
        floatingUI.addChild(title)
        let dragHint = label("拖这里移动", size: 9, color: Palette.muted)
        dragHint.horizontalAlignmentMode = .right
        dragHint.position = CGPoint(x: 345, y: windowHandleFrame.midY)
        floatingUI.addChild(dragHint)
        floatingUI.addChild(shape(rounded: hideFrame, radius: 8,
                                 fill: .white.withAlphaComponent(0.8), stroke: Palette.line, width: 1))
        let hide = label("−", size: 20, color: Palette.muted)
        hide.position = hidePoint
        floatingUI.addChild(hide)
        statusDot.position = CGPoint(x: 369, y: 258)
        statusDot.strokeColor = .clear
        floatingUI.addChild(statusDot)
        statusLabel.fontSize = 10
        statusLabel.fontColor = Palette.muted
        statusLabel.horizontalAlignmentMode = .left
        statusLabel.verticalAlignmentMode = .center
        statusLabel.position = CGPoint(x: 379, y: 258)
        floatingUI.addChild(statusLabel)
        floatingUI.addChild(shape(rounded: ballButtonFrame, radius: 12,
                                 fill: .white.withAlphaComponent(0.86), stroke: Palette.line, width: 1))
        ballButtonLabel.fontSize = 11
        ballButtonLabel.fontColor = Palette.ink
        ballButtonLabel.verticalAlignmentMode = .center
        ballButtonLabel.position = ballTogglePoint
        floatingUI.addChild(ballButtonLabel)
        floatingUI.addChild(shape(rounded: pauseButtonFrame, radius: 12,
                                 fill: Palette.ink.withAlphaComponent(0.94)))
        pauseButtonLabel.fontSize = 11
        pauseButtonLabel.fontColor = .white
        pauseButtonLabel.verticalAlignmentMode = .center
        pauseButtonLabel.position = pausePoint
        floatingUI.addChild(pauseButtonLabel)
    }

    private func label(_ text: String, size: CGFloat, color: NSColor, bold: Bool = false) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: bold ? "PingFangSC-Semibold" : "PingFangSC-Regular")
        node.text = text
        node.fontSize = size
        node.fontColor = color
        node.verticalAlignmentMode = .center
        return node
    }

    private func circle(radius: CGFloat, fill: NSColor, stroke: NSColor = .clear, width: CGFloat = 0) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = width
        node.isAntialiased = true
        return node
    }

    private func shape(rounded rect: CGRect, radius: CGFloat, fill: NSColor,
                       stroke: NSColor = .clear, width: CGFloat = 0) -> SKShapeNode {
        let node = SKShapeNode(path: CGPath(roundedRect: rect, cornerWidth: radius,
                                             cornerHeight: radius, transform: nil))
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = width
        node.isAntialiased = true
        return node
    }

    private func shape(path: CGPath, fill: NSColor, stroke: NSColor = .clear,
                       width: CGFloat = 0) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = width
        node.isAntialiased = true
        return node
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        path.closeSubpath()
        return path
    }

    private func grassPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: -6, y: 10), control: CGPoint(x: -6, y: 6))
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: 3, y: 14), control: CGPoint(x: 0, y: 8))
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: 9, y: 8), control: CGPoint(x: 7, y: 7))
        return path
    }
}
