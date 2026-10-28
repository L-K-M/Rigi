import AppKit
import XCTest
@testable import RigiUI

@MainActor
final class PickerTests: XCTestCase {
    func testSynchronizationDoesNotApplyFormattingAndKeyboardSkipsSections() {
        _ = NSApplication.shared
        let picker = PickerListView(hint: "Pick a style")
        picker.setItems([.separator("Styles"), PickerItem(id: "a", title: "Alpha"),
                         .separator("More"), PickerItem(id: "b", title: "Beta")])
        var picks: [String] = []
        picker.onPick = { picks.append($0.id) }

        picker.select(id: "a")
        picker.select(id: "a")
        XCTAssertEqual(picker.selectedItem?.id, "a")
        XCTAssertTrue(picks.isEmpty)

        let field = NSSearchField()
        XCTAssertTrue(picker.control(field, textView: NSTextView(),
                                     doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertEqual(picker.selectedItem?.id, "b")
        XCTAssertEqual(picks, ["b"])

        picker.select(id: nil)
        XCTAssertNil(picker.selectedItem)
        XCTAssertEqual(picks, ["b"])
    }

    func testFilteringKeepsMatchingSelectionWithoutEmittingAnEdit() throws {
        _ = NSApplication.shared
        let picker = PickerListView(hint: "Filter")
        picker.setItems([PickerItem(id: "a", title: "Alpha"), PickerItem(id: "b", title: "Beta")])
        picker.select(id: "b")
        var picks = 0
        picker.onPick = { _ in picks += 1 }
        let filter = try XCTUnwrap(picker.subviews.compactMap { $0 as? NSSearchField }.first)
        filter.stringValue = "bet"

        picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: filter))

        XCTAssertEqual(picker.selectedItem?.id, "b")
        XCTAssertEqual(picks, 0)
        picker.clearFilter()
        XCTAssertEqual(picker.selectedItem?.id, "b")
        XCTAssertEqual(picks, 0)
    }

    func testReturnAndEscapeReportDistinctIntents() {
        _ = NSApplication.shared
        let picker = PickerListView(hint: "Preview")
        var actions: [String] = []
        picker.onCommit = { actions.append("commit") }
        picker.onCancel = { actions.append("cancel") }
        let field = NSSearchField()
        let text = NSTextView()

        XCTAssertTrue(picker.control(field, textView: text,
                                     doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(picker.control(field, textView: text,
                                     doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(actions, ["commit", "cancel"])
    }
}
