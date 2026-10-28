import AppKit
import XCTest

@testable import RigiUI

@MainActor
final class PaletteTests: XCTestCase {

  func testLegacyNotificationNameRemainsCompatible() {
    XCTAssertEqual(Palette.presentationDidChangeNotification.rawValue,
                   "SionKitPalettePresentationDidChange")
  }

  // MARK: - Typed retarget

  func testRetargetFeedsTheTypedTargetToThePresentedContent() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let recorder = PaletteRecorder()
    let first = PaletteTestTarget()
    var frontDocument: PaletteTestTarget? = first
    let palette = Palette(
      definition: makeDefinition(kind: "tests.retarget.typed"),
      target: { frontDocument },
      makeContent: { RecordingPaletteContent(recorder: recorder) }
    )
    defer { drainClose(palette) }

    palette.present(from: anchor)

    let content = try XCTUnwrap(recorder.contents.first)
    XCTAssertEqual(content.retargets, [ObjectIdentifier(first)])

    // A new front document resolves through the same closure, typed.
    let other = PaletteTestTarget()
    frontDocument = other
    palette.retarget()
    XCTAssertEqual(
      content.retargets,
      [ObjectIdentifier(first), ObjectIdentifier(other)]
    )
  }

  func testDismissReleasesTheTarget() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let recorder = PaletteRecorder()
    let palette = Palette(
      definition: makeDefinition(kind: "tests.retarget.release"),
      target: { PaletteTestTarget() },
      makeContent: { RecordingPaletteContent(recorder: recorder) }
    )

    palette.present(from: anchor)
    drainClose(palette)

    let content = try XCTUnwrap(recorder.contents.first)
    XCTAssertNotNil(content.retargets.first ?? nil)
    XCTAssertNil(content.retargets.last ?? nil)
    XCTAssertEqual(content.dismissed, [.popover])
  }

  // MARK: - Registration

  func testPaletteCenterRegistersOnePalettePerKind() {
    _ = NSApplication.shared
    let kind = PaletteKind("tests.singleton.\(UUID().uuidString)")

    let first = PaletteCenter.shared.palette(
      for: PaletteDefinition(
        kind: kind,
        title: "First",
        contentSize: NSSize(width: 120, height: 100)
      ),
      target: { nil as PaletteTestTarget? },
      makeContent: { RecordingPaletteContent(recorder: PaletteRecorder()) }
    )
    // The first registration owns the definition and factories; a second call
    // for the same kind hands the existing palette back.
    let second = PaletteCenter.shared.palette(
      for: PaletteDefinition(
        kind: kind,
        title: "Second",
        contentSize: NSSize(width: 60, height: 50)
      ),
      target: { nil as PaletteTestTarget? },
      makeContent: { RecordingPaletteContent(recorder: PaletteRecorder()) }
    )

    XCTAssertTrue(first === second)
    XCTAssertIdentical(PaletteCenter.shared.registeredPalette(for: kind), first)
    XCTAssertEqual(first.definitionContentSize, NSSize(width: 120, height: 100))
  }

  // MARK: - Presentation lifecycle

  func testDetachmentPresentsThePanelAndDismissesThePopoverExactlyOnce() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let recorder = PaletteRecorder()
    let palette = Palette(
      definition: makeDefinition(kind: "tests.detach"),
      target: { PaletteTestTarget() },
      makeContent: { RecordingPaletteContent(recorder: recorder) }
    )
    defer { drainClose(palette) }

    palette.present(from: anchor)
    let popover = try XCTUnwrap(palette.presentedPopover)
    XCTAssertEqual(recorder.contents.count, 1)

    // The delegate call the OS makes at the start of a tear-off drag.
    let panel = try XCTUnwrap(palette.detachableWindow(for: popover) as? PalettePanel)
    XCTAssertEqual(recorder.contents.count, 2)

    // …and the one that commits it: the popover closed with the detach
    // reason. The popover's own close is simulated here rather than dragged
    // out, so its delegate is detached first to keep a real didClose from
    // racing the manual one.
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

    let popoverContent = recorder.contents[0]
    let panelContent = recorder.contents[1]
    XCTAssertEqual(popoverContent.presented, [.popover])
    XCTAssertEqual(popoverContent.dismissed, [.popover])
    XCTAssertEqual(panelContent.presented, [.panel])
    XCTAssertEqual(panelContent.dismissed, [])

    palette.close()

    XCTAssertEqual(panelContent.dismissed, [.panel])
    XCTAssertFalse(panel.isVisible)
    XCTAssertFalse(palette.isPresented)
  }

  func testEachPresentationBuildsADistinctViewController() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let recorder = PaletteRecorder()
    let palette = Palette(
      definition: makeDefinition(kind: "tests.distinct"),
      target: { PaletteTestTarget() },
      makeContent: { RecordingPaletteContent(recorder: recorder) }
    )
    defer { drainClose(palette) }

    palette.present(from: anchor)
    let popoverContent = try XCTUnwrap(recorder.contents.first)

    palette.showPanel()
    drainRunLoop()

    XCTAssertEqual(recorder.contents.count, 2)
    XCTAssertFalse(
      recorder.contents[1].paletteViewController === popoverContent.paletteViewController,
      "A palette content factory must create distinct view controllers"
    )
    XCTAssertEqual(palette.presentation, .panel)
    XCTAssertEqual(popoverContent.dismissed, [.popover])
  }

  func testPresentRaisesTheFloatingPanelInsteadOfOpeningASecondForm() throws {
    _ = NSApplication.shared
    let (window, anchor) = try makeAnchorWindow()
    defer { window.close() }

    let recorder = PaletteRecorder()
    let palette = Palette(
      definition: makeDefinition(kind: "tests.raise"),
      target: { PaletteTestTarget() },
      makeContent: { RecordingPaletteContent(recorder: recorder) }
    )
    defer { drainClose(palette) }

    palette.showPanel()
    let panel = try XCTUnwrap(
      NSApp.windows.first { $0 is PalettePanel && $0.isVisible }
    )
    XCTAssertEqual(palette.presentation, .panel)

    palette.present(from: anchor)

    XCTAssertNil(palette.presentedPopover)
    XCTAssertEqual(palette.presentation, .panel)
    XCTAssertEqual(recorder.contents.count, 1)

    palette.bringToFront()
    XCTAssertTrue(panel.isVisible)

    palette.close()
    XCTAssertFalse(panel.isVisible)
    XCTAssertFalse(palette.isPresented)
  }

  // MARK: - Helpers

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

  private func makeDefinition(kind: String) -> PaletteDefinition {
    PaletteDefinition(
      kind: PaletteKind(kind),
      title: "Palette Test",
      contentSize: NSSize(width: 300, height: 320)
    )
  }

  private func drainRunLoop() {
    let deadline = Date(timeIntervalSinceNow: 0.5)
    while Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
  }

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

@MainActor
private final class PaletteTestTarget: NSObject {}

/// What each presentation's content observed, in order.
@MainActor
private final class PaletteRecorder {
  var contents: [RecordingPaletteContent] = []
}

@MainActor
private final class RecordingPaletteContent: NSViewController, PaletteContent {
  typealias Target = PaletteTestTarget

  var retargets: [ObjectIdentifier?] = []
  var presented: [PalettePresentation] = []
  var dismissed: [PalettePresentation] = []

  init(recorder: PaletteRecorder) {
    super.init(nibName: nil, bundle: nil)
    recorder.contents.append(self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func loadView() {
    view = NSView()
  }

  func retarget(to target: PaletteTestTarget?) {
    retargets.append(target.map(ObjectIdentifier.init))
  }

  func paletteDidPresent(_ presentation: PalettePresentation) {
    presented.append(presentation)
  }

  func paletteDidDismiss(_ presentation: PalettePresentation) {
    dismissed.append(presentation)
  }
}
