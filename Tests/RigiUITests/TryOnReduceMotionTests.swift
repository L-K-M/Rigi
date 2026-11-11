import AppKit
import XCTest
@testable import RigiUI

/// Reduce Motion handling of the try-on popover: the actual created
/// NSPopover's `animates` follows the preference at each opening and when the
/// preference changes while the popover is open, without changing commit,
/// click-away, or tear-off outcomes.
@MainActor
final class TryOnReduceMotionTests: XCTestCase {
    func testBackgroundDisplayNotificationUpdatesThePopoverOnMain() throws {
        let (window, anchor) = makeAnchor()
        defer { window.close() }
        let preference = ReduceMotionPreference(false)
        var readsWereOnMain = true
        let picker = TryOnPopover(hint: "Preview", reduceMotion: {
            readsWereOnMain = readsWereOnMain && Thread.isMainThread
            return preference.value
        })
        present(picker, from: anchor, onFinish: { _ in })
        let popover = try XCTUnwrap(picker.presentedPopover)
        defer { popover.close(); drain(picker) }
        preference.value = true
        let delivered = expectation(description: "background display notification delivered")
        let center = NSWorkspace.shared.notificationCenter
        DispatchQueue.global().async {
            center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 2)
        XCTAssertFalse(popover.animates)
        XCTAssertTrue(readsWereOnMain)
    }

    func testEachOpeningReadsTheForcedPreferenceOnTheActualPopover() throws {
        let (window, anchor) = makeAnchor()
        defer { window.close() }
        let preference = ReduceMotionPreference(true)
        let picker = TryOnPopover(hint: "Preview", reduceMotion: { preference.value })
        var outcomes: [TryOnPopover.Outcome] = []

        present(picker, from: anchor, onFinish: { outcomes.append($0) })
        let first = try XCTUnwrap(picker.presentedPopover)
        XCTAssertFalse(first.animates, "Reduce Motion on: the popover must not animate")
        first.close()
        drain(picker)

        preference.value = false
        present(picker, from: anchor, onFinish: { outcomes.append($0) })
        let second = try XCTUnwrap(picker.presentedPopover)
        XCTAssertTrue(second.animates, "Reduce Motion off: the popover must animate")
        second.close()
        drain(picker)

        // Both sessions were plain click-aways: the commit outcome is unchanged.
        XCTAssertEqual(outcomes, [.commit, .commit])
        XCTAssertFalse(picker.isActive)
    }

    func testPreferenceChangeWhileOpenUpdatesAnimatesAndKeepsCommitSemantics() throws {
        let (window, anchor) = makeAnchor()
        defer { window.close() }
        let preference = ReduceMotionPreference(false)
        let picker = TryOnPopover(hint: "Preview", reduceMotion: { preference.value })
        var outcomes: [TryOnPopover.Outcome] = []
        present(picker, from: anchor, onFinish: { outcomes.append($0) })
        let popover = try XCTUnwrap(picker.presentedPopover)
        XCTAssertTrue(popover.animates)

        preference.value = true
        postReduceMotionChange()
        XCTAssertFalse(popover.animates, "An open popover follows a Reduce Motion change")

        // Return still commits exactly once and ends the session.
        let list = try XCTUnwrap(popover.contentViewController?.view.subviews
            .compactMap { $0 as? PickerListView }.first)
        _ = list.control(NSSearchField(), textView: NSTextView(),
                         doCommandBy: #selector(NSResponder.insertNewline(_:)))
        drain(picker)

        XCTAssertEqual(outcomes, [.commit])
        XCTAssertFalse(picker.isActive)
    }

    func testPreferenceChangeWhileOpenKeepsTheTearOffOutcome() throws {
        let (window, anchor) = makeAnchor()
        defer { window.close() }
        let preference = ReduceMotionPreference(false)
        let picker = TryOnPopover(hint: "Preview", reduceMotion: { preference.value })
        let palette = ReduceMotionTearOffPalette()
        var events: [String] = []
        picker.present(from: anchor, palette: palette,
                       items: [PickerItem(id: "one", title: "One")], currentID: "one",
                       specimenFont: { _ in .systemFont(ofSize: 13) }, onPreview: { _ in },
                       onDetach: { events.append("bank") },
                       onFinish: { _ in events.append("finish") })
        let popover = try XCTUnwrap(picker.presentedPopover)
        XCTAssertTrue(popover.animates)

        preference.value = true
        postReduceMotionChange()
        XCTAssertFalse(popover.animates)

        // The delegate calls the OS makes during a tear-off drag, with the
        // popover's own delegate detached so a real close cannot race them.
        _ = picker.detachableWindow(for: popover)
        popover.delegate = nil
        picker.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover,
                                            userInfo: [NSPopover.closeReasonUserInfoKey:
                                                        NSPopover.CloseReason.detachToWindow]))
        popover.close()

        XCTAssertEqual(events, ["bank", "finish"])
        XCTAssertEqual(palette.detachCount, 1)
        XCTAssertFalse(picker.isActive)
    }

    private func postReduceMotionChange() {
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared)
    }

    private func present(_ picker: TryOnPopover, from anchor: NSView,
                         onFinish: @escaping (TryOnPopover.Outcome) -> Void) {
        picker.present(from: anchor, palette: nil, items: [], currentID: nil,
                       specimenFont: { _ in .systemFont(ofSize: 13) }, onPreview: { _ in },
                       onDetach: {}, onFinish: onFinish)
    }

    private func makeAnchor() -> (NSWindow, NSView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 80, height: 24))
        window.contentView?.addSubview(anchor)
        window.orderFrontRegardless()
        return (window, anchor)
    }

    private func drain(_ picker: TryOnPopover) {
        let deadline = Date(timeIntervalSinceNow: 1)
        while picker.isActive && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
}

/// A mutable per-instance Reduce Motion source for the provider seam.
@MainActor
private final class ReduceMotionPreference {
    var value: Bool

    init(_ value: Bool) { self.value = value }
}

@MainActor
private final class ReduceMotionTearOffPalette: TearOffPalette {
    let window = NSWindow(contentRect: .zero, styleMask: .borderless,
                          backing: .buffered, defer: false)
    var detachCount = 0
    var isShowingPanel: Bool { false }

    func windowForDetach(selecting id: String?) -> NSWindow { window }

    func didDetach() { detachCount += 1 }
}
