import Foundation
import PetCore
import PetModel

struct Trial: Codable {
    var index: Int
    var scenario: String
    var snapshot: WorldSnapshot
    var result: PlanningResult?
    var accepted: Bool
    var executed: Bool
    var error: String?
    var finalSnapshot: WorldSnapshot
}

struct Report: Codable {
    var timestamp: Date
    var model: String
    var availability: String
    var contextSize: Int
    var trials: [Trial]
}

@main struct PetProbe {
    static func main() async throws {
        let arguments = CommandLine.arguments
        let count = arguments.firstIndex(of: "--count").flatMap {
            arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil
        } ?? 8
        let output = arguments.firstIndex(of: "--output").flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }
        let planner = ModelPlanner()
        print("model=SystemLanguageModel.default availability=\(planner.availability) context=\(planner.contextSize)")
        var trials: [Trial] = []
        let continuous = arguments.contains("--continuous")
        var continuousWorld = PetWorld()
        for index in 0..<max(1, min(count, 40)) {
            var world = continuous ? continuousWorld : PetWorld()
            let scenario: String
            if continuous {
                switch index {
                case 4: world.move(target: .box, to: 0.35)
                case 8: world.setBallPresent(false)
                case 12: world.setBallPresent(true)
                default: break
                }
                scenario = world.snapshot.ballX == nil ? "continuous_no_ball" : "continuous_play"
            } else { switch index % 4 {
            case 1:
                scenario = "ball_removed"
                world.setBallPresent(false)
            case 2:
                scenario = "holding_ball"
                try world.submit(plan: PetPlan(intent: "捡起球", steps: [PetStep(verb: .carry, target: .ball)]), revision: world.snapshot.revision)
                world.advance(seconds: 20)
            case 3:
                scenario = "continuity"
                try world.submit(plan: PetPlan(intent: "把球送到箱子", steps: [PetStep(verb: .carry, target: .ball), PetStep(verb: .drop, target: .box)]), revision: world.snapshot.revision)
                world.advance(seconds: 20)
                world.pet()
            default: scenario = "fresh"
            } }
            let snapshot = world.snapshot
            var trial = Trial(index: index, scenario: scenario, snapshot: snapshot, accepted: false, executed: false, finalSnapshot: snapshot)
            do {
                let result = try await planner.generate(snapshot: snapshot)
                trial.result = result
                try world.submit(plan: result.plan, revision: snapshot.revision)
                trial.accepted = true
                world.advance(seconds: 30)
                trial.executed = world.currentPlan == nil && world.snapshot.completedActivities.last == result.plan.intent
                print("\(index) \(scenario): accepted=\(trial.accepted) executed=\(trial.executed) seconds=\(String(format: "%.2f", result.elapsedSeconds)) plan=\(result.plan)")
            } catch {
                trial.error = String(describing: error)
                print("\(index) \(scenario): failed=\(error)")
            }
            trial.finalSnapshot = world.snapshot
            continuousWorld = world
            trials.append(trial)
        }
        let report = Report(timestamp: Date(), model: "SystemLanguageModel.default", availability: planner.availability, contextSize: planner.contextSize, trials: trials)
        if let output {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        print("accepted=\(trials.filter(\.accepted).count)/\(trials.count) executed=\(trials.filter(\.executed).count)/\(trials.count)")
        if !trials.allSatisfy({ $0.accepted && $0.executed }) { exit(1) }
    }
}
