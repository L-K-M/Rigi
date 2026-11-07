import AppKit

/// One app-global attached or floating presentation for a palette kind.
///
/// The floating form lives in a palette group's panel, possibly as one of
/// several tabs; ``PaletteCenter`` arranges the groups. A palette is also a
/// ``TearOffPalette``, so a ``TryOnPopover`` can tear off into it.
@MainActor
public final class Palette: NSObject, NSPopoverDelegate, TearOffPalette {
  // Preserve the public raw name used by pre-Rigi SionKit observers.
  public static let presentationDidChangeNotification = Notification.Name(
    "SionKitPalettePresentationDidChange"
  )

  public let kind: PaletteKind
  public private(set) var presentation: PalettePresentation?

  public var isPresented: Bool { presentation != nil }
  public var isFloating: Bool { presentation == .panel }

  /// The attached form while it exists. Module-internal; tests read it.
  var presentedPopover: NSPopover? { popover }

  /// The size this palette was registered with. Module-internal; tests read it.
  var definitionContentSize: NSSize { definition.contentSize }

  private enum PopoverFollowUp: Equatable {
    case closePanel
    case showPanel
  }

  let definition: PaletteDefinition

  /// Whether a palette group's panel hosts this palette: floating, or
  /// prepared for a tear-off that is under way.
  var occupiesPanel: Bool { presentation == .panel || detachmentPrepared }

  /// The floating form's body, once it has been made.
  var panelContentViewController: NSViewController? { panelContent?.viewController }

  /// The floating form's palette menu, if its content offers one with
  /// something in it.
  var panelMenu: NSMenu? {
    guard let menu = panelContent?.menu, !menu.items.isEmpty else { return nil }
    return menu
  }

  /// The panel the floating form shows in. Module-internal; tests read it.
  var hostingPanel: PalettePanel? { dock.panel(showing: self) }

  private let makeContent: @MainActor () -> AnyPaletteContent
  private let dock: PaletteDock

  private var popover: NSPopover?
  private var popoverContent: AnyPaletteContent?
  private var panelContent: AnyPaletteContent?
  private var detachmentPrepared = false
  private var popoverFollowUp: PopoverFollowUp?

  /// A palette made outside ``PaletteCenter`` gets a dock of its own that
  /// keeps its layout in memory.
  init<Content: PaletteContent>(
    definition: PaletteDefinition,
    target: @escaping @MainActor () -> Content.Target?,
    makeContent: @escaping @MainActor () -> Content,
    dock: PaletteDock? = nil
  ) {
    kind = definition.kind
    self.definition = definition
    self.makeContent = {
      AnyPaletteContent(content: makeContent(), target: target)
    }
    self.dock = dock ?? PaletteDock(store: .memory())

    super.init()

    self.dock.register(self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(chromeSchemeDidChange(_:)),
      name: .classicChromeSchemeDidChange, object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  /// A scheme change reaches an open popover through its appearance and a
  /// repaint of the content tree; the panel form is covered by the window
  /// walk in `ClassicChromeRefresh`.
  @objc private func chromeSchemeDidChange(_ note: Notification) {
    popover?.appearance = ClassicChrome.schemeAppearance
    ClassicChromeRefresh.refresh(popover?.contentViewController?.view)
  }

  /// Shows the attached form, or raises the existing floating form.
  public func present(
    relativeTo positioningRect: NSRect,
    of anchor: NSView,
    preferredEdge: NSRectEdge = .maxY
  ) {
    guard anchor.window != nil else { return }

    if presentation == .panel {
      retarget()
      dock.bringToFront(self)
      return
    }

    guard popover == nil else { return }

    let content = newContent()
    content.retarget()
    definition.applyContentSizing(to: content.viewController)

    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
    popover.appearance = ClassicChrome.schemeAppearance
    // Attaching a content view controller re-derives the popover's size from
    // it, so the requested size is applied afterwards and wins either way.
    popover.contentViewController = content.viewController
    popover.contentSize = definition.contentSize
    popover.delegate = self

    self.popover = popover
    popoverContent = content
    popover.show(relativeTo: positioningRect, of: anchor, preferredEdge: preferredEdge)

    transition(to: .popover)
    content.presented(as: .popover)
    focusInitialResponder(in: content)
  }

  public func present(from anchor: NSView, preferredEdge: NSRectEdge = .maxY) {
    present(relativeTo: anchor.bounds, of: anchor, preferredEdge: preferredEdge)
  }

  /// Opens the floating form without first showing a popover.
  public func showPanel() {
    if popover != nil {
      popoverFollowUp = .showPanel
      popover?.close()
      return
    }

    showPanelNow()
  }

  /// Raises the floating form, selecting its tab and expanding its group.
  public func bringToFront() {
    guard presentation == .panel else { return }

    retarget()
    dock.bringToFront(self)
  }

  public func close() {
    // A detached panel can briefly coexist with its closing popover.
    if let popover {
      popoverFollowUp = occupiesPanel ? .closePanel : nil
      popover.close()
      return
    }

    popoverFollowUp = nil
    closePanel()
  }

  /// Re-resolves the target after front-document or selection changes.
  public func retarget() {
    if presentation == .popover {
      popoverContent?.retarget()
    }

    if presentation == .panel || detachmentPrepared {
      panelContent?.retarget()
      // A content may offer a menu only for some targets.
      dock.paletteMenuMayHaveChanged(self)
    }
  }

  public func popoverShouldDetach(_ popover: NSPopover) -> Bool {
    true
  }

  public func detachableWindow(for popover: NSPopover) -> NSWindow? {
    // AppKit places the returned panel at the end of the drag.
    prepareDetachment()
  }

  // MARK: TearOffPalette

  public var isShowingPanel: Bool { dock.isShowingPanel(self) }

  /// Prepares the floating form for a ``TryOnPopover`` tear-off. The body
  /// resolves its selection from the target, so `id` is not consulted.
  public func windowForDetach(selecting id: String?) -> NSWindow {
    prepareDetachment()
  }

  public func didDetach() {
    completeDetachment()
  }

  public func cancelDetach() {
    discardPreparedDetachment()
  }

  public func popoverDidClose(_ notification: Notification) {
    let detached = didDetach(notification)
    let followUp = popoverFollowUp

    popoverFollowUp = nil
    dismissPopover()

    if detached {
      completeDetachment()
      if followUp == .closePanel {
        closePanel()
      }
      return
    }

    discardPreparedDetachment()
    transition(to: nil)

    switch followUp {
    case .closePanel:
      closePanel()
    case .showPanel:
      showPanelNow()
    case nil:
      break
    }
  }

  private func closePanel() {
    guard occupiesPanel else { return }

    // Closed while a tear-off is still pending: the drag never landed, so
    // the layout it set up goes back as an abandoned drag's would.
    let abandonsDetachment = detachmentPrepared

    if presentation == .panel {
      panelContent?.dismissed(from: .panel)
    }

    detachmentPrepared = false
    panelContent?.releaseTarget()
    transition(to: nil)
    if abandonsDetachment {
      dock.cancelDetachment(self)
    } else {
      dock.didClose(self)
    }
  }

  private func showPanelNow() {
    let content = ensurePanelContent()

    content.retarget()

    if presentation != .panel {
      content.presented(as: .panel)
      transition(to: .panel)
    }

    dock.show(self)
  }

  private func prepareDetachment() -> NSWindow {
    // A floating palette's chooser raises it rather than tearing it off
    // (see the tear-off contract), so a request for one raises it, hidden
    // or not, and lends the panel it is in, leaving the layout alone.
    if presentation == .panel, let panel = dock.panel(showing: self) {
      bringToFront()
      return panel
    }

    let content = ensurePanelContent()

    content.retarget()
    detachmentPrepared = true

    return dock.prepareDetachment(self)
  }

  private func ensurePanelContent() -> AnyPaletteContent {
    if let panelContent { return panelContent }

    let content = newContent()
    panelContent = content
    return content
  }

  private func newContent() -> AnyPaletteContent {
    let content = makeContent()

    precondition(
      content.viewController !== popoverContent?.viewController
        && content.viewController !== panelContent?.viewController,
      "A palette content factory must create distinct view controllers"
    )

    if content.viewController.title?.isEmpty ?? true {
      content.viewController.title = definition.title
    }

    return content
  }

  private func dismissPopover() {
    popoverContent?.dismissed(from: .popover)
    popoverContent?.releaseTarget()
    popover?.contentViewController = nil
    popoverContent = nil
    popover = nil
  }

  private func completeDetachment() {
    guard detachmentPrepared else { return }

    detachmentPrepared = false
    panelContent?.retarget()

    if presentation != .panel {
      panelContent?.presented(as: .panel)
      transition(to: .panel)
    }

    dock.show(self)
  }

  private func discardPreparedDetachment() {
    guard detachmentPrepared else { return }

    detachmentPrepared = false
    panelContent?.releaseTarget()
    dock.cancelDetachment(self)
  }

  private func didDetach(_ notification: Notification) -> Bool {
    let reason = notification.userInfo?[NSPopover.closeReasonUserInfoKey]
    let reasonIsDetach =
      (reason as? NSPopover.CloseReason) == .detachToWindow
      || (reason as? String) == NSPopover.CloseReason.detachToWindow.rawValue

    return detachmentPrepared && (reasonIsDetach || dock.isShowingPanel(self))
  }

  private func focusInitialResponder(in content: AnyPaletteContent) {
    guard let responder = content.preferredFirstResponder else { return }
    guard responder.window === content.viewController.view.window else { return }

    responder.window?.makeFirstResponder(responder)
  }

  private func transition(to newPresentation: PalettePresentation?) {
    guard presentation != newPresentation else { return }

    presentation = newPresentation
    NotificationCenter.default.post(
      name: Self.presentationDidChangeNotification,
      object: self
    )
  }
}
