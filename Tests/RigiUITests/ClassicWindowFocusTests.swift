import AppKit
import XCTest
import RigiUI

@MainActor
final class ClassicWindowFocusTests: XCTestCase {
    func testBorderlessDefaultsToAppKitGetters() {
        _ = NSApplication.shared
        let window = makeClassicWindow(styleMask: [.borderless])
        defer { window.close() }

        XCTAssertEqual(window.borderlessFocusPolicy, .appKitDefault)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
    }

    func testDocumentPolicyOptsInBorderlessWindow() {
        _ = NSApplication.shared
        let window = makeClassicWindow(styleMask: [.borderless])
        defer { window.close() }

        window.borderlessFocusPolicy = .document

        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
    }

    func testDocumentPolicyCanToggleBackToDefault() {
        _ = NSApplication.shared
        let window = makeClassicWindow(styleMask: [.borderless])
        defer { window.close() }

        window.borderlessFocusPolicy = .document
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
        window.borderlessFocusPolicy = .appKitDefault

        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
    }

    func testTitledWindowBehaviorMatchesPlainNSWindowForBothPolicies() {
        _ = NSApplication.shared
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let classic = makeClassicWindow(styleMask: styleMask)
        let plain = NSWindow(contentRect: contentRect, styleMask: styleMask,
                             backing: .buffered, defer: false)
        plain.isReleasedWhenClosed = false
        defer {
            classic.close()
            plain.close()
        }

        XCTAssertTrue(plain.canBecomeKey)
        XCTAssertTrue(plain.canBecomeMain)
        classic.borderlessFocusPolicy = .appKitDefault
        XCTAssertEqual(classic.canBecomeKey, plain.canBecomeKey)
        XCTAssertEqual(classic.canBecomeMain, plain.canBecomeMain)

        classic.borderlessFocusPolicy = .document
        XCTAssertEqual(classic.canBecomeKey, plain.canBecomeKey)
        XCTAssertEqual(classic.canBecomeMain, plain.canBecomeMain)
    }

    func testUntitledModifiersKeepAppKitDefaultAndPermitDocumentOptIn() {
        _ = NSApplication.shared
        let styles: [NSWindow.StyleMask] = [[.closable], [.resizable], [.closable, .resizable]]
        for styleMask in styles {
            let classic = makeClassicWindow(styleMask: styleMask)
            let plain = NSWindow(contentRect: contentRect, styleMask: styleMask,
                                 backing: .buffered, defer: false)
            plain.isReleasedWhenClosed = false
            defer {
                classic.close()
                plain.close()
            }

            let originalStyle = classic.styleMask
            XCTAssertEqual(classic.canBecomeKey, plain.canBecomeKey)
            XCTAssertEqual(classic.canBecomeMain, plain.canBecomeMain)

            classic.borderlessFocusPolicy = .document
            XCTAssertTrue(classic.canBecomeKey)
            XCTAssertTrue(classic.canBecomeMain)
            XCTAssertEqual(classic.styleMask, originalStyle)

            classic.borderlessFocusPolicy = .appKitDefault
            XCTAssertEqual(classic.canBecomeKey, plain.canBecomeKey)
            XCTAssertEqual(classic.canBecomeMain, plain.canBecomeMain)
        }
    }

    private var contentRect: NSRect {
        NSRect(x: 0, y: 0, width: 320, height: 240)
    }

    private func makeClassicWindow(styleMask: NSWindow.StyleMask) -> ClassicWindow {
        let window = ClassicWindow(contentRect: contentRect, styleMask: styleMask,
                                   backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}
