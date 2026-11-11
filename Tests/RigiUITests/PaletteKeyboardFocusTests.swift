import AppKit
import XCTest

@testable import RigiUI

@MainActor
final class PaletteKeyboardFocusTests: XCTestCase {
  func testFocusOpensThePanelWithItsPreferredResponder() throws {
    let bodies = FocusBodies()
    let palette = makePalette(bodies)
    defer { close(palette) }

    palette.focusPanel()

    let body = try XCTUnwrap(bodies.items.last)
    let window = try XCTUnwrap(body.view.window)
    XCTAssertEqual(palette.presentation, .panel)
    XCTAssertTrue(window.isVisible)
    XCTAssertFalse(window.canBecomeMain)
    XCTAssertTrue(isEditing(body.field, in: window))
  }

  func testFocusRaisesAnExistingPanelWithoutReplacingItsBody() throws {
    let bodies = FocusBodies()
    let palette = makePalette(bodies)
    defer { close(palette) }
    palette.showPanel()
    let body = try XCTUnwrap(bodies.items.first)
    let window = try XCTUnwrap(body.view.window)
    window.makeFirstResponder(nil)

    palette.focusPanel()

    XCTAssertEqual(bodies.items.count, 1)
    XCTAssertTrue(body.view.window === window)
    XCTAssertTrue(isEditing(body.field, in: window))
  }

  func testFocusTransfersFromThePopoverAfterItCloses() throws {
    let (window, anchor) = makeAnchor()
    defer { window.close() }
    let bodies = FocusBodies()
    let palette = makePalette(bodies)
    defer { close(palette) }
    palette.present(from: anchor)
    XCTAssertNotNil(palette.presentedPopover)

    palette.focusPanel()
    settle { palette.presentedPopover == nil && palette.presentation == .panel }

    XCTAssertNil(palette.presentedPopover)
    XCTAssertEqual(palette.presentation, .panel)
    let body = try XCTUnwrap(bodies.items.last)
    let panel = try XCTUnwrap(body.view.window)
    XCTAssertTrue(panel.isVisible)
    XCTAssertTrue(isEditing(body.field, in: panel))
  }

  func testCloseCancelsAnUnfinishedFocusRequest() {
    let (window, anchor) = makeAnchor()
    defer { window.close() }
    let palette = makePalette(FocusBodies())
    defer { close(palette) }
    palette.present(from: anchor)

    palette.focusPanel()
    palette.close()
    settle { palette.presentedPopover == nil && !palette.isPresented }

    XCTAssertNil(palette.presentedPopover)
    XCTAssertFalse(palette.isPresented)
    XCTAssertFalse(palette.isShowingPanel)
  }

  func testFocusSelectsTheRequestedGroupedTabDuringTheOpeningTurn() throws {
    try exerciseGroupedOpening(collapsed: false)
  }

  func testFocusExpandsTheRequestedGroupDuringTheOpeningTurn() throws {
    try exerciseGroupedOpening(collapsed: true)
  }

  private func exerciseGroupedOpening(collapsed: Bool) throws {
    let dock = PaletteDock(store: .memory())
    let firstBodies = FocusBodies()
    let secondBodies = FocusBodies()
    let first = makePalette(firstBodies, dock: dock)
    let second = makePalette(secondBodies, dock: dock)
    defer { close(second); close(first) }
    dock.setDefaults([PaletteGroupDefault([first.kind, second.kind])])

    // No event pumping: explicit focus must override the launch-time policy
    // that preserves the selected tab during a batch of ordinary shows.
    first.showPanel()
    let group = try XCTUnwrap(dock.groupID(of: first))
    if collapsed { dock.toggleCollapsed(group) }
    second.focusPanel()

    let body = try XCTUnwrap(secondBodies.items.last)
    let panel = try XCTUnwrap(second.hostingPanel)
    XCTAssertTrue(body.view.window === panel)
    XCTAssertFalse(dock.isCollapsed(group))
    XCTAssertTrue(isEditing(body.field, in: panel))
    XCTAssertNil(firstBodies.items.last?.view.window)
  }

  private func makePalette(_ bodies: FocusBodies, dock: PaletteDock? = nil) -> Palette {
    _ = NSApplication.shared
    return Palette(
      definition: PaletteDefinition(kind: PaletteKind("tests.focus.\(UUID().uuidString)"),
                                    title: "Keyboard Focus", contentSize: NSSize(width: 220, height: 100)),
      target: { NSObject() },
      makeContent: {
        let body = FocusBody()
        bodies.items.append(body)
        return body
      }, dock: dock)
  }

  private func isEditing(_ field: NSTextField, in window: NSWindow) -> Bool {
    guard let responder = window.firstResponder else { return false }
    return responder === field || field.currentEditor().map { responder === $0 } == true
  }

  private func makeAnchor() -> (NSWindow, NSView) {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 80, height: 24))
    window.contentView?.addSubview(anchor)
    window.orderFrontRegardless()
    return (window, anchor)
  }

  private func settle(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
  }

  private func close(_ palette: Palette) {
    palette.close()
    settle { !palette.isPresented && palette.presentedPopover == nil }
    XCTAssertFalse(palette.isPresented)
    XCTAssertNil(palette.presentedPopover)
  }
}

@MainActor
private final class FocusBodies {
  var items: [FocusBody] = []
}

@MainActor
private final class FocusBody: NSViewController, PaletteContent {
  typealias Target = NSObject
  let field = NSTextField(string: "Focus this field")

  override func loadView() {
    field.setAccessibilityLabel("Focus test field")
    view = NSStackView(views: [field])
  }

  var paletteInitialFirstResponder: NSView? { field }
  func retarget(to target: NSObject?) {}
}
