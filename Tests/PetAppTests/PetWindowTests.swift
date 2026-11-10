import AppKit
import SpriteKit
import XCTest
@testable import DesktopPet

final class PetWindowTests: XCTestCase {
    func testLaunchedWindowDoesNotStealObjectDragsOrFloatAboveApps() async {
        await MainActor.run {
            _ = NSApplication.shared
            let delegate = AppDelegate()
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            guard let window = NSApp.windows.first(where: { $0.title == "小狗的角落" }) else {
                XCTFail("missing pet window"); return
            }
            XCTAssertFalse(window.isMovableByWindowBackground)
            XCTAssertEqual(window.level, .normal)
            XCTAssertLessThanOrEqual(window.frame.width * window.frame.height, 520 * 280)
            XCTAssertEqual(window.contentView?.mouseDownCanMoveWindow, false)
            XCTAssertEqual(window.contentView?.acceptsFirstMouse(for: nil), true)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            window.isReleasedWhenClosed = false
            window.close()
        }
    }
}
