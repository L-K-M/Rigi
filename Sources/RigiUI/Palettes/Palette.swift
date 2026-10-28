import AppKit

/// One app-global attached or floating presentation for a palette kind.
@MainActor
public final class Palette: NSObject, NSPopoverDelegate, NSWindowDelegate {
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

  private let definition: PaletteDefinition
  private let makeContent: @MainActor () -> AnyPaletteContent

  private var popover: NSPopover?
  private var popoverContent: AnyPaletteContent?
  private var panel: PalettePanel?
  private var panelContent: AnyPaletteContent?
  private var detachmentPrepared = false
  private var popoverFollowUp: PopoverFollowUp?

  init<Content: PaletteContent>(
    definition: PaletteDefinition,
    target: @escaping @MainActor () -> Content.Target?,
    makeContent: @escaping @MainActor () -> Content
  ) {
    kind = definition.kind
    self.definition = definition
    self.makeContent = {
      AnyPaletteContent(content: makeContent(), target: target)
    }

    super.init()
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
      panel?.orderFront(nil)
      return
    }

    guard popover == nil else { return }

    let content = newContent()
    content.retarget()
    definition.applyContentSizing(to: content.viewController)

    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
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

  public func bringToFront() {
    guard presentation == .panel else { return }

    retarget()
    panel?.orderFront(nil)
  }

  public func close() {
    // A detached panel can briefly coexist with its closing popover.
    let hasPresentedPanel = presentation == .panel || panel?.isVisible == true
    if let popover {
      popoverFollowUp = hasPresentedPanel ? .closePanel : nil
      popover.close()
      return
    }

    popoverFollowUp = nil
    panel?.close()
  }

  /// Re-resolves the target after front-document or selection changes.
  public func retarget() {
    if presentation == .popover {
      popoverContent?.retarget()
    }

    if presentation == .panel || detachmentPrepared {
      panelContent?.retarget()
    }
  }

  public func popoverShouldDetach(_ popover: NSPopover) -> Bool {
    true
  }

  public func detachableWindow(for popover: NSPopover) -> NSWindow? {
    let panel = ensurePanel()
    let content = ensurePanelContent()

    content.retarget()
    detachmentPrepared = true

    // AppKit places the returned panel at the end of the drag.
    return panel
  }

  public func popoverDidClose(_ notification: Notification) {
    let detached = didDetach(notification)
    let followUp = popoverFollowUp

    popoverFollowUp = nil
    dismissPopover()

    if detached {
      completeDetachment()
      if followUp == .closePanel {
        panel?.close()
      }
      return
    }

    discardPreparedDetachment()
    transition(to: nil)

    switch followUp {
    case .closePanel:
      panel?.close()
    case .showPanel:
      showPanelNow()
    case nil:
      break
    }
  }

  public func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === panel else { return }

    if presentation == .panel {
      panelContent?.dismissed(from: .panel)
    }

    detachmentPrepared = false
    panelContent?.releaseTarget()
    transition(to: nil)
  }

  private func showPanelNow() {
    let panel = ensurePanel()
    let content = ensurePanelContent()

    content.retarget()

    if presentation != .panel {
      content.presented(as: .panel)
      transition(to: .panel)
    }

    panel.orderFront(nil)
  }

  private func ensurePanel() -> PalettePanel {
    if let panel { return panel }

    let panel = PalettePanel(definition: definition)
    panel.delegate = self
    panel.setCloseHandler { [weak self] in
      self?.close()
    }

    self.panel = panel
    return panel
  }

  private func ensurePanelContent() -> AnyPaletteContent {
    if let panelContent { return panelContent }

    let content = newContent()
    ensurePanel().embed(content.viewController)
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

    panel?.orderFront(nil)
    panel?.invalidateShadow()
  }

  private func discardPreparedDetachment() {
    guard detachmentPrepared else { return }

    detachmentPrepared = false
    panelContent?.releaseTarget()
    panel?.orderOut(nil)
  }

  private func didDetach(_ notification: Notification) -> Bool {
    let reason = notification.userInfo?[NSPopover.closeReasonUserInfoKey]
    let reasonIsDetach =
      (reason as? NSPopover.CloseReason) == .detachToWindow
      || (reason as? String) == NSPopover.CloseReason.detachToWindow.rawValue

    return detachmentPrepared && (reasonIsDetach || panel?.isVisible == true)
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
