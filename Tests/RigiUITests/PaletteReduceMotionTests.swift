import AppKit
import XCTest

@testable import RigiUI

/// Reduce Motion handling of the attached palette popover: the actual created
/// NSPopover's `animates` follows the preference at each opening and when the
/// preference changes while the popover is open, without changing the
/// close, tear-off, or showPanel/focus follow-up outcomes.
@MainActor
final class PaletteReduceMotionTests: XCTestCase {
  private let contentSize = NSSize(width: 320, height: 240)

  func testBackgroundDisplayNotificationUpdatesThePopoverOnMain() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }
    let preference = ReduceMotionPreference(false)
    var readsWereOnMain = true
    let palette = Palette(definition: makeDefinition(), target: { NSObject() },
      makeContent: ReduceMotionTestContent.init, reduceMotion: {
        readsWereOnMain = readsWereOnMain && Thread.isMainThread
        return preference.value
      })
    defer { drainClose(palette) }
    palette.present(from: anchor)
    let popover = try XCTUnwrap(palette.presentedPopover)
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
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let preference = ReduceMotionPreference(false)
    let palette = Palette(
      definition: makeDefinition(),
      target: { NSObject() },
      makeContent: ReduceMotionTestContent.init,
      reduceMotion: { preference.value }
    )
    defer { drainClose(palette) }

    palette.present(from: anchor)
    let first = try XCTUnwrap(palette.presentedPopover)
    XCTAssertTrue(first.animates, "Reduce Motion off: the popover must animate")
    drainClose(palette)

    preference.value = true
    palette.present(from: anchor)
    let second = try XCTUnwrap(palette.presentedPopover)
    XCTAssertFalse(second.animates, "Reduce Motion on: the popover must not animate")
  }

  func testPreferenceChangeWhileOpenUpdatesTheOpenPopoversAnimates() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let preference = ReduceMotionPreference(false)
    let palette = Palette(
      definition: makeDefinition(),
      target: { NSObject() },
      makeContent: ReduceMotionTestContent.init,
      reduceMotion: { preference.value }
    )
    defer { drainClose(palette) }

    palette.present(from: anchor)
    let popover = try XCTUnwrap(palette.presentedPopover)
    XCTAssertTrue(popover.animates)

    preference.value = true
    postReduceMotionChange()

    XCTAssertFalse(popover.animates, "An open popover follows a Reduce Motion change")

    // The plain close lifecycle is unchanged by the preference flip.
    palette.close()
    let deadline = Date(timeIntervalSinceNow: 1)
    while palette.isPresented || palette.presentedPopover != nil, Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    XCTAssertFalse(palette.isPresented)
    XCTAssertNil(palette.presentedPopover)
  }

  func testPreferenceChangeWhileOpenKeepsTheShowPanelFollowUp() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let preference = ReduceMotionPreference(false)
    let palette = Palette(
      definition: makeDefinition(),
      target: { NSObject() },
      makeContent: ReduceMotionTestContent.init,
      reduceMotion: { preference.value }
    )
    defer { drainClose(palette) }

    palette.present(from: anchor)
    let popover = try XCTUnwrap(palette.presentedPopover)

    preference.value = true
    postReduceMotionChange()
    XCTAssertFalse(popover.animates)

    // showPanel closes the popover and opens the floating form afterwards.
    palette.showPanel()
    let deadline = Date(timeIntervalSinceNow: 1)
    while palette.presentation != .panel, Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    XCTAssertEqual(palette.presentation, .panel)
    XCTAssertNil(palette.presentedPopover)
  }

  func testPreferenceChangeWhileOpenKeepsTheTearOffOutcome() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let preference = ReduceMotionPreference(false)
    let palette = Palette(
      definition: makeDefinition(),
      target: { NSObject() },
      makeContent: ReduceMotionTestContent.init,
      reduceMotion: { preference.value }
    )
    defer { drainClose(palette) }

    palette.present(from: anchor)
    let popover = try XCTUnwrap(palette.presentedPopover)

    preference.value = true
    postReduceMotionChange()
    XCTAssertFalse(popover.animates)

    // The delegate calls the OS makes during a tear-off drag, with the
    // popover's own delegate detached so a real close cannot race them.
    let panel = try XCTUnwrap(palette.detachableWindow(for: popover) as? PalettePanel)
    popover.delegate = nil
    palette.popoverDidClose(
      Notification(
        name: NSPopover.didCloseNotification,
        object: popover,
        userInfo: [
          NSPopover.closeReasonUserInfoKey: NSPopover.CloseReason.detachToWindow
        ]
      )
    )
    popover.close()

    XCTAssertEqual(palette.presentation, .panel)
    XCTAssertTrue(panel.isVisible)
  }

  private func postReduceMotionChange() {
    NSWorkspace.shared.notificationCenter.post(
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: NSWorkspace.shared
    )
  }

  private func makeAnchorWindow() throws -> (window: NSWindow, anchor: NSView) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 80, height: 24))
    try XCTUnwrap(window.contentView).addSubview(anchor)
    window.orderFrontRegardless()
    return (window, anchor)
  }

  private func makeDefinition() -> PaletteDefinition {
    PaletteDefinition(
      kind: PaletteKind("tests.popover.reduce-motion"),
      title: "Reduce Motion Test",
      contentSize: contentSize
    )
  }

  /// A popover closes asynchronously, and a palette is app global, so a leaked
  /// one would defer the next presentation instead of failing here.
  private func drainClose(
    _ palette: Palette,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    palette.close()
    let deadline = Date(timeIntervalSinceNow: 1)
    while palette.isPresented || palette.presentedPopover != nil, Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    XCTAssertFalse(palette.isPresented, "The palette did not close.", file: file, line: line)
    XCTAssertNil(palette.presentedPopover, "The popover did not close.", file: file, line: line)
  }
}

/// A mutable per-instance Reduce Motion source for the provider seam.
@MainActor
private final class ReduceMotionPreference {
  var value: Bool

  init(_ value: Bool) { self.value = value }
}

@MainActor
private final class ReduceMotionTestContent: NSViewController, PaletteContent {
  typealias Target = NSObject

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
  }

  func retarget(to target: NSObject?) {}
}
