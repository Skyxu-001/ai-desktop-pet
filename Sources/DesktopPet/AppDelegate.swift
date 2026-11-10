import AppKit
import Foundation
import ApplicationServices
import PetUI
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel!
    private var view: PetView!
    private var scene: PetScene!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var controller: PetController!
    private var transparent = false
    private var windowScale: CGFloat = 1
    private var pinItem: NSMenuItem?
    private var elapsed: Double = 0
    private var started = ProcessInfo.processInfo.systemUptime
    private var smokeStage = 0
    private var smokeReport: String?
    private var snapshotPath: String?
    private var smokeSeconds: Double = 8
    private var smokeChecks: [String: Bool] = [:]
    private var holdRequestCount = 0
    private var holdBallX: Double = 0.55
    private var systemEvents = false
    private var originalMousePoint: CGPoint?
    private var smokeFrame: NSRect = .zero
    private var windowDragCheckAt: Double = 0
    private var smokeHideCheckAt: Double = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        func option(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        smokeReport = option("--smoke-test")
        snapshotPath = option("--snapshot")
        smokeSeconds = option("--smoke-seconds").flatMap(Double.init) ?? 8
        let noModel = args.contains("--no-model")
        systemEvents = args.contains("--system-events")
        if smokeReport != nil && systemEvents {
            originalMousePoint = CGEvent(source: nil)?.location
            smokeChecks["accessibility_trusted"] = AXIsProcessTrusted()
        }
        let memoryURL = smokeReport == nil ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LocalDesktopPet/memory.json") : nil
        controller = PetController(modelEnabled: !noModel, memoryURL: memoryURL)
        scene = PetScene()
        scene.onInteract = { [weak self] in self?.controller.interact($0) }
        view = PetView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 30
        view.wantsLayer = true
        view.layer?.cornerRadius = 24
        view.layer?.masksToBounds = true
        view.presentScene(scene)
        panel = PetPanel(contentView: view)
        panel.delegate = self
        scene.onWindowDrag = { [weak self] event in self?.panel.performDrag(with: event) }
        scene.onHide = { [weak self] in self?.hidePet() }
        positionPanel()
        setupMenu()
        panel.orderFrontRegardless()
        started = ProcessInfo.processInfo.systemUptime
        timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "小狗的角落")
        let menu = NSMenu()
        add("显示小狗 / 回到屏幕角落", #selector(showPet), to: menu)
        add("藏起小狗", #selector(hidePet), to: menu)
        add("放到其他窗口后面", #selector(sendBehind), to: menu)
        pinItem = add("始终置顶", #selector(togglePinned), to: menu)
        let sizes = NSMenu()
        for (title, tag) in [("小号", 80), ("标准", 100), ("大号", 125)] {
            let item = add(title, #selector(changeSize), to: sizes)
            item.tag = tag
        }
        let sizeItem = NSMenuItem(title: "小狗活动区大小", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        add("暂停 / 继续", #selector(togglePause), to: menu)
        add("透明桌面模式", #selector(toggleTransparent), to: menu)
        menu.addItem(.separator())
        add("活动与模型状态…", #selector(showDiagnostics), to: menu)
        menu.addItem(.separator())
        let quit = add("退出小狗", #selector(quit), to: menu)
        quit.keyEquivalent = "q"
        statusItem.menu = menu
    }

    @discardableResult private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func positionPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let scale = min(windowScale, min(screen.width / 560, screen.height / 320))
        panel.setContentSize(NSSize(width: 520 * scale, height: 280 * scale))
        panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 20, y: screen.minY + 22))
    }

    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        elapsed = now - started
        controller.tick(now: now)
        scene.render(snapshot: controller.world.snapshot, step: controller.world.currentStep,
                     progress: controller.world.stepProgress, intent: controller.intention,
                     mode: controller.mode, time: now, expression: controller.expression)
        if smokeReport != nil { runSmoke() }
    }

    @objc private func showPet() {
        scene.cancelInteraction()
        positionPanel()
        controller.setHidden(false)
        view.isPaused = false
        panel.orderFrontRegardless()
    }
    @objc private func hidePet() {
        scene.cancelInteraction()
        controller.setHidden(true)
        view.isPaused = true
        panel.orderOut(nil)
    }
    @objc private func sendBehind() {
        panel.level = .normal
        pinItem?.state = .off
        panel.orderBack(nil)
    }
    @objc private func togglePinned(_ sender: NSMenuItem) {
        let pinned = panel.level != .floating
        panel.level = pinned ? .floating : .normal
        sender.state = pinned ? .on : .off
    }
    @objc private func changeSize(_ sender: NSMenuItem) {
        scene.cancelInteraction()
        windowScale = CGFloat(sender.tag) / 100
        positionPanel()
    }
    @objc private func togglePause() { controller.interact(.togglePaused) }
    @objc private func toggleTransparent(_ sender: NSMenuItem) {
        transparent.toggle()
        scene.setTransparent(transparent)
        panel.hasShadow = !transparent
        sender.state = transparent ? .on : .off
    }
    @objc private func showDiagnostics() {
        let alert = NSAlert()
        alert.messageText = "小狗现在的状态"
        alert.informativeText = controller.diagnostics
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        controller.shutdown()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        if let originalMousePoint { CGWarpMouseCursorPosition(originalMousePoint) }
    }

    private func runSmoke() {
        if elapsed >= 1, smokeStage == 0 {
            smokeFrame = panel.frame
            smokeChecks["normal_window_level"] = panel.level == .normal
            smokeChecks["compact_window"] = panel.frame.width * panel.frame.height <= 520 * 280
            smokeChecks["no_background_window_drag"] = !panel.isMovableByWindowBackground && !view.mouseDownCanMoveWindow
            if let point = scene.interactionPoint(for: .ball) {
                smokeObjectDrag(from: point, to: scene.point(for: .ball, at: 0.72))
            }
            smokeStage = 1
        }
        if elapsed >= 1.6, smokeStage == 1 {
            smokeChecks["ball_drag_through_window"] = abs((controller.world.snapshot.ballX ?? 0) - 0.72) < 0.015
            smokeChecks["ball_drag_keeps_window_still"] = panel.frame == smokeFrame
            let smallSize = NSMenuItem()
            smallSize.tag = 80
            changeSize(smallSize)
            smokeChecks["small_size_menu"] = abs(panel.frame.width - 416) < 1 && abs(panel.frame.height - 224) < 1
            smokeFrame = panel.frame
            if let point = scene.interactionPoint(for: .box) {
                smokeObjectDrag(from: point, to: scene.point(for: .box, at: 0.4))
            }
            smokeStage = 2
        }
        if elapsed >= 2.2, smokeStage == 2 {
            smokeChecks["box_drag_through_window"] = abs(controller.world.snapshot.boxX - 0.4) < 0.015
            smokeChecks["box_drag_keeps_window_still"] = panel.frame == smokeFrame
            if let point = scene.interactionPoint(for: .pet) { smokeClick(at: point) }
            smokeStage = 3
        }
        if elapsed >= 2.8, smokeStage == 3 {
            smokeChecks["pet_through_window"] = controller.world.snapshot.recentEvents.contains("petted")
            smokeClick(at: scene.ballTogglePoint)
            smokeStage = 4
        }
        if elapsed >= 3.4, smokeStage == 4 {
            smokeChecks["remove_ball_button"] = controller.world.snapshot.ballX == nil
            smokeClick(at: scene.pausePoint)
            smokeStage = 5
        }
        if elapsed >= 4, smokeStage == 5 {
            smokeChecks["pause_button"] = controller.world.isPaused
            smokeClick(at: scene.pausePoint)
            smokeStage = 6
        }
        if elapsed >= 4.6, smokeStage == 6 {
            smokeChecks["resume_button"] = !controller.world.isPaused
            smokeClick(at: scene.ballTogglePoint)
            smokeStage = 7
        }
        if elapsed >= 5.2, smokeStage == 7 {
            smokeChecks["restore_ball_button"] = controller.world.snapshot.ballX != nil
            if smokeSeconds >= 26, let point = scene.interactionPoint(for: .ball) {
                holdRequestCount = controller.requests
                holdBallX = controller.world.snapshot.ballX ?? 0.55
                smokeMouse(.leftMouseDown, at: point)
            }
            smokeStage = 8
        }
        if smokeSeconds >= 26, elapsed >= 21, smokeStage == 8 {
            smokeChecks["held_drag_blocks_new_inference"] = controller.requests == holdRequestCount
            smokeChecks["held_drag_keeps_ball_still"] = !controller.world.snapshot.heldBall && abs((controller.world.snapshot.ballX ?? 0) - holdBallX) < 0.015
            smokeMouse(.leftMouseUp, at: scene.point(for: .ball, at: holdBallX))
            smokeStage = 9
        }
        if smokeSeconds >= 26, elapsed >= 21.6, smokeStage == 9 {
            smokeChecks["release_preserves_ball_position"] = abs((controller.world.snapshot.ballX ?? 0) - holdBallX) < 0.015
            smokeStage = 10
        }
        if systemEvents, (smokeSeconds < 26 && elapsed >= 6 && smokeStage == 8) || (elapsed >= 22 && smokeStage == 10) {
            smokeFrame = panel.frame
            windowDragCheckAt = elapsed + 0.9
            smokeStage = 11
            smokeDragWindowHandle()
        }
        if smokeStage == 11, elapsed >= windowDragCheckAt {
            smokeChecks["handle_moves_window"] = abs(panel.frame.minX - (smokeFrame.minX - 70)) < 3
            let coveringWindow = NSWindow(contentRect: panel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            coveringWindow.isReleasedWhenClosed = false
            coveringWindow.level = .normal
            coveringWindow.orderFrontRegardless()
            sendBehind()
            smokeChecks["can_go_behind_normal_window"] = coveringWindow.orderedIndex < panel.orderedIndex
            coveringWindow.close()
            panel.orderFrontRegardless()
            smokeClick(at: scene.hidePoint)
            smokeHideCheckAt = elapsed + 0.3
            smokeStage = 12
        }
        if smokeStage == 12, elapsed >= smokeHideCheckAt {
            smokeChecks["hide_button"] = controller.hidden && !panel.isVisible
            showPet()
            smokeChecks["show_from_menu_restores_pet"] = !controller.hidden && panel.isVisible
            smokeStage = 13
        }
        guard elapsed >= smokeSeconds, let smokeReport else { return }
        self.smokeReport = nil
        do {
            if let snapshotPath { try saveSnapshot(to: snapshotPath) }
            if controller.modelEnabled { smokeChecks["accepted_live_model_plan"] = controller.acceptedPlans > 0 }
            let passed = smokeChecks.count >= 11 && smokeChecks.values.allSatisfy { $0 }
            let payload: [String: Any] = [
                "checksPassed": passed, "checks": smokeChecks,
                "eventRoute": systemEvents ? "CGEvent -> window server -> AppKit -> PetView -> PetScene" : "NSPanel.sendEvent -> PetView -> PetScene",
                "elapsedSeconds": elapsed, "stages": smokeStage,
                "windowWidth": panel.frame.width, "windowHeight": panel.frame.height,
                "requests": controller.requests, "acceptedPlans": controller.acceptedPlans,
                "discardedPlans": controller.discardedPlans, "timeouts": controller.timeouts,
                "completedActivities": controller.world.snapshot.completedActivities,
                "revision": controller.world.snapshot.revision,
                "ballPresent": controller.world.snapshot.ballX != nil,
                "paused": controller.world.isPaused,
                "diagnostics": controller.diagnostics
            ]
            try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: smokeReport), options: .atomic)
            print("APP_SMOKE_\(passed ? "OK" : "FAILED") \(smokeReport)")
            if !passed {
                controller.shutdown()
                if let originalMousePoint { CGWarpMouseCursorPosition(originalMousePoint) }
                exit(1)
            }
        } catch {
            fputs("APP_SMOKE_FAILED \(error)\n", stderr)
            controller.shutdown()
            if let originalMousePoint { CGWarpMouseCursorPosition(originalMousePoint) }
            exit(1)
        }
        quit()
    }

    private func smokeClick(at point: CGPoint) {
        smokeMouse(.leftMouseDown, at: point)
        smokeMouse(.leftMouseUp, at: point)
    }

    private func smokeObjectDrag(from start: CGPoint, to end: CGPoint) {
        if systemEvents {
            let points = [start, end, end].map { scenePoint in
                let windowPoint = view.convert(scene.convertPoint(toView: scenePoint), to: nil)
                let point = panel.convertPoint(toScreen: windowPoint)
                return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
            }
            Task.detached {
                for (type, point) in zip([CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp], points) {
                    try? await Task.sleep(for: .milliseconds(120))
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                }
            }
        } else {
            smokeMouse(.leftMouseDown, at: start)
            smokeMouse(.leftMouseDragged, at: end)
            smokeMouse(.leftMouseUp, at: end)
        }
    }

    private func smokeDragWindowHandle() {
        let point = view.convert(scene.convertPoint(toView: scene.windowHandlePoint), to: nil)
        let screenPoint = panel.convertPoint(toScreen: point)
        let height = NSScreen.screens.first?.frame.height ?? 0
        let start = CGPoint(x: screenPoint.x, y: height - screenPoint.y)
        let end = CGPoint(x: start.x - 70, y: start.y - 20)
        // Native performDrag runs a tracking loop. Post the release independently
        // so the smoke timer is never responsible for releasing a blocked loop.
        Task.detached {
            for (type, point) in [(CGEventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
                try? await Task.sleep(for: .milliseconds(150))
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
    }

    private func smokeMouse(_ type: NSEvent.EventType, at scenePoint: CGPoint) {
        let point = view.convert(scene.convertPoint(toView: scenePoint), to: nil)
        if systemEvents {
            let screenPoint = panel.convertPoint(toScreen: point)
            let desktopHeight = NSScreen.screens.first?.frame.height ?? 0
            let quartzPoint = CGPoint(x: screenPoint.x, y: desktopHeight - screenPoint.y)
            let eventType: CGEventType
            switch type {
            case .leftMouseDown: eventType = .leftMouseDown
            case .leftMouseDragged: eventType = .leftMouseDragged
            case .leftMouseUp: eventType = .leftMouseUp
            default: return
            }
            CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: quartzPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
        } else {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: elapsed,
                                                windowNumber: panel.windowNumber, context: nil,
                                                eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            panel.sendEvent(event)
        }
    }

    private func saveSnapshot(to path: String) throws {
        guard let texture = view.texture(from: scene) else {
            throw NSError(domain: "PetSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "场景纹理导出失败"])
        }
        let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PetSnapshot", code: 2)
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
