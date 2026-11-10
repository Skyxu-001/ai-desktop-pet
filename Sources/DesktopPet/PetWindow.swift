import AppKit
import SpriteKit

@MainActor
final class PetView: SKView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }

    init(contentView: PetView) {
        super.init(contentRect: contentView.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "小狗的角落"
        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .normal
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces]
        isReleasedWhenClosed = false
    }
}
