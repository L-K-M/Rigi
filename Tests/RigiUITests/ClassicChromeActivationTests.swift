import AppKit
import XCTest
@testable import RigiUI

@MainActor
final class ClassicChromeActivationTests: XCTestCase {
    func testActivationInvalidatesChromeButNotDocumentViews() {
        _ = NSApplication.shared
        let window = ClassicWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        window.contentView = root
        let container = DisplayProbe(frame: NSRect(x: 0, y: 50, width: 500, height: 350))
        let document = DisplayProbe(frame: container.bounds)
        container.addSubview(document)
        root.addSubview(container)
        let chrome = ChromeProbe(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        root.addSubview(chrome)
        window.orderFrontRegardless()
        window.displayIfNeeded()

        for notification in [NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
                             NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            container.invalidations = 0
            document.invalidations = 0
            chrome.invalidations = 0
            NotificationCenter.default.post(name: notification, object: window)

            XCTAssertEqual(container.invalidations, 0)
            XCTAssertEqual(document.invalidations, 0)
            XCTAssertGreaterThan(chrome.invalidations, 0)
        }
    }

    func testActivationDependentControlsParticipateInRedraw() {
        for view: NSView in [ClassicToolGrid(), ClassicColorPair(), ClassicPopUpButton()] {
            XCTAssertTrue(view is any ClassicChromeDrawing,
                          "\(type(of: view)) must update its active colors")
        }
    }
}

@MainActor
private class DisplayProbe: NSView {
    var invalidations = 0

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if newValue { invalidations += 1 }
            super.needsDisplay = newValue
        }
    }
}

@MainActor
private final class ChromeProbe: DisplayProbe, ClassicChromeDrawing {}
