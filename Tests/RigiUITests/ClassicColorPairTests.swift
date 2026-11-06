import AppKit
import XCTest

@testable import RigiUI

@MainActor
final class ClassicColorPairTests: XCTestCase {
    func testEachPartHasItsOwnTargetAndTheForegroundWinsTheOverlap() {
        let layout = ClassicColorPairLayout()

        XCTAssertEqual(layout.part(at: CGPoint(x: 8, y: 8)), .foreground)
        XCTAssertEqual(layout.part(at: CGPoint(x: 38, y: 34)), .background)
        // Where the squares overlap, the one drawn on top takes the click.
        XCTAssertEqual(layout.part(at: CGPoint(x: 24, y: 22)), .foreground)
        XCTAssertEqual(layout.part(at: CGPoint(x: 38, y: 6)), .swap)
        XCTAssertEqual(layout.part(at: CGPoint(x: 8, y: 35)), .reset)
        XCTAssertNil(layout.part(at: CGPoint(x: 1, y: 40)))

        let bounds = CGRect(origin: .zero, size: ClassicColorPairLayout.size)
        for part in ClassicColorPairLayout.Part.allCases {
            XCTAssertTrue(bounds.contains(layout.frame(of: part)), "\(part) leaves the control")
        }
    }

    func testAClickReportsItsPartAndLeavesTheColorsToTheApplication() throws {
        let (window, pair) = makeWindow()
        defer { window.close() }
        var reports: [String] = []
        pair.onEditForeground = { reports.append("foreground") }
        pair.onEditBackground = { reports.append("background") }
        pair.onSwap = { reports.append("swap") }
        pair.onReset = { reports.append("reset") }
        pair.foreground = .systemRed
        pair.background = .systemBlue

        let layout = ClassicColorPairLayout()
        for part in [ClassicColorPairLayout.Part.foreground, .background, .swap, .reset] {
            let frame = layout.frame(of: part)
            click(pair, at: CGPoint(x: frame.maxX - 2, y: frame.maxY - 2), in: window)
        }

        XCTAssertEqual(reports, ["foreground", "background", "swap", "reset"])
        // The control reports intent; the colors are the application's to change.
        XCTAssertEqual(pair.foreground, .systemRed)
        XCTAssertEqual(pair.background, .systemBlue)
    }

    func testAPressReleasedOverAnotherPartDoesNothing() {
        let (window, pair) = makeWindow()
        defer { window.close() }
        var reports = 0
        pair.onSwap = { reports += 1 }
        pair.onEditForeground = { reports += 1 }

        let layout = ClassicColorPairLayout()
        send(.leftMouseDown, to: pair, at: CGPoint(x: layout.swap.midX, y: layout.swap.midY), in: window)
        send(.leftMouseUp, to: pair, at: CGPoint(x: layout.foreground.midX, y: layout.foreground.midY), in: window)

        XCTAssertEqual(reports, 0)
    }

    func testADisabledPairReportsNothing() {
        let (window, pair) = makeWindow()
        defer { window.close() }
        var reports = 0
        pair.onSwap = { reports += 1 }
        pair.isEnabled = false

        let swap = ClassicColorPairLayout().swap
        click(pair, at: CGPoint(x: swap.midX, y: swap.midY), in: window)
        pair.perform(.swap)

        XCTAssertEqual(reports, 0)
    }

    func testVoiceOverReadsFourButtonsWithTheColorsAndShortcuts() throws {
        let pair = ClassicColorPair()
        pair.foreground = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        pair.background = .white
        pair.swapShortcut = "X"
        pair.resetShortcut = "D"
        var swaps = 0
        pair.onSwap = { swaps += 1 }

        let elements = try XCTUnwrap(pair.accessibilityChildren() as? [NSAccessibilityElement])

        XCTAssertEqual(pair.accessibilityRole(), .group)
        XCTAssertEqual(elements.map { $0.accessibilityLabel() }, [
            "Foreground Color", "Background Color", "Swap Colors (X)", "Default Colors (D)",
        ])
        XCTAssertTrue(elements.allSatisfy { $0.accessibilityRole() == .button })
        XCTAssertEqual(elements[0].accessibilityValue() as? String,
                       "red 100 percent, green 0 percent, blue 0 percent")
        XCTAssertEqual(elements[1].accessibilityValue() as? String,
                       "red 100 percent, green 100 percent, blue 100 percent")

        XCTAssertTrue(elements[2].accessibilityPerformPress())
        XCTAssertEqual(swaps, 1)

        pair.foreground = .black
        XCTAssertEqual(elements[0].accessibilityValue() as? String,
                       "red 0 percent, green 0 percent, blue 0 percent")
    }

    // MARK: - Helpers

    private func makeWindow() -> (NSWindow, ClassicColorPair) {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let pair = ClassicColorPair()
        pair.setFrameOrigin(NSPoint(x: 10, y: 10))
        window.contentView?.addSubview(pair)
        return (window, pair)
    }

    private func click(_ pair: ClassicColorPair, at point: CGPoint, in window: NSWindow) {
        send(.leftMouseDown, to: pair, at: point, in: window)
        send(.leftMouseUp, to: pair, at: point, in: window)
    }

    /// `point` is in the pair's own flipped coordinates.
    private func send(_ type: NSEvent.EventType, to pair: ClassicColorPair,
                      at point: CGPoint, in window: NSWindow) {
        let location = pair.convert(point, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1)
        else { return XCTFail("could not make a mouse event") }

        if type == .leftMouseDown {
            pair.mouseDown(with: event)
        } else {
            pair.mouseUp(with: event)
        }
    }
}
