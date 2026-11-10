import Foundation
import PetCore
import PetModel
import PetRuntime
import PetUI

@MainActor
final class PetController {
    private(set) var world = PetWorld()
    private var gate = InferenceGate()
    private let planner = ModelPlanner()
    private var task: Task<Void, Never>?
    private let store: MemoryStore?
    private var memory: PetMemory
    private var lastTick: Double?
    private(set) var intention = "今天想玩点什么呢"
    private(set) var expression: PetExpression? = PetExpression(thought: "嗨，我在这儿陪你", emoji: "🐶", doodle: " / \\__\n(    @\\___\n /         O")
    private(set) var lastDiagnostic = "等待第一次端侧决策"
    private(set) var lastResult: PlanningResult?
    private(set) var requests = 0
    private(set) var acceptedPlans = 0
    private(set) var discardedPlans = 0
    private(set) var timeouts = 0
    private(set) var hidden = false
    private var dragging = false
    private var basic = true
    private var reactionUntil: Double = 0
    private var lastReactionKind = ""
    private var nextBasicActivity = ProcessInfo.processInfo.systemUptime + 10
    private var lastBasicVerb: ActionVerb?
    let modelEnabled: Bool

    init(modelEnabled: Bool, memoryURL: URL?) {
        self.modelEnabled = modelEnabled
        store = memoryURL.map(MemoryStore.init)
        memory = store?.load() ?? PetMemory()
        world.restoreCompletedActivities(memory.completedActivities)
    }

    var mode: PetDisplayMode {
        if world.isPaused || hidden { return .paused }
        if gate.active != nil && !gate.expired { return .thinking }
        if world.currentStep?.verb == .rest { return .resting }
        if world.currentPlan != nil { return basic ? .basic : .playing }
        return basic ? .basic : .idle
    }

    func tick(now: Double) {
        let delta = min(0.1, max(0, now - (lastTick ?? now)))
        lastTick = now
        if hidden { return }
        world.advance(seconds: delta)
        if world.snapshot.completedActivities != memory.completedActivities {
            memory.completedActivities = world.snapshot.completedActivities
            persist()
        }
        if gate.expire(now: now) {
            timeouts += 1
            task?.cancel()
            basic = true
            intention = "先歇一会儿"
            expression = PetExpression(thought: intention, emoji: "🌿", doodle: " z Z\n( -.- )\n /   \\")
            lastDiagnostic = "推理已超时；结果将丢弃，旧请求结束前不启动新请求"
        }
        guard world.currentPlan == nil, !world.isPaused, !dragging, now >= reactionUntil else { return }
        guard modelEnabled, let ticket = gate.begin(now: now, revision: world.snapshot.revision) else {
            if basic && gate.active == nil { playBasicActivity(now: now) }
            return
        }
        let snapshot = world.snapshot
        requests += 1
        task = Task { [weak self, planner] in
            do {
                try Task.checkCancellation()
                let result = try await planner.generate(snapshot: snapshot)
                guard let self else { return }
                var candidate = self.world
                do {
                    try candidate.submit(plan: result.plan, revision: ticket.revision)
                } catch {
                    self.finishFailure(ticket, error: error)
                    return
                }
                if self.gate.finish(ticket, currentRevision: self.world.snapshot.revision,
                                    now: ProcessInfo.processInfo.systemUptime, succeeded: true) {
                    self.world = candidate
                    self.acceptedPlans += 1
                    self.lastResult = result
                    self.intention = result.plan.intent
                    self.expression = result.plan.expression ?? PetExpression(
                        thought: result.plan.intent, emoji: self.expression?.emoji ?? "🐾",
                        doodle: self.expression?.doodle ?? " / \\__\n(    @\\___\n /         O")
                    self.lastReactionKind = ""
                    self.basic = false
                    self.lastDiagnostic = String(format: "端侧模型 · %.2f 秒 · 输入 %d / 输出 %d tokens", result.elapsedSeconds, result.inputTokens, result.outputTokens)
                    let fallback = result.expressionFallbackFields ?? []
                    self.lastDiagnostic += fallback.isEmpty ? "\n短句与 emoji：端侧生成" : "\n表达使用备用内容：\(fallback.joined(separator: ", "))"
                    self.lastDiagnostic += "\nASCII：模型选择参数，程序组合绘制"
                    if let error = result.expressionError {
                        self.lastDiagnostic += "\n表达调用失败，已保留合法动作：\(error)\nToken 统计只含成功响应。"
                    }
                } else {
                    self.discardedPlans += 1
                }
                self.task = nil
            } catch {
                self?.finishFailure(ticket, error: error)
            }
        }
    }

    private func finishFailure(_ ticket: InferenceTicket, error: Error) {
        let canceled = error is CancellationError || ticket.revision != world.snapshot.revision
        _ = gate.finish(ticket, currentRevision: world.snapshot.revision,
                        now: ProcessInfo.processInfo.systemUptime, succeeded: canceled)
        discardedPlans += 1
        task = nil
        if !canceled {
            basic = true
            intention = "先自己待一会儿"
            expression = PetExpression(thought: intention, emoji: "🌿", doodle: " .  .\n( o.o )\n /   \\")
            lastDiagnostic = "基础活动：\(error.localizedDescription)"
        }
    }

    func interact(_ interaction: PetInteraction) {
        gate.invalidate()
        task?.cancel()
        let now = ProcessInfo.processInfo.systemUptime
        reactionUntil = now + 1.5
        switch interaction {
        case .dragBegan:
            dragging = true
            gate.setSuspended(hidden || world.isPaused || dragging)
        case .dragEnded:
            dragging = false
            lastReactionKind = ""
            gate.setSuspended(hidden || world.isPaused || dragging)
        case .move(let target, let x):
            world.move(target: target, to: x)
            let kind = target.rawValue
            if lastReactionKind != kind {
                react(target == .ball ? ["咦，球会飞了！", "等一下，我的小行星", "这球有自己的主意"] : ["纸箱搬家啦", "秘密基地挪窝了", "这个位置，适合探险"], emoji: target == .ball ? "🎾" : "📦")
                lastReactionKind = kind
            }
        case .pet:
            world.pet()
            memory.petCount = min(1_000_000, memory.petCount + 1)
            persist()
            let verb: ActionVerb = [.hop, .spin, .bow].randomElement() ?? .hop
            let reaction = PetPlan(intent: "回应摸摸", steps: [PetStep(verb: verb, target: .pet)])
            if !world.isPaused { try? world.submit(plan: reaction, revision: world.snapshot.revision) }
            react(["再摸摸我～", "尾巴已经停不下来啦", "嘿嘿，今天也喜欢你", "摸摸电量 +1", "这个位置刚刚好"], emoji: ["💛", "🥰", "🐾"].randomElement() ?? "💛")
            basic = true
            lastDiagnostic = "抚摸反射：程序随机选择跳跃、转圈或伸懒腰；自主活动由端侧模型决定"
        case .toggleBall:
            let present = world.snapshot.ballX != nil
            world.setBallPresent(!present)
            react(present ? ["球呢？鼻子雷达启动", "那就找点别的乐子", "消失的球，未解之谜"] : ["我的小行星回来啦", "球球，你去旅行了吗", "好耶，又能玩了"], emoji: present ? "🔎" : "🎾")
        case .togglePaused:
            world.setPaused(!world.isPaused)
            gate.setSuspended(world.isPaused || hidden || dragging)
            intention = world.isPaused ? "陪你安静一会儿" : "继续过我的小日子"
            expression = PetExpression(thought: intention, emoji: world.isPaused ? "🌙" : "🐾", doodle: world.isPaused ? "z Z z\n /)__/ )\n( - . -)" : " / \\__\n(    @\\___\n /         O")
        }
    }

    private func react(_ choices: [String], emoji: String) {
        let fresh = choices.filter { $0 != intention }
        intention = fresh.randomElement() ?? choices[0]
        expression = PetExpression(thought: intention, emoji: emoji,
                                   doodle: [" / \\__\n(    @\\___\n /         O", " /)__/ )\n( ^ . ^)\n / >  < ", "  __\n (oo)\n /|  |\\"].randomElement() ?? "(o.o)")
    }

    private func playBasicActivity(now: Double) {
        guard now >= nextBasicActivity else { return }
        nextBasicActivity = now + Double.random(in: 12...18)
        let choices: [(ActionVerb, TargetID, String)] = [
            (.spin, .pet, "自己追一圈小尾巴"), (.bow, .pet, "伸个大大的懒腰"),
            (.hop, .pet, "地板好像有弹簧"), (.dig, .box, "给纸箱挠挠痒"),
            (.push, .ball, "球球，往前走啦"), (.drop, .home, "把球安顿在毯子上")
        ]
        for (verb, target, thought) in choices.shuffled() where verb != lastBasicVerb {
            var candidate = world
            let plan = PetPlan(intent: thought, steps: [PetStep(verb: verb, target: target)])
            guard (try? candidate.submit(plan: plan, revision: world.snapshot.revision)) != nil else { continue }
            world = candidate
            lastBasicVerb = verb
            react([thought], emoji: "🐾")
            return
        }
    }

    func setHidden(_ value: Bool) {
        guard hidden != value else { return }
        hidden = value
        if value {
            dragging = false
            world.interruptForHiding()
        }
        gate.setSuspended(hidden || world.isPaused || dragging)
        gate.invalidate()
        task?.cancel()
        lastTick = nil
    }

    func shutdown() {
        gate.setSuspended(true)
        task?.cancel()
        persist()
    }

    private func persist() {
        do { try store?.save(memory) }
        catch { lastDiagnostic = "本地记忆保存失败：\(error.localizedDescription)" }
    }

    var diagnostics: String {
        """
        \(lastDiagnostic)

        模型：SystemLanguageModel.default
        可用性：\(planner.availability)
        上下文：\(planner.contextSize) tokens
        请求 / 接纳 / 丢弃 / 超时：\(requests) / \(acceptedPlans) / \(discardedPlans) / \(timeouts)
        最近决策来源：\(basic ? "基础行为或抚摸反射" : "端侧模型")
        记住的活动：\(memory.completedActivities.count)；摸摸次数：\(memory.petCount)
        \(modelEnabled ? "" : "本次运行已关闭模型，仅测试画面与交互。")
        """
    }
}
