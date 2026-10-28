import AppKit
import XCTest

@testable import RigiUI

@MainActor
final class PalettePanelTests: XCTestCase {
  func testTheClassicTitleBarDragsAndHousesARealCloseButton() throws {
    _ = NSApplication.shared
    let panel = makePanel()
    let chrome = try XCTUnwrap(panel.contentView as? PaletteChromeView)
    let closeButton = try XCTUnwrap(chrome.descendants.compactMap { $0 as? NSButton }.first)
    chrome.setFrameSize(NSSize(width: 320, height: 240))
    chrome.layoutSubtreeIfNeeded()

    // The classic chrome draws its title bar rather than hosting a view for
    // it, so a point there hits the chrome itself — its mouseDown drags the
    // window — while the dot's own button claims clicks on it.
    let onDragRegion = NSPoint(
      x: chrome.bounds.maxX - 8,
      y: chrome.bounds.height - PaletteChromeView.titleBarHeight / 2
    )
    let onCloseButton = chrome.convert(
      NSPoint(x: closeButton.bounds.midX, y: closeButton.bounds.midY),
      from: closeButton
    )

    XCTAssertTrue(panel.isMovable)
    XCTAssertTrue(chrome.acceptsFirstMouse(for: nil))
    XCTAssertIdentical(chrome.hitTest(onDragRegion), chrome)
    XCTAssertIdentical(chrome.hitTest(onCloseButton), closeButton)
    XCTAssertTrue(closeButton.acceptsFirstMouse(for: nil))
  }

  func testPanelSizesItsChromeAndContentFromTheDefinition() throws {
    _ = NSApplication.shared
    let panel = makePanel()
    let content = PaletteTestContent()
    panel.embed(content)
    let chrome = try XCTUnwrap(panel.contentView)

    // The palette's own 300 points plus the 16pt classic title bar and the
    // 1pt border inset the chrome keeps around embedded content. The palette
    // bodies scroll and so fit to nothing on their own: without a size stated
    // here the chrome fits its bar alone and the panel opens as a bare pill.
    XCTAssertEqual(
      chrome.fittingSize.width,
      PalettePanelTestGeometry.contentSize.width + 2 * PaletteChromeView.contentInset
    )
    XCTAssertEqual(
      chrome.fittingSize.height,
      PalettePanelTestGeometry.contentSize.height + PaletteChromeView.titleBarHeight
        + PaletteChromeView.contentInset
    )

    chrome.setFrameSize(chrome.fittingSize)
    chrome.layoutSubtreeIfNeeded()

    XCTAssertEqual(content.view.frame.size, PalettePanelTestGeometry.contentSize)
  }

  func testARepairedFrameIsHeldInsideTheVisibleScreen() {
    let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let size = PalettePanelTestGeometry.contentSize

    // Grown from a frame parked at the right edge, so the width now runs past it.
    XCTAssertEqual(
      PalettePanel.constrained(
        NSRect(x: 940, y: 400, width: size.width, height: size.height),
        to: visible
      ),
      NSRect(x: 1000 - size.width, y: 400, width: size.width, height: size.height)
    )
    // Grown downward from a low top edge, so the body ran off the bottom.
    XCTAssertEqual(
      PalettePanel.constrained(
        NSRect(x: 100, y: -200, width: size.width, height: size.height),
        to: visible
      ),
      NSRect(x: 100, y: 0, width: size.width, height: size.height)
    )
    // Wider than the screen: it starts at the screen's edge rather than past it.
    XCTAssertEqual(
      PalettePanel.constrained(NSRect(x: 40, y: 0, width: 1200, height: 344), to: visible),
      NSRect(x: 0, y: 0, width: 1200, height: 344)
    )
    // Taller than the screen: the header keeps its place on screen and the
    // body, which scrolls, is what hangs off.
    XCTAssertEqual(
      PalettePanel.constrained(
        NSRect(x: 100, y: 0, width: size.width, height: 900),
        to: visible
      ).maxY,
      visible.maxY
    )
    // A frame that already fits stays where it was put.
    let placed = NSRect(x: 100, y: 100, width: size.width, height: size.height)
    XCTAssertEqual(PalettePanel.constrained(placed, to: visible), placed)
  }

  func testOnlyAResizablePaletteOffersEdgesToDragBy() throws {
    _ = NSApplication.shared
    let fixed = makePanel(kind: "tests.fixed")
    let resizable = makePanel(
      kind: "tests.resizable",
      sizing: .resizable(minimumContentSize: PalettePanelTestGeometry.minimumContentSize)
    )

    XCTAssertFalse(fixed.styleMask.contains(.resizable))
    XCTAssertTrue(resizable.styleMask.contains(.resizable))

    // A borderless window has no frame view, so the edges are the panel's own
    // and a palette that cannot be resized must not grow any.
    XCTAssertNil(
      try XCTUnwrap(fixed.contentView).descendants
        .first { $0 is PaletteResizeBorderView }
    )
    XCTAssertNotNil(
      try XCTUnwrap(resizable.contentView).descendants
        .first { $0 is PaletteResizeBorderView }
    )
    XCTAssertEqual(
      resizable.contentMinSize,
      PalettePanel.panelSize(forContentSize: PalettePanelTestGeometry.minimumContentSize)
    )
    // Stated rather than inherited: the drag clamps against this, and an
    // unset maximum reporting zero would pin the palette at its minimum.
    XCTAssertGreaterThan(resizable.contentMaxSize.width, resizable.contentMinSize.width)
    XCTAssertGreaterThan(resizable.contentMaxSize.height, resizable.contentMinSize.height)
    XCTAssertTrue(resizable.contentMaxSize.width.isFinite)
    XCTAssertTrue(resizable.contentMaxSize.height.isFinite)
  }

  func testTheDragBandsRunDownTheSidesAndAlongTheBottomOnly() {
    let bounds = NSRect(
      x: 0,
      y: 0,
      width: PalettePanelTestGeometry.contentSize.width,
      height: PalettePanelTestGeometry.contentSize.height + PaletteChromeView.titleBarHeight
    )

    XCTAssertEqual(PaletteResizeBorderView.edges(at: NSPoint(x: 150, y: 2), in: bounds), .bottom)
    XCTAssertEqual(PaletteResizeBorderView.edges(at: NSPoint(x: 2, y: 200), in: bounds), .left)
    XCTAssertEqual(PaletteResizeBorderView.edges(at: NSPoint(x: 298, y: 200), in: bounds), .right)
    XCTAssertEqual(
      PaletteResizeBorderView.edges(at: NSPoint(x: 298, y: 2), in: bounds),
      [.right, .bottom]
    )
    // The top belongs to the title bar, which drags the panel rather than
    // sizing it, and the middle belongs to the palette.
    XCTAssertEqual(
      PaletteResizeBorderView.edges(at: NSPoint(x: 150, y: bounds.maxY - 2), in: bounds),
      []
    )
    XCTAssertEqual(PaletteResizeBorderView.edges(at: NSPoint(x: 150, y: 172), in: bounds), [])
    XCTAssertEqual(PaletteResizeBorderView.edges(at: NSPoint(x: -5, y: 172), in: bounds), [])
  }

  func testThePointerChangesOverEachBandAndTheBandsDoNotOverlap() throws {
    let bounds = NSRect(x: 0, y: 0, width: 300, height: 344)
    let bands = PaletteResizeBorderView.cursorBands(in: bounds)

    XCTAssertEqual(bands.count, 3)
    XCTAssertIdentical(bands.first?.cursor, NSCursor.resizeLeftRight)
    XCTAssertIdentical(bands.dropFirst().first?.cursor, NSCursor.resizeLeftRight)
    XCTAssertIdentical(bands.last?.cursor, NSCursor.resizeUpDown)

    // Overlapping would leave a corner reading as whichever tracking area was
    // added last; it belongs to the bottom band, which is the last one here.
    for (index, band) in bands.enumerated() {
      XCTAssertTrue(bounds.contains(band.rect), "\(band.rect) leaves the palette")

      for other in bands.dropFirst(index + 1) {
        XCTAssertFalse(band.rect.intersects(other.rect), "\(band.rect) meets \(other.rect)")
      }
    }

    XCTAssertTrue(
      try XCTUnwrap(bands.last).rect.contains(NSPoint(x: bounds.maxX - 1, y: bounds.minY + 1))
    )
  }

  func testADraggedEdgeMovesAndTheOnesOppositeItStayPut() {
    let start = NSRect(x: 100, y: 100, width: 300, height: 344)
    let minimum = NSSize(width: 200, height: 200)
    let maximum = NSSize(width: 1000, height: 1000)

    XCTAssertEqual(
      PaletteResizeBorderView.resizedFrame(
        start,
        edges: .right,
        translation: NSSize(width: 60, height: -20),
        minimum: minimum,
        maximum: maximum
      ),
      NSRect(x: 100, y: 100, width: 360, height: 344)
    )
    // Dragging the leading edge inwards moves the origin so the trailing edge
    // does not follow the pointer across the screen.
    XCTAssertEqual(
      PaletteResizeBorderView.resizedFrame(
        start,
        edges: .left,
        translation: NSSize(width: 50, height: 0),
        minimum: minimum,
        maximum: maximum
      ),
      NSRect(x: 150, y: 100, width: 250, height: 344)
    )
    // Downwards is negative on screen, and the title bar keeps its place.
    XCTAssertEqual(
      PaletteResizeBorderView.resizedFrame(
        start,
        edges: [.right, .bottom],
        translation: NSSize(width: 40, height: -40),
        minimum: minimum,
        maximum: maximum
      ),
      NSRect(x: 100, y: 60, width: 340, height: 384)
    )
    // Past the minimum on both axes: the size stops, and the anchored edges
    // stay where they were rather than drifting with the pointer.
    XCTAssertEqual(
      PaletteResizeBorderView.resizedFrame(
        start,
        edges: [.left, .bottom],
        translation: NSSize(width: 400, height: 400),
        minimum: minimum,
        maximum: maximum
      ),
      NSRect(x: 200, y: 244, width: 200, height: 200)
    )
    // And past the maximum on the way out, with the leading edge still where
    // the drag started from.
    XCTAssertEqual(
      PaletteResizeBorderView.resizedFrame(
        start,
        edges: .right,
        translation: NSSize(width: 5_000, height: 0),
        minimum: minimum,
        maximum: maximum
      ),
      NSRect(x: 100, y: 100, width: maximum.width, height: 344)
    )
    // A maximum below the minimum is a palette that cannot show itself; the
    // minimum is what a person can still work in, so it wins.
    XCTAssertEqual(
      PaletteResizeBorderView.resizedFrame(
        start,
        edges: .right,
        translation: NSSize(width: 400, height: 0),
        minimum: minimum,
        maximum: NSSize(width: 100, height: 100)
      ).width,
      minimum.width
    )
  }

  func testCloseButtonClosesPanel() throws {
    _ = NSApplication.shared
    let panel = makePanel()
    panel.setCloseHandler { [weak panel] in
      panel?.close()
    }
    panel.orderFrontRegardless()

    let contentView = try XCTUnwrap(panel.contentView)
    let closeButton = try XCTUnwrap(
      contentView.descendants.compactMap { $0 as? NSButton }.first {
        $0.toolTip == "Close \(PalettePanelTestCopy.title) Palette"
      }
    )

    XCTAssertTrue(panel.styleMask.contains(.closable))
    XCTAssertTrue(closeButton.acceptsFirstMouse(for: nil))
    closeButton.performClick(nil)

    XCTAssertFalse(panel.isVisible)
  }

  func testPaletteCloseClosesFloatingPanel() throws {
    _ = NSApplication.shared
    let palette = Palette(
      definition: PaletteDefinition(
        kind: PaletteKind("tests.close"),
        title: "Palette Close Test",
        contentSize: NSSize(width: 300, height: 320)
      ),
      target: { NSObject() },
      makeContent: PaletteTestContent.init
    )
    defer { palette.close() }

    palette.showPanel()
    let panel = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Palette Close Test" && $0.isVisible }
    )

    palette.close()

    XCTAssertFalse(panel.isVisible)
  }

  func testPanelPersistsItsFrameUnderARigiNamespacedAutosaveNameByDefault() {
    _ = NSApplication.shared
    let panel = PalettePanel(
      definition: PaletteDefinition(
        kind: PaletteKind("tests.autosave.default"),
        title: "Autosave Default",
        contentSize: NSSize(width: 200, height: 160)
      )
    )
    defer { panel.close() }

    XCTAssertEqual(
      panel.frameAutosaveName,
      "Rigi.palette.tests.autosave.default"
    )
  }

  func testPanelPersistsItsFrameUnderAnExplicitAutosaveName() {
    _ = NSApplication.shared
    // An adapter keeps the keys an earlier toolkit saved its frames under —
    // Sion's, for example — instead of abandoning the user's placement.
    let panel = PalettePanel(
      definition: PaletteDefinition(
        kind: PaletteKind("tests.autosave.custom"),
        title: "Autosave Custom",
        contentSize: NSSize(width: 200, height: 160),
        frameAutosaveName: "Sion.palette.tests.autosave.custom"
      )
    )
    defer { panel.close() }

    XCTAssertEqual(panel.frameAutosaveName, "Sion.palette.tests.autosave.custom")
  }

  private func makePanel(
    kind: String = "tests.inspector",
    sizing: PaletteSizing = .fixed
  ) -> PalettePanel {
    PalettePanel(
      definition: PaletteDefinition(
        kind: PaletteKind(kind),
        title: PalettePanelTestCopy.title,
        contentSize: PalettePanelTestGeometry.contentSize,
        sizing: sizing
      )
    )
  }
}

private enum PalettePanelTestCopy {
  static let title = "Palette Panel Test"
}

private enum PalettePanelTestGeometry {
  static let contentSize = NSSize(width: 300, height: 320)
  static let minimumContentSize = NSSize(width: 200, height: 180)
}

@MainActor
private final class PaletteTestContent: NSViewController, PaletteContent {
  typealias Target = NSObject

  override func loadView() {
    view = NSView()
  }

  func retarget(to target: NSObject?) {}
}

extension NSView {
  fileprivate var descendants: [NSView] {
    subviews + subviews.flatMap(\.descendants)
  }
}
