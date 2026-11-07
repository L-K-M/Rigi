import AppKit
import XCTest
@testable import RigiUI

@MainActor
final class TryOnFocusTests: XCTestCase {
    func testCommitAndCancelReturnFocusToTheEditorNotTheAnchor() throws {
        for command in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            let (window, anchor, editor) = makeEditor()
            defer { window.close() }
            let picker = TryOnPopover(hint: "Preview")
            present(picker, from: anchor)
            let popover = try XCTUnwrap(picker.presentedPopover)
            let list = try XCTUnwrap(popover.contentViewController?.view.subviews
                .compactMap { $0 as? PickerListView }.first)
            window.makeFirstResponder(anchor)
            _ = list.control(NSSearchField(), textView: NSTextView(), doCommandBy: command)
            drain(picker)
            XCTAssertIdentical(window.firstResponder, editor)
        }
    }

    func testClickAwayDoesNotOverrideAnotherEditorChosenByTheUser() throws {
        let (window, anchor, _) = makeEditor()
        defer { window.close() }
        let other = NSTextView(frame: NSRect(x: 300, y: 60, width: 200, height: 200))
        window.contentView?.addSubview(other)
        let picker = TryOnPopover(hint: "Preview")
        present(picker, from: anchor)
        let popover = try XCTUnwrap(picker.presentedPopover)
        window.makeFirstResponder(other)
        popover.close()
        drain(picker)
        XCTAssertIdentical(window.firstResponder, other)
    }

    func testApplicationFinishCallbackKeepsItsExplicitFocusChoice() throws {
        let (window, anchor, _) = makeEditor()
        defer { window.close() }
        let other = NSTextView(frame: NSRect(x: 300, y: 60, width: 200, height: 200))
        window.contentView?.addSubview(other)
        let picker = TryOnPopover(hint: "Preview")
        present(picker, from: anchor, onFinish: { _ in window.makeFirstResponder(other) })
        let popover = try XCTUnwrap(picker.presentedPopover)
        popover.close()
        drain(picker)
        XCTAssertIdentical(window.firstResponder, other)
    }

    func testReturnsToATextFieldThroughItsOwningControl() throws {
        let (window, anchor, _) = makeEditor()
        defer { window.close() }
        let field = NSTextField(string: "Value")
        field.frame = NSRect(x: 20, y: 300, width: 200, height: 24)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        XCTAssertNotNil(field.currentEditor())
        let picker = TryOnPopover(hint: "Preview")
        present(picker, from: anchor)
        let popover = try XCTUnwrap(picker.presentedPopover)
        let list = try XCTUnwrap(popover.contentViewController?.view.subviews
            .compactMap { $0 as? PickerListView }.first)
        window.makeFirstResponder(anchor)
        _ = list.control(NSSearchField(), textView: NSTextView(),
                         doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        drain(picker)
        XCTAssertIdentical(window.firstResponder, field.currentEditor())
        XCTAssertNotNil(field.currentEditor())
    }

    private func present(_ picker: TryOnPopover, from anchor: NSView,
                         onFinish: @escaping (TryOnPopover.Outcome) -> Void = { _ in }) {
        picker.present(from: anchor, palette: nil, items: [], currentID: nil,
                       specimenFont: { _ in .systemFont(ofSize: 13) }, onPreview: { _ in },
                       onDetach: {}, onFinish: onFinish)
    }

    private func makeEditor() -> (NSWindow, NSView, NSTextView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = FocusableAnchor(frame: NSRect(x: 20, y: 20, width: 80, height: 24))
        let editor = NSTextView(frame: NSRect(x: 20, y: 60, width: 200, height: 200))
        window.contentView?.addSubview(anchor)
        window.contentView?.addSubview(editor)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        return (window, anchor, editor)
    }

    private func drain(_ picker: TryOnPopover) {
        let deadline = Date(timeIntervalSinceNow: 1)
        while picker.isActive && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
}

@MainActor
private final class FocusableAnchor: NSView {
    override var acceptsFirstResponder: Bool { true }
}
