import AppKit

private enum PaletteMetrics {
  /// Past any display, but stated rather than left to whatever an unset
  /// `contentMaxSize` reports: the drag below clamps against it.
  static let maximumContentSize = NSSize(width: 10_000, height: 10_000)
}

/// Classic chrome around a borderless palette panel, hosting the body of
/// whichever palette the panel's group shows.
@MainActor
final class PalettePanelViewController: NSViewController {
  var onClose: (@MainActor () -> Void)? {
    didSet { chrome.onClose = onClose }
  }

  let chrome: PaletteChromeView
  private(set) var embeddedController: NSViewController?
  private var declaredContentSize: NSSize
  private var isCollapsed = false

  init(title: String, contentSize: NSSize) {
    declaredContentSize = contentSize
    chrome = PaletteChromeView(title: title)

    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func loadView() {
    view = chrome
  }

  /// Shows `controller`'s view as the panel body, declared at `contentSize`.
  func embed(_ controller: NSViewController, contentSize: NSSize) {
    declaredContentSize = contentSize

    if embeddedController !== controller {
      removeEmbeddedController()
    }
    if controller.parent !== self {
      // A tab moving between groups arrives still parented to its old panel.
      controller.removeFromParent()
      addChild(controller)
    }
    embeddedController = controller

    guard !isCollapsed else { return }

    chrome.embedContent(controller.view)
    chrome.applyDeclaredContentSize(contentSize)
  }

  /// Lets go of the body, leaving the panel empty.
  func removeEmbeddedController() {
    guard let controller = embeddedController else { return }

    if controller.view.superview === chrome {
      chrome.removeEmbeddedContent()
    }
    if controller.parent === self {
      controller.removeFromParent()
    }
    embeddedController = nil
  }

  /// A collapsed panel is its title bar alone; the body leaves the chrome,
  /// rather than squeezing to nothing under constraints it cannot meet.
  func setCollapsed(_ collapsed: Bool) {
    guard collapsed != isCollapsed else { return }

    isCollapsed = collapsed
    guard let controller = embeddedController else { return }

    if collapsed {
      if controller.view.superview === chrome {
        chrome.removeEmbeddedContent()
      }
    } else {
      chrome.embedContent(controller.view)
      chrome.applyDeclaredContentSize(declaredContentSize)
    }
  }
}

/// How a palette panel may be sized while it shows a given palette.
enum PalettePanelSizing: Equatable {
  /// Exactly this content size.
  case fixed(NSSize)
  /// At least this content size, from the side and bottom bands.
  case resizable(minimumContentSize: NSSize)
  /// The title bar alone, at this content width.
  case collapsed(width: CGFloat)
}

/// A nonactivating utility window that becomes key only for controls that need it.
///
/// One panel serves a palette group: it shows the selected palette's body
/// and takes that palette's size limits. Its frame persists in the palette
/// layout rather than under a window autosave name.
@MainActor
final class PalettePanel: ClassicPaletteWindow {
  /// The prefix a definition's frame autosave name falls back to when it does
  /// not carry one of its own. Frames saved under these names before palette
  /// groups existed seed a group's first placement.
  static let defaultFrameAutosavePrefix = "Rigi.palette."

  /// The close dot, Escape and Command-W, which close the whole group.
  var onCloseRequest: (@MainActor () -> Void)? {
    didSet { paletteViewController.onClose = onCloseRequest }
  }

  var chrome: PaletteChromeView { paletteViewController.chrome }

  private let paletteViewController: PalettePanelViewController

  init(title: String, contentSize: NSSize) {
    let panelSize = Self.panelSize(forContentSize: contentSize)
    paletteViewController = PalettePanelViewController(title: title, contentSize: contentSize)

    super.init(contentSize: panelSize, styleMask: [.borderless, .closable, .nonactivatingPanel])

    self.title = title
    isMovable = true

    // The chrome is the content view rather than the window's content view
    // controller: AppKit pins a window to its content view controller's
    // preferred size, above the priority a frame change holds at, which
    // would undo every resize, collapse and tab switch.
    contentView = paletteViewController.view
    apply(.fixed(contentSize))
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

  /// The content area inside a panel frame of `size`; the inverse of
  /// ``panelSize(forContentSize:)``.
  static func contentSize(forPanelSize size: NSSize) -> NSSize {
    NSSize(
      width: max(0, size.width - 2 * PaletteChromeView.contentInset),
      height: max(0, size.height - PaletteChromeView.titleBarHeight - PaletteChromeView.contentInset)
    )
  }

  override func performClose(_ sender: Any?) {
    requestClose()
  }

  override func cancelOperation(_ sender: Any?) {
    requestClose()
  }

  func embed(_ controller: NSViewController, contentSize: NSSize) {
    paletteViewController.embed(controller, contentSize: contentSize)
  }

  func removeEmbeddedContent() {
    paletteViewController.removeEmbeddedController()
  }

  var embeddedController: NSViewController? { paletteViewController.embeddedController }

  /// Sets the style mask, resize bands and size limits for `sizing`. The
  /// frame itself is the caller's to set: limits alone never move a window.
  func apply(_ sizing: PalettePanelSizing) {
    switch sizing {
    case .fixed(let contentSize):
      styleMask.remove(.resizable)
      chrome.setResizeBorderEnabled(false)
      paletteViewController.setCollapsed(false)
      contentMinSize = Self.panelSize(forContentSize: contentSize)
      contentMaxSize = contentMinSize

    case .resizable(let minimumContentSize):
      styleMask.insert(.resizable)
      chrome.setResizeBorderEnabled(true)
      paletteViewController.setCollapsed(false)
      contentMinSize = Self.panelSize(forContentSize: minimumContentSize)
      contentMaxSize = PaletteMetrics.maximumContentSize

    case .collapsed(let width):
      styleMask.remove(.resizable)
      chrome.setResizeBorderEnabled(false)
      paletteViewController.setCollapsed(true)
      contentMinSize = Self.panelSize(forContentSize: NSSize(width: width, height: 0))
      contentMaxSize = contentMinSize
    }
  }

  private func requestClose() {
    if let onCloseRequest {
      onCloseRequest()
    } else {
      close()
    }
  }

  /// A frame saved under `name` by NSWindow's frame autosave, which palettes
  /// used before the layout kept their frames. The string starts with the
  /// window frame as "x y width height"; the screen frame follows.
  static func legacySavedFrame(named name: String, in defaults: UserDefaults = .standard) -> NSRect? {
    guard let string = defaults.string(forKey: "NSWindow Frame \(name)") else { return nil }

    let values = string.split(separator: " ").prefix(4).compactMap { Double($0) }
    guard values.count == 4, values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0 else {
      return nil
    }
    return NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
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
