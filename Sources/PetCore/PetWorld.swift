import Foundation

public enum ActionVerb: String, Codable, Sendable, CaseIterable {
    case look, approach, push, carry, drop, hop, rest, spin, bow, dig
}

public enum TargetID: String, Codable, Sendable, CaseIterable {
    case pet, ball, box, home
}

public struct PetStep: Codable, Sendable, Equatable {
    public var verb: ActionVerb
    public var target: TargetID

    public init(verb: ActionVerb, target: TargetID) {
        self.verb = verb
        self.target = target
    }
}

public struct PetExpression: Codable, Sendable, Equatable {
    public var thought: String
    public var emoji: String
    public var doodle: String

    public init(thought: String, emoji: String, doodle: String) {
        self.thought = thought
        self.emoji = emoji
        self.doodle = doodle
    }
}

public struct PetPlan: Codable, Sendable, Equatable {
    public var intent: String
    public var steps: [PetStep]
    public var expression: PetExpression?

    public init(intent: String, steps: [PetStep], expression: PetExpression? = nil) {
        self.intent = intent
        self.steps = steps
        self.expression = expression
    }
}

public struct WorldSnapshot: Codable, Sendable, Equatable {
    public var revision: Int
    public var petX: Double
    public var ballX: Double?
    public var boxX: Double
    public var heldBall: Bool
    public var recentEvents: [String]
    public var completedActivities: [String]

    public init(
        revision: Int = 0,
        petX: Double = 0.25,
        ballX: Double? = 0.55,
        boxX: Double = 0.8,
        heldBall: Bool = false,
        recentEvents: [String] = [],
        completedActivities: [String] = []
    ) {
        self.revision = revision
        self.petX = petX
        self.ballX = ballX
        self.boxX = boxX
        self.heldBall = heldBall
        self.recentEvents = recentEvents
        self.completedActivities = completedActivities
    }
}

public enum PetWorldError: Error, Equatable, Sendable {
    case staleRevision
    case busy
    case paused
    case invalidPlan
    case invalidStep(Int)
}

public struct PetWorld: Sendable {
    public private(set) var snapshot = WorldSnapshot()
    public private(set) var currentPlan: PetPlan?
    public var currentStep: PetStep? {
        guard let currentPlan, stepIndex < currentPlan.steps.count else { return nil }
        return currentPlan.steps[stepIndex]
    }
    public private(set) var stepProgress: Double = 0
    public private(set) var isPaused = false

    private struct StepMotion: Sendable {
        var verb: ActionVerb
        var start: WorldSnapshot
        var end: WorldSnapshot
        var duration: Double
        var event: String
    }

    private var motions: [StepMotion] = []
    private var stepIndex = 0
    private var stepElapsed: Double = 0

    public init(snapshot: WorldSnapshot = WorldSnapshot()) {
        self.snapshot = snapshot
    }

    public mutating func submit(plan: PetPlan, revision: Int) throws {
        guard revision == snapshot.revision else { throw PetWorldError.staleRevision }
        guard !isPaused else { throw PetWorldError.paused }
        guard currentPlan == nil else { throw PetWorldError.busy }
        let intent = plan.intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !intent.isEmpty, plan.intent.count <= 160, (1...3).contains(plan.steps.count) else {
            throw PetWorldError.invalidPlan
        }

        var simulated = snapshot
        var accepted: [StepMotion] = []
        for (index, step) in plan.steps.enumerated() {
            guard let motion = Self.simulate(step, from: simulated) else {
                throw PetWorldError.invalidStep(index)
            }
            accepted.append(motion)
            simulated = motion.end
        }

        currentPlan = plan
        motions = accepted
        stepIndex = 0
        stepElapsed = 0
        stepProgress = 0
    }

    public mutating func advance(seconds: Double) {
        guard seconds.isFinite, seconds > 0, !isPaused, currentPlan != nil else { return }

        var remaining = seconds
        while remaining > 0, currentPlan != nil, stepIndex < motions.count {
            let motion = motions[stepIndex]
            let consumed = min(remaining, motion.duration - stepElapsed)
            stepElapsed += consumed
            remaining -= consumed
            stepProgress = min(1, stepElapsed / motion.duration)

            if stepProgress < 1 {
                applyProgress(of: motion, progress: stepProgress)
                break
            }

            snapshot.petX = motion.end.petX
            snapshot.ballX = motion.end.ballX
            snapshot.heldBall = motion.end.heldBall
            appendEvent(motion.event)
            stepIndex += 1
            stepElapsed = 0
            stepProgress = 0

            if stepIndex == motions.count {
                if let intent = currentPlan?.intent {
                    snapshot.completedActivities.append(intent)
                    trimHistory(&snapshot.completedActivities, keeping: 12)
                }
                cancelPlan()
            }
        }
    }

    public mutating func move(target: TargetID, to position: Double) {
        guard position.isFinite else { return }
        let bounded = Self.clamp(position)
        switch target {
        case .pet:
            invalidatePlan()
            snapshot.petX = bounded
            if snapshot.heldBall { snapshot.ballX = bounded }
        case .ball:
            guard snapshot.ballX != nil else { return }
            invalidatePlan()
            snapshot.ballX = bounded
            snapshot.heldBall = false
        case .box:
            invalidatePlan()
            snapshot.boxX = bounded
        case .home:
            return
        }
        appendEvent("moved \(target.rawValue)")
    }

    public mutating func setBallPresent(_ present: Bool) {
        invalidatePlan()
        if present {
            snapshot.ballX = snapshot.ballX ?? 0.55
            snapshot.heldBall = false
            appendEvent("ball appeared")
        } else {
            snapshot.ballX = nil
            snapshot.heldBall = false
            appendEvent("ball removed")
        }
    }

    public mutating func pet() {
        invalidatePlan()
        appendEvent("petted")
    }

    public mutating func setPaused(_ paused: Bool) {
        invalidatePlan()
        isPaused = paused
        appendEvent(paused ? "paused" : "resumed")
    }

    public mutating func interruptForHiding() {
        invalidatePlan()
        appendEvent("hidden")
    }

    public mutating func reset() {
        let nextRevision = snapshot.revision < Int.max ? snapshot.revision + 1 : Int.max
        snapshot = WorldSnapshot(revision: nextRevision)
        isPaused = false
        cancelPlan()
    }

    public mutating func restoreCompletedActivities(_ activities: [String]) {
        snapshot.completedActivities = Array(activities.suffix(12))
    }

    private mutating func invalidatePlan() {
        if snapshot.revision < Int.max { snapshot.revision += 1 }
        cancelPlan()
    }

    private mutating func cancelPlan() {
        currentPlan = nil
        motions = []
        stepIndex = 0
        stepElapsed = 0
        stepProgress = 0
    }

    private mutating func appendEvent(_ event: String) {
        if event.hasPrefix("moved "), snapshot.recentEvents.last == event { return }
        snapshot.recentEvents.append(event)
        trimHistory(&snapshot.recentEvents, keeping: 8)
    }

    private func trimHistory(_ values: inout [String], keeping limit: Int) {
        if values.count > limit { values.removeFirst(values.count - limit) }
    }

    private mutating func applyProgress(of motion: StepMotion, progress: Double) {
        if motion.verb == .dig {
            snapshot.petX = Self.lerp(motion.start.petX, motion.end.petX, min(1, progress * 2))
            if motion.start.heldBall { snapshot.ballX = snapshot.petX }
            return
        }
        if motion.verb == .rest {
            snapshot.petX = Self.lerp(motion.start.petX, motion.end.petX, min(1, progress / 0.75))
            if motion.start.heldBall { snapshot.ballX = snapshot.petX }
            return
        }
        if motion.verb == .push, let startBall = motion.start.ballX,
           let endBall = motion.end.ballX {
            let direction = endBall > startBall ? 1.0 : -1.0
            let contactX = Self.clamp(startBall - direction * 0.04)
            if progress <= 0.5 {
                snapshot.petX = Self.lerp(motion.start.petX, contactX, progress * 2)
                snapshot.ballX = startBall
            } else {
                let rollingProgress = (progress - 0.5) * 2
                snapshot.petX = Self.lerp(contactX, motion.end.petX, rollingProgress)
                snapshot.ballX = Self.lerp(startBall, endBall, rollingProgress)
            }
            return
        }

        snapshot.petX = Self.lerp(motion.start.petX, motion.end.petX, progress)
        if motion.start.heldBall {
            snapshot.ballX = snapshot.petX
        } else {
            snapshot.ballX = motion.start.ballX
        }
    }

    private static func simulate(_ step: PetStep, from start: WorldSnapshot) -> StepMotion? {
        var end = start
        let duration: Double

        switch step.verb {
        case .look:
            guard targetPosition(step.target, in: start) != nil else { return nil }
            duration = 1
        case .approach:
            guard let destination = targetPosition(step.target, in: start) else { return nil }
            end.petX = destination
            if end.heldBall { end.ballX = destination }
            duration = 2
        case .push:
            guard step.target == .ball, let ball = start.ballX, !start.heldBall else { return nil }
            let rolledBall = clamp(ball + (ball <= 0.85 ? 0.15 : -0.15))
            let direction = rolledBall > ball ? 1.0 : -1.0
            end.ballX = rolledBall
            end.petX = clamp(rolledBall - direction * 0.04)
            duration = 2.5
        case .carry:
            guard step.target == .ball, let ball = start.ballX, !start.heldBall else { return nil }
            end.petX = ball
            end.ballX = ball
            end.heldBall = true
            duration = 2.5
        case .drop:
            guard start.heldBall, start.ballX != nil,
                  step.target == .box || step.target == .home,
                  let destination = targetPosition(step.target, in: start) else { return nil }
            end.petX = destination
            end.ballX = destination
            end.heldBall = false
            duration = 2
        case .hop:
            guard step.target == .pet else { return nil }
            duration = 1.5
        case .rest:
            guard step.target == .home else { return nil }
            end.petX = 0.1
            if end.heldBall { end.ballX = end.petX }
            duration = 2
        case .spin, .bow:
            guard step.target == .pet else { return nil }
            duration = step.verb == .spin ? 2.4 : 2.8
        case .dig:
            guard step.target == .box else { return nil }
            end.petX = start.boxX
            if end.heldBall { end.ballX = end.petX }
            duration = 4
        }

        return StepMotion(
            verb: step.verb,
            start: start,
            end: end,
            duration: duration,
            event: "\(step.verb.rawValue) \(step.target.rawValue)"
        )
    }

    private static func targetPosition(_ target: TargetID, in state: WorldSnapshot) -> Double? {
        switch target {
        case .pet: state.petX
        case .ball: state.ballX
        case .box: state.boxX
        case .home: 0.1
        }
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    private static func lerp(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start + (end - start) * progress
    }
}
