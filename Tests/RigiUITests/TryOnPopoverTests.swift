import AppKit
import XCTest
@testable import RigiUI

@MainActor
final class TryOnPopoverTests: XCTestCase {
    func testCancelFinishesOnceAndReleasesPresentation() throws {
        let (window, anchor) = makeAnchor()
        defer { window.close() }
        let picker = TryOnPopover(hint: "Preview")
        var outcomes: [TryOnPopover.Outcome] = []
        present(picker, from: anchor, onFinish: { outcomes.append($0) })
        XCTAssertTrue(picker.isActive)

        let popover = try XCTUnwrap(picker.presentedPopover)
        let list = try XCTUnwrap(popover.contentViewController?.view.subviews
            .compactMap { $0 as? PickerListView }.first)
        _ = list.control(NSSearchField(), textView: NSTextView(),
                         doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        _ = list.control(NSSearchField(), textView: NSTextView(),
                         doCommandBy: #selector(NSResponder.insertNewline(_:)))
        drain(picker)

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertTrue(outcomes.first == .cancel)
        XCTAssertFalse(picker.isActive)
    }

    func testClickAwayCommitsAndDetachmentIsOptIn() throws {
        let (window, anchor) = makeAnchor()
        defer { window.close() }
        let picker = TryOnPopover(hint: "Preview")
        var outcomes: [TryOnPopover.Outcome] = []
        present(picker, from: anchor, onFinish: { outcomes.append($0) })
        let popover = try XCTUnwrap(picker.presentedPopover)
        XCTAssertFalse(picker.popoverShouldDetach(popover))

        popover.close()
        drain(picker)

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertTrue(outcomes.first == .commit)
        XCTAssertFalse(picker.isActive)
    }

    func testDetachBanksPreviewBeforeHandingOffAndFinishesOnlyOnce() throws {
        let (window, anchor) = makeAnchor()
        defer { window.close() }
        let picker = TryOnPopover(hint: "Preview")
        let palette = TestTearOffPalette()
        var events: [String] = []
        picker.present(from: anchor, palette: palette,
                       items: [PickerItem(id: "one", title: "One")], currentID: "one",
                       specimenFont: { _ in .systemFont(ofSize: 13) }, onPreview: { _ in },
                       onDetach: { events.append("bank") },
                       onFinish: { _ in events.append("finish") })
        let popover = try XCTUnwrap(picker.presentedPopover)
        XCTAssertTrue(picker.popoverShouldDetach(popover))
        XCTAssertIdentical(picker.detachableWindow(for: popover), palette.window)
        XCTAssertEqual(palette.selectedID, "one")
        XCTAssertTrue(events.isEmpty)

        popover.delegate = nil
        picker.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover,
                                            userInfo: [NSPopover.closeReasonUserInfoKey:
                                                        NSPopover.CloseReason.detachToWindow]))
        picker.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))
        popover.close()

        XCTAssertEqual(events, ["bank", "finish"])
        XCTAssertEqual(palette.detachCount, 1)
    }

    func testClickAwayWhilePaletteShowsIsNotMistakenForTearOff() throws {
        // chonk finding 7: the panel-visibility fallback must only count when
        // a detachment was actually prepared; a plain click-away with the
        // palette showing must not bank an undo step.
        let (window, anchor) = makeAnchor()
        defer { window.close() }
        let picker = TryOnPopover(hint: "Preview")
        let palette = TestTearOffPalette()
        palette.showingPanel = true
        var events: [String] = []
        picker.present(from: anchor, palette: palette,
                       items: [PickerItem(id: "one", title: "One")], currentID: "one",
                       specimenFont: { _ in .systemFont(ofSize: 13) }, onPreview: { _ in },
                       onDetach: { events.append("bank") },
                       onFinish: { _ in events.append("finish") })
        let popover = try XCTUnwrap(picker.presentedPopover)

        popover.delegate = nil
        picker.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover,
                                            userInfo: [NSPopover.closeReasonUserInfoKey:
                                                        NSPopover.CloseReason.standard]))

        XCTAssertEqual(events, ["finish"], "click-away must not fire onDetach")
        XCTAssertEqual(palette.detachCount, 0)
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

@MainActor
private final class TestTearOffPalette: TearOffPalette {
    let window = NSWindow(contentRect: .zero, styleMask: .borderless,
                          backing: .buffered, defer: false)
    var selectedID: String?
    var detachCount = 0
    var showingPanel = false
    var isShowingPanel: Bool { showingPanel }

    func windowForDetach(selecting id: String?) -> NSWindow {
        selectedID = id
        return window
    }

    func didDetach() { detachCount += 1 }
}
