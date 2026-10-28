import AppKit
import XCTest

@testable import RigiUI

@MainActor
final class PalettePopoverTests: XCTestCase {
  private let paletteContentSize = NSSize(width: 320, height: 240)

  func testContentSizingGivesScrollingContentADefiniteSize() {
    _ = NSApplication.shared
    let content = PaletteScrollingTestContent()

    // A scroll-view root reports neither a preferred size nor a usable frame
    // on its own, which is what collapsed the popover.
    XCTAssertEqual(content.view.frame.size, .zero)

    makeDefinition().applyContentSizing(to: content)

    XCTAssertEqual(content.preferredContentSize, paletteContentSize)
    XCTAssertEqual(content.view.frame.size, paletteContentSize)
  }

  func testPopoverPresentsScrollingContentAtTheDeclaredContentSize() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let palette = Palette(
      definition: makeDefinition(),
      target: { NSObject() },
      makeContent: PaletteScrollingTestContent.init
    )
    defer { drainClose(palette) }

    palette.present(from: anchor)

    let popover = try XCTUnwrap(palette.presentedPopover)

    XCTAssertEqual(popover.contentSize, paletteContentSize)
    XCTAssertEqual(palette.presentation, .popover)

    let contentView = try XCTUnwrap(popover.contentViewController?.view)
    contentView.layoutSubtreeIfNeeded()

    // Chrome independent: whatever the popover settles on, the content fills it.
    XCTAssertEqual(contentView.frame.size, popover.contentSize)
  }

  /// A programmatically created window is released when it closes, which would
  /// over-release the strong reference the caller holds.
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
      kind: PaletteKind("tests.popover.scrolling"),
      title: "Popover Scrolling Test",
      contentSize: paletteContentSize
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

/// Mirrors a palette body: a scroll view whose document stack is taller than the
/// viewport and supplies no height to the scroll view itself.
@MainActor
private final class PaletteScrollingTestContent: NSViewController, PaletteContent {
  typealias Target = NSObject

  override func loadView() {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    for index in 0..<24 {
      stack.addArrangedSubview(NSTextField(labelWithString: "Row \(index)"))
    }

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.documentView = stack
    stack.translatesAutoresizingMaskIntoConstraints = false
    let clipView = scrollView.contentView
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: clipView.topAnchor),
      stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
      stack.widthAnchor.constraint(equalTo: clipView.widthAnchor),
    ])
    view = scrollView
  }

  func retarget(to target: NSObject?) {}
}
