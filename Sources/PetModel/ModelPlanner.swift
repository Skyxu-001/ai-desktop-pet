import Foundation
import FoundationModels
import PetCore

public struct PlanningResult: Codable, Sendable {
    public let plan: PetPlan
    public let elapsedSeconds: Double
    public let promptTokens: Int
    public let schemaTokens: Int
    public let instructionTokens: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let contextSize: Int
    public let prompt: String
    public let rawOutput: String
    public let decisionCount: Int?
    public let expressionFallbackFields: [String]?
    public let expressionAdjustedFields: [String]?
    public let doodleSource: String?
    public let expressionError: String?
}

public enum PlanningError: Error, LocalizedError {
    case unavailable(String)
    case budgetExceeded(Int, Int)
    case invalidAction
    case timedOut
    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "本地模型尚未就绪：\(reason)"
        case .budgetExceeded(let used, let limit): "上下文预算不足：\(used) / \(limit)"
        case .invalidAction: "模型返回的动作不属于当前可执行集合"
        case .timedOut: "这次活动想得太久，稍后再试"
        }
    }
}

struct DecisionRequest: Sendable {
    let index: Int
    let snapshot: WorldSnapshot
    let actions: [String]
    let prompt: String
    var drawings: [DoodleDrawing] = []
    var accents: [DoodleAccent] = []
    var moods: [DoodleMood] = []
}

struct ModelDecision: Sendable {
    var action: String = ""
    var thought: String = ""
    var emoji: String = ""
    var drawing: DoodleDrawing?
    var accent: DoodleAccent?
    var mood: DoodleMood?
    var promptTokens: Int = 0
    var schemaTokens: Int = 0
    var instructionTokens: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var contextSize: Int = 4096
    var rawOutput: String = ""
}

public struct ModelPlanner: Sendable {
    public init() {}

    static func candidates(for snapshot: WorldSnapshot) -> [GeneratedAction] {
        let executed = Set(snapshot.recentEvents.filter { event in
            GeneratedAction.allCases.contains { $0.event == event }
        }.suffix(6))
        return GeneratedAction.allCases.filter { action in
            guard !executed.contains(action.event) else { return false }
            var copy = PetWorld(snapshot: snapshot)
            return (try? copy.submit(
                plan: PetPlan(intent: "规划校验", steps: [action.step]),
                revision: snapshot.revision
            )) != nil
        }
    }

    public var availability: String { String(describing: SystemLanguageModel.default.availability) }
    public var isAvailable: Bool { SystemLanguageModel.default.isAvailable }
    public var contextSize: Int { SystemLanguageModel.default.contextSize }

    public func generate(snapshot: WorldSnapshot) async throws -> PlanningResult {
        try Task.checkCancellation()
        guard SystemLanguageModel.default.isAvailable else { throw PlanningError.unavailable(availability) }
        return try await generate(snapshot: snapshot, respond: Self.respond)
    }

    // Action failures invalidate the activity. The final expression call has no action authority.
    func generate(
        snapshot: WorldSnapshot,
        respond: @Sendable (DecisionRequest) async throws -> ModelDecision
    ) async throws -> PlanningResult {
        try Task.checkCancellation()
        let started = ContinuousClock.now
        var simulated = PetWorld(snapshot: snapshot)
        var selected: [GeneratedAction] = []
        var decisions: [ModelDecision] = []
        var prompts: [String] = []
        var outputs: [String] = []
        let drawings = Array(DoodleDrawing.allCases.filter { snapshot.ballX != nil || $0 != .ball }.shuffled().prefix(3))
        let accents = Array(DoodleAccent.allCases.shuffled().prefix(2))
        let moods = DoodleMood.allCases.shuffled()

        for index in 0..<2 {
            try Task.checkCancellation()
            let available = Self.candidates(for: simulated.snapshot).filter { !selected.contains($0) }.shuffled()
            let actions = available.map(\.rawValue) + (index > 0 ? ["stop"] : [])
            guard !actions.isEmpty else { throw PlanningError.invalidAction }
            let prompt = """
            Ball: \(simulated.snapshot.ballX == nil ? "absent" : "present"); held: \(simulated.snapshot.heldBall).
            The puppy, cardboard box and home mat are present.
            Recent actual actions: \(snapshot.recentEvents.suffix(6).joined(separator: "; "))
            Past activity titles (not exact action facts): \(snapshot.completedActivities.suffix(3).map { String($0.prefix(40)) }.joined(separator: "; ")). Try a different idea.
            Selected actions simulated in this state: \(selected.map(\.rawValue).joined(separator: ", ")).
            \(index == 0 ? "Choose an interesting first action and a picture composition." : "Choose a related second action, or stop if the activity is complete.")
            """
            let request = DecisionRequest(index: index, snapshot: simulated.snapshot, actions: actions, prompt: prompt,
                                          drawings: index == 0 ? drawings : [], accents: index == 0 ? accents : [], moods: index == 0 ? moods : [])
            prompts.append("ACTION \(index + 1)\n\(prompt)\nChoices: \(actions.joined(separator: ", "))\nDrawing choices: \(request.drawings.map(\.rawValue)); accents: \(request.accents.map(\.rawValue)); moods: \(request.moods.map(\.rawValue))")
            let decision = try await respond(request)
            try Task.checkCancellation()
            guard Self.seconds(since: started) < 20 else { throw PlanningError.timedOut }
            decisions.append(decision)
            outputs.append("ACTION \(index + 1)\n\(decision.rawOutput)")
            guard actions.contains(decision.action) else { throw PlanningError.invalidAction }
            if decision.action == "stop" { break }
            guard let action = GeneratedAction(rawValue: decision.action) else { throw PlanningError.invalidAction }
            try simulated.submit(plan: PetPlan(intent: "规划校验", steps: [action.step]), revision: simulated.snapshot.revision)
            simulated.advance(seconds: 30)
            guard simulated.currentPlan == nil else { throw PlanningError.invalidAction }
            simulated.restoreCompletedActivities(snapshot.completedActivities)
            selected.append(action)
        }

        guard let first = decisions.first, let firstAction = selected.first else { throw PlanningError.invalidAction }
        var validation = PetWorld(snapshot: snapshot)
        try validation.submit(plan: PetPlan(intent: firstAction.label, steps: selected.map(\.step)), revision: snapshot.revision)
        let expressionPrompt = """
        小狗接下来计划按顺序做：\(selected.map(\.label).joined(separator: "，然后"))。
        球目前\(snapshot.ballX == nil ? "不在场" : "在场")。这里只需要描述这些动作，用8至16字简体中文说一句俏皮的打算，再给一个emoji。
        """
        prompts.append("EXPRESSION\n\(expressionPrompt)")
        var combined = first
        combined.thought = ""
        combined.emoji = ""
        var expressionError: String?
        do {
            try Task.checkCancellation()
            let expression = try await respond(DecisionRequest(index: 2, snapshot: snapshot, actions: [], prompt: expressionPrompt))
            try Task.checkCancellation()
            combined.thought = expression.thought
            combined.emoji = expression.emoji
            decisions.append(expression)
            outputs.append("EXPRESSION\n\(expression.rawOutput)")
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            expressionError = String(String(describing: error).prefix(240))
            outputs.append("EXPRESSION ERROR\n\(expressionError!)")
            prompts.append("EXPRESSION ERROR: \(expressionError!)")
        }
        try Task.checkCancellation()
        guard Self.seconds(since: started) < 20 else { throw PlanningError.timedOut }
        let expression = Self.sanitizeExpression(combined, fallbackThought: firstAction.label)
        let plan = PetPlan(intent: expression.value.thought, steps: selected.map(\.step), expression: expression.value)
        var finalValidation = PetWorld(snapshot: snapshot)
        try finalValidation.submit(plan: plan, revision: snapshot.revision)
        return PlanningResult(
            plan: plan, elapsedSeconds: Self.seconds(since: started),
            promptTokens: decisions.reduce(0) { $0 + $1.promptTokens },
            schemaTokens: decisions.reduce(0) { $0 + $1.schemaTokens },
            instructionTokens: decisions.reduce(0) { $0 + $1.instructionTokens },
            inputTokens: decisions.reduce(0) { $0 + $1.inputTokens },
            outputTokens: decisions.reduce(0) { $0 + $1.outputTokens },
            contextSize: first.contextSize, prompt: prompts.joined(separator: "\n\n"),
            rawOutput: outputs.joined(separator: "\n\n"), decisionCount: 3,
            expressionFallbackFields: expression.fallback, expressionAdjustedFields: expression.adjusted,
            doodleSource: expression.fallback.contains("doodle") ? "fallback" : "composed", expressionError: expressionError
        )
    }

    private static func respond(to request: DecisionRequest) async throws -> ModelDecision {
        try Task.checkCancellation()
        let model = SystemLanguageModel.default
        let expressionOnly = request.index == 2
        var properties: [DynamicGenerationSchema.Property]
        if expressionOnly {
            properties = [
                .init(name: "thought", description: "简体中文短句，8至16字，与计划动作相符", schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "emoji", description: "一个表达心情的emoji", schema: DynamicGenerationSchema(type: String.self))
            ]
        } else {
            properties = [.init(name: "action", description: "Select one executable action", schema: DynamicGenerationSchema(name: "Action", anyOf: request.actions))]
            if request.index == 0 {
                properties += [
                    .init(name: "drawing", description: "Choose the picture subject", schema: DynamicGenerationSchema(name: "Drawing", anyOf: request.drawings.map(\.rawValue))),
                    .init(name: "accent", description: "Choose a picture ornament", schema: DynamicGenerationSchema(name: "Accent", anyOf: request.accents.map(\.rawValue))),
                    .init(name: "mood", description: "Choose a picture expression", schema: DynamicGenerationSchema(name: "Mood", anyOf: request.moods.map(\.rawValue)))
                ]
            }
        }
        let schema = try GenerationSchema(root: DynamicGenerationSchema(name: expressionOnly ? "Expression" : "Decision", properties: properties), dependencies: [])
        let instructions = Instructions(expressionOnly ? Self.expressionInstructions : Self.actionInstructions)
        let maximumResponseTokens = expressionOnly ? 96 : (request.index == 0 ? 96 : 40)
        let promptTokens = try await model.tokenCount(for: Prompt(request.prompt))
        let instructionTokens = try await model.tokenCount(for: instructions)
        let schemaTokens = try await model.tokenCount(for: schema)
        let needed = promptTokens + instructionTokens + schemaTokens + maximumResponseTokens + 768
        guard needed <= model.contextSize else { throw PlanningError.budgetExceeded(needed, model.contextSize) }
        try Task.checkCancellation()
        let session = LanguageModelSession(model: model, instructions: instructions)
        session.transcriptErrorHandlingPolicy = .revertTranscript
        let response = try await session.respond(to: request.prompt, schema: schema, options: GenerationOptions(temperature: 0.8, maximumResponseTokens: maximumResponseTokens))
        try Task.checkCancellation()
        let action: String = expressionOnly ? "" : try response.content.value(forProperty: "action")
        let thought: String = expressionOnly ? try response.content.value(forProperty: "thought") : ""
        let emoji: String = expressionOnly ? try response.content.value(forProperty: "emoji") : ""
        let drawing: String = request.index == 0 ? try response.content.value(forProperty: "drawing") : ""
        let accent: String = request.index == 0 ? try response.content.value(forProperty: "accent") : ""
        let mood: String = request.index == 0 ? try response.content.value(forProperty: "mood") : ""
        return ModelDecision(action: action, thought: thought, emoji: emoji,
            drawing: DoodleDrawing(rawValue: drawing), accent: DoodleAccent(rawValue: accent), mood: DoodleMood(rawValue: mood),
            promptTokens: promptTokens, schemaTokens: schemaTokens, instructionTokens: instructionTokens,
            inputTokens: response.usage.input.totalTokenCount, outputTokens: response.usage.output.totalTokenCount,
            contextSize: model.contextSize, rawOutput: response.rawContent.jsonString)
    }

    private static let actionInstructions = """
    Choose a legal action for a curious desktop puppy. Use the actual world and recent actions.
    Alternate toy play, movement, exploration and rest. Prefer a related second action to make a short activity.
    A picture is a playful decoration: select the subject, ornament and mood from their enums.
    """
    private static let expressionInstructions = """
    你是可爱的小狗。只用简体中文，写一句8至16字的俏皮打算和一个emoji。
    严格围绕给出的动作和现有道具，不添加新的动作或物品，不说已经完成。
    """

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    private static func sanitizeExpression(_ decision: ModelDecision, fallbackThought: String) -> (value: PetExpression, fallback: [String], adjusted: [String]) {
        var fallback: [String] = []
        var adjusted: [String] = []
        let cleanThought = String(decision.thought.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: false
            default: true
            }
        }).trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredThought = cleanThought.count > 24 ? String(cleanThought.prefix(24)) + "…" : cleanThought
        let hasChinese = filteredThought.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let thought = hasChinese ? filteredThought : ""
        let emoji = String(decision.emoji.filter { character in
            character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation || (scalar.value > 0x7F && scalar.properties.isEmoji)
            } && !character.unicodeScalars.contains { scalar in
                scalar.properties.generalCategory == .control ||
                (scalar.properties.generalCategory == .format && scalar.value != 0x200D)
            }
        }.prefix(3))
        let doodle = DoodleRenderer.render(drawing: decision.drawing ?? .puppy, accent: decision.accent ?? .dots, mood: decision.mood ?? .curious)
        if decision.drawing == nil || decision.accent == nil || decision.mood == nil { fallback.append("doodle") }
        for (field, original, filtered) in [("thought", decision.thought, thought), ("emoji", decision.emoji, emoji)] {
            if filtered.isEmpty { fallback.append(field) }
            else if original != filtered { adjusted.append(field) }
        }
        return (
            PetExpression(
                thought: thought.isEmpty ? fallbackThought : thought,
                emoji: emoji.isEmpty ? "🐾" : emoji,
                doodle: doodle
            ), fallback, adjusted
        )
    }
}

enum GeneratedAction: String, CaseIterable, Sendable {
    case lookAtBall, approachBall, pushBall, pickUpBall, placeBallInBox, placeBallAtHome
    case lookAtBox, approachBox, goHome, lookAtUser, hop, rest, spinAround, stretch, digInBox
    var event: String { "\(step.verb.rawValue) \(step.target.rawValue)" }
    var label: String {
        switch self {
        case .lookAtBall: "想仔细观察一下球"
        case .approachBall: "想去球旁边转转"
        case .pushBall: "试试让球滚起来"
        case .pickUpBall: "准备叼起我的球"
        case .placeBallInBox: "想给球找个纸箱窝"
        case .placeBallAtHome: "想带球去小毯子"
        case .lookAtBox: "想观察纸箱的秘密"
        case .approachBox: "打算去纸箱边探险"
        case .goHome: "想回小毯子歇一会"
        case .lookAtUser: "想和你交换个眼神"
        case .hop: "想给自己加一点弹力"
        case .rest: "准备打个小盹"
        case .spinAround: "想转个小圈庆祝一下"
        case .stretch: "想把懒腰伸到天边"
        case .digInBox: "准备在纸箱边刨一刨"
        }
    }
    var step: PetStep {
        switch self {
        case .lookAtBall: PetStep(verb: .look, target: .ball)
        case .approachBall: PetStep(verb: .approach, target: .ball)
        case .pushBall: PetStep(verb: .push, target: .ball)
        case .pickUpBall: PetStep(verb: .carry, target: .ball)
        case .placeBallInBox: PetStep(verb: .drop, target: .box)
        case .placeBallAtHome: PetStep(verb: .drop, target: .home)
        case .lookAtBox: PetStep(verb: .look, target: .box)
        case .approachBox: PetStep(verb: .approach, target: .box)
        case .goHome: PetStep(verb: .approach, target: .home)
        case .lookAtUser: PetStep(verb: .look, target: .pet)
        case .hop: PetStep(verb: .hop, target: .pet)
        case .rest: PetStep(verb: .rest, target: .home)
        case .spinAround: PetStep(verb: .spin, target: .pet)
        case .stretch: PetStep(verb: .bow, target: .pet)
        case .digInBox: PetStep(verb: .dig, target: .box)
        }
    }
}
