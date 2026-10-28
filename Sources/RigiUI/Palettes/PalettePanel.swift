import AppKit

private enum PaletteMetrics {
  /// Past any display, but stated rather than left to whatever an unset
  /// `contentMaxSize` reports: the drag below clamps against it.
  static let maximumContentSize = NSSize(width: 10_000, height: 10_000)
}

/// Classic chrome around a borderless palette panel.
@MainActor
final class PalettePanelViewController: NSViewController {
  var onClose: (@MainActor () -> Void)? {
    didSet { chrome.onClose = onClose }
  }

  private let chrome: PaletteChromeView
  private let declaredContentSize: NSSize
  private var embeddedController: NSViewController?

  init(title: String, contentSize: NSSize, isResizable: Bool) {
    declaredContentSize = contentSize
    chrome = PaletteChromeView(title: title)

    super.init(nibName: nil, bundle: nil)

    // A borderless panel has no title bar of its own to size it, so the
    // chrome states the size the window should open at.
    preferredContentSize = PalettePanel.panelSize(forContentSize: contentSize)

    if isResizable {
      chrome.installResizeBorder()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func loadView() {
    view = chrome
  }

  func embed(_ controller: NSViewController) {
    guard embeddedController !== controller else { return }

    embeddedController?.removeFromParent()
    embeddedController = controller
    addChild(controller)
    chrome.embedContent(controller.view)
    chrome.applyDeclaredContentSize(declaredContentSize)
  }
}

/// A nonactivating utility window that becomes key only for controls that need it.
@MainActor
final class PalettePanel: ClassicPaletteWindow {
  /// The prefix a definition's frame autosave name falls back to when it does
  /// not carry one of its own.
  static let defaultFrameAutosavePrefix = "Rigi.palette."

  private let paletteViewController: PalettePanelViewController

  init(definition: PaletteDefinition) {
    var styleMask: NSWindow.StyleMask = [.borderless, .closable, .nonactivatingPanel]
    var isResizable = false
    if case .resizable = definition.sizing {
      styleMask.insert(.resizable)
      isResizable = true
    }

    let panelSize = Self.panelSize(forContentSize: definition.contentSize)
    paletteViewController = PalettePanelViewController(
      title: definition.title,
      contentSize: definition.contentSize,
      isResizable: isResizable
    )

    super.init(contentSize: panelSize, styleMask: styleMask)

    title = definition.title
    isMovable = true

    // The limits go in before the content view controller, which resizes the
    // window to the controller's preferred size as it is attached.
    configureSizing(definition.sizing, preferredContentSize: panelSize)
    contentViewController = paletteViewController

    // Center first; setFrameAutosaveName restores a previous placement.
    center()
    _ = setFrameAutosaveName(
      definition.frameAutosaveName
        ?? Self.defaultFrameAutosavePrefix + definition.kind.identifier
    )
    growToMinimumContentSize()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  /// The chrome's footprint around a palette body: the half-height title bar
  /// on top and the hairline-border inset around the other three edges.
  static func panelSize(forContentSize contentSize: NSSize) -> NSSize {
    NSSize(
      width: contentSize.width + 2 * PaletteChromeView.contentInset,
      height: contentSize.height + PaletteChromeView.titleBarHeight
        + PaletteChromeView.contentInset
    )
  }

  override func performClose(_ sender: Any?) {
    close()
  }

  override func cancelOperation(_ sender: Any?) {
    close()
  }

  func embed(_ controller: NSViewController) {
    paletteViewController.embed(controller)
  }

  func setCloseHandler(_ handler: @escaping @MainActor () -> Void) {
    paletteViewController.onClose = handler
  }

  private func configureSizing(_ sizing: PaletteSizing, preferredContentSize: NSSize) {
    switch sizing {
    case .fixed:
      contentMinSize = preferredContentSize
      contentMaxSize = preferredContentSize

    case .resizable(let minimumContentSize):
      contentMinSize = Self.panelSize(forContentSize: minimumContentSize)
      contentMaxSize = PaletteMetrics.maximumContentSize
    }
  }

  /// A frame restored from user defaults can be smaller than the palette can
  /// show anything in — one saved by a build that collapsed the panel, say.
  /// Growing back is the only way out for a palette the user cannot resize.
  private func growToMinimumContentSize() {
    let current = contentRect(forFrameRect: frame).size
    guard current.width < contentMinSize.width || current.height < contentMinSize.height else {
      return
    }

    let grown = frameRect(
      forContentRect: NSRect(
        origin: .zero,
        size: NSSize(
          width: max(current.width, contentMinSize.width),
          height: max(current.height, contentMinSize.height)
        )
      )
    )

    // Anchored at the top-left, then held on screen: the position the frame
    // grew from is as arbitrary as its size was, and a palette hanging off
    // the edge is as far out of reach as one collapsed to its header. The
    // window may be on no screen at all, which is why the main one stands in.
    let anchored = NSRect(
      x: frame.minX,
      y: frame.maxY - grown.height,
      width: grown.width,
      height: grown.height
    )
    let visible = (screen ?? NSScreen.main)?.visibleFrame

    // One frame change, so nothing observing the window sees it half moved.
    setFrame(visible.map { Self.constrained(anchored, to: $0) } ?? anchored, display: false)
  }

  /// Slides `rect` inside `visible` without resizing it.
  ///
  /// A rect that does not fit gives up a different edge per axis. Too wide
  /// starts at the leading edge, since the header runs the whole width and
  /// stays grabbable from either end. Too tall keeps its top edge on screen
  /// and lets the body hang off the bottom: the body scrolls, and the header
  /// is the only handle the panel has.
  static func constrained(_ rect: NSRect, to visible: NSRect) -> NSRect {
    NSRect(
      origin: NSPoint(
        x: min(max(rect.minX, visible.minX), max(visible.minX, visible.maxX - rect.width)),
        y: min(max(rect.minY, visible.minY), visible.maxY - rect.height)
      ),
      size: rect.size
    )
  }
}

/// Drags the window's own edges, standing in for the frame view a borderless
/// window does not have.
@MainActor
final class PaletteResizeBorderView: NSView {
  /// How far in from an edge still counts as that edge.
  static let bandWidth: CGFloat = 5

  struct Edges: OptionSet {
    let rawValue: Int

    static let left = Edges(rawValue: 1 << 0)
    static let right = Edges(rawValue: 1 << 1)
    static let bottom = Edges(rawValue: 1 << 2)
  }

  private struct ResizeDrag {
    let edges: Edges
    let startFrame: NSRect
    let startLocation: NSPoint
  }

  /// A sibling control — the close button — whose own hit area wins over the
  /// bands it overlaps. The button's padded frame dips a few points into the
  /// left band; without this those pixels would start a resize.
  weak var interactiveSibling: NSView?

  private var drag: ResizeDrag?

  /// The overlay covers the whole palette, so anything that is not on a band
  /// has to fall through to the content underneath it.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let localPoint = convert(point, from: superview)
    if let sibling = interactiveSibling,
      convert(sibling.bounds, from: sibling).contains(localPoint)
    {
      return nil
    }
    guard !Self.edges(at: localPoint, in: bounds).isEmpty else { return nil }

    return self
  }

  /// Cursor rectangles are only consulted for the key window, and a floating
  /// nonactivating palette is usually not it: the bands would show the plain
  /// arrow for the whole time a document window has focus, and the resize
  /// would ship with nothing to find it by. Tracking areas set to
  /// `.activeAlways` change the pointer either way.
  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    for area in trackingAreas {
      removeTrackingArea(area)
    }

    for band in Self.cursorBands(in: bounds) {
      addTrackingArea(
        NSTrackingArea(
          rect: band.rect,
          // A resize calls this back with the pointer inside the band it is
          // being dragged by. Without `.assumeInside` the replacement area
          // is never entered and so never exited, and the resize cursor
          // stays on over the palette once the drag ends.
          options: [.cursorUpdate, .activeAlways, .assumeInside],
          owner: self,
          userInfo: [CursorBand.cursorKey: band.cursor]
        )
      )
    }
  }

  override func cursorUpdate(with event: NSEvent) {
    guard let cursor = event.trackingArea?.userInfo?[CursorBand.cursorKey] as? NSCursor else {
      super.cursorUpdate(with: event)
      return
    }

    cursor.set()
  }

  /// Where the pointer changes shape, which is not quite where a drag is
  /// picked up: the bands here do not overlap, so a corner reads as one
  /// thing rather than as whichever region was added last.
  ///
  /// The corner belongs to the bottom band and shows the vertical arrow,
  /// while a drag from it still resizes both edges — AppKit publishes no
  /// diagonal resize cursor to say so.
  static func cursorBands(in bounds: NSRect) -> [CursorBand] {
    let band = bandWidth
    let sideY = bounds.minY + band
    let sideHeight = max(0, bounds.height - band)

    return [
      CursorBand(
        rect: NSRect(x: bounds.minX, y: sideY, width: band, height: sideHeight),
        cursor: .resizeLeftRight
      ),
      CursorBand(
        rect: NSRect(x: bounds.maxX - band, y: sideY, width: band, height: sideHeight),
        cursor: .resizeLeftRight
      ),
      CursorBand(
        rect: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: band),
        cursor: .resizeUpDown
      ),
    ]
  }

  struct CursorBand {
    static let cursorKey = "cursor"

    let rect: NSRect
    let cursor: NSCursor
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  /// The title bar above this view moves the panel on mouse-down; a band has
  /// to keep the press for itself to resize with it.
  override var mouseDownCanMoveWindow: Bool { false }

  override func mouseDown(with event: NSEvent) {
    guard let window else { return }

    let edges = Self.edges(at: convert(event.locationInWindow, from: nil), in: bounds)
    guard !edges.isEmpty else { return }

    drag = ResizeDrag(
      edges: edges,
      startFrame: window.frame,
      startLocation: window.convertPoint(toScreen: event.locationInWindow)
    )
  }

  override func mouseDragged(with event: NSEvent) {
    guard let drag, let window else { return }

    // Screen coordinates, because resizing from a leading or bottom edge
    // moves the window's own origin out from under the pointer.
    let location = window.convertPoint(toScreen: event.locationInWindow)
    let frame = Self.resizedFrame(
      drag.startFrame,
      edges: drag.edges,
      translation: NSSize(
        width: location.x - drag.startLocation.x,
        height: location.y - drag.startLocation.y
      ),
      minimum: Self.frameSize(forContentSize: window.contentMinSize, of: window),
      maximum: Self.frameSize(forContentSize: window.contentMaxSize, of: window)
    )

    window.setFrame(frame, display: true)
  }

  override func mouseUp(with event: NSEvent) {
    drag = nil
  }

  /// The bands a point lies on, empty everywhere else. The top is missing on
  /// purpose: the title bar owns it, and dragging it moves the panel.
  static func edges(at point: NSPoint, in bounds: NSRect) -> Edges {
    guard bounds.contains(point) else { return [] }

    let bandWidth = Self.bandWidth

    var edges = Edges()
    if point.x - bounds.minX <= bandWidth {
      edges.insert(.left)
    }
    if bounds.maxX - point.x <= bandWidth {
      edges.insert(.right)
    }
    if point.y - bounds.minY <= bandWidth {
      edges.insert(.bottom)
    }

    return edges
  }

  /// The edges opposite the dragged ones stay put, so the palette grows away
  /// from the pointer rather than sliding under it. The top edge is opposite
  /// every band there is, which is what keeps the title bar in place.
  static func resizedFrame(
    _ startFrame: NSRect,
    edges: Edges,
    translation: NSSize,
    minimum: NSSize,
    maximum: NSSize
  ) -> NSRect {
    var width = startFrame.width
    if edges.contains(.left) {
      width -= translation.width
    }
    if edges.contains(.right) {
      width += translation.width
    }

    var height = startFrame.height
    if edges.contains(.bottom) {
      height -= translation.height
    }

    width = clamped(width, minimum: minimum.width, maximum: maximum.width)
    height = clamped(height, minimum: minimum.height, maximum: maximum.height)

    return NSRect(
      x: edges.contains(.left) ? startFrame.maxX - width : startFrame.minX,
      y: startFrame.maxY - height,
      width: width,
      height: height
    )
  }

  /// A maximum below the minimum would otherwise pin the palette under the
  /// size it needs; an unset one is already larger than any screen.
  private static func clamped(
    _ value: CGFloat,
    minimum: CGFloat,
    maximum: CGFloat
  ) -> CGFloat {
    min(max(value, minimum), max(minimum, maximum))
  }

  private static func frameSize(forContentSize contentSize: NSSize, of window: NSWindow) -> NSSize {
    window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
  }
}
