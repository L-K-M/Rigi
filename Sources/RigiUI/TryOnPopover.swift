import AppKit

/// Application-owned destination for a picker's tear-off. The application owns
/// item semantics and document edits; Rigi owns presentation and dismissal.
@MainActor
public protocol TearOffPalette: AnyObject {
    var isShowingPanel: Bool { get }
    func windowForDetach(selecting id: String?) -> NSWindow
    func didDetach()
    /// The drag `windowForDetach` prepared for ended without tearing off.
    func cancelDetach()
}

extension TearOffPalette {
    public func cancelDetach() {}
}

// The attached "try-on" picker: a transient popover anchored to one of the
// format bar's chooser controls (typeface or paragraph style). Moving the
// selection (arrow keys, clicks, or filtering) applies the candidate to the
// document live WITHOUT closing the picker, so you can flip through faces or
// styles and watch your actual letter change. Return or double-click keeps the
// current pick, Esc reverts to where you started, and clicking outside keeps
// whatever you were trying. The whole session lands as a single undo step
// supplied by the application's editor adapter.
//
// Dragging the popover off its control hands the session to the app-global
// palette adapter: the attached browsing is banked as one undo
// (onDetach), AppKit closes the popover, and the palette window — returned from
// detachableWindow(for:) — appears under the drag in its place.
@MainActor
public final class TryOnPopover: NSObject, NSPopoverDelegate {

    public enum Outcome { case commit, cancel }

    private let list: PickerListView
    /// Reduce Motion source, read at each presentation and while the popover
    /// is open. Never cached at launch; the default is the live workspace
    /// setting.
    private let reduceMotion: @MainActor () -> Bool
    private var popover: NSPopover?
    private var palette: TearOffPalette?
    private weak var anchor: NSView?
    private weak var invokingWindow: NSWindow?
    private weak var invokingResponder: NSResponder?
    private var onPreview: ((PickerItem) -> Void)?  // live, single-undo session
    private var onDetach: (() -> Void)?             // bank the session before the palette takes over
    private var onFinish: ((Outcome) -> Void)?     // end the session + refocus
    private var finished = false
    private var detachRequested = false

    public convenience init(hint: String) {
        self.init(hint: hint, reduceMotion: {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        })
    }

    /// `reduceMotion` is the per-instance Reduce Motion source. Tests inject
    /// a forced value through this internal initializer; the default reads
    /// the live workspace setting on every call.
    init(hint: String, reduceMotion: @escaping @MainActor () -> Bool) {
        self.reduceMotion = reduceMotion
        list = PickerListView(hint: hint)
        super.init()
        list.onPick = { [weak self] item in self?.onPreview?(item) }
        list.onCommit = { [weak self] in self?.finish(.commit) }
        list.onCancel = { [weak self] in self?.finish(.cancel) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(chromeSchemeDidChange(_:)),
            name: .classicChromeSchemeDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// A scheme change reaches an open popover through its appearance and a
    /// repaint of the content tree.
    @objc private func chromeSchemeDidChange(_ note: Notification) {
        popover?.appearance = ClassicChrome.schemeAppearance
        ClassicChromeRefresh.refresh(popover?.contentViewController?.view)
    }

    /// True while the popover is on screen; the toolbar guards on this so it
    /// never starts a second preview session over a running one.
    public var isActive: Bool { popover != nil }

    // Native integration tests inspect the presented container without making
    // presentation internals part of the public API.
    var presentedPopover: NSPopover? { popover }

    public func present(from anchor: NSView, palette: TearOffPalette?,
                 items: [PickerItem], currentID: String?,
                 specimenFont: @escaping (PickerItem) -> NSFont,
                 onPreview: @escaping (PickerItem) -> Void,
                 onDetach: @escaping () -> Void,
                  onFinish: @escaping (Outcome) -> Void) {
        guard popover == nil else { return }
        self.anchor = anchor
        invokingWindow = anchor.window
        let responder = anchor.window?.firstResponder
        // AppKit lends one field editor to text controls. Restore through its
        // owner, since the field editor can be detached before we dismiss.
        if let editor = responder as? NSTextView, editor.isFieldEditor,
           let owner = editor.delegate as? NSView {
            invokingResponder = owner
        } else {
            invokingResponder = responder
        }
        self.palette = palette
        self.onPreview = onPreview
        self.onDetach = onDetach
        self.onFinish = onFinish
        finished = false

        list.specimenFont = specimenFont
        list.clearFilter()
        list.setItems(items)

        let pop = NSPopover()
        pop.behavior = .transient    // .transient + popoverShouldDetach → draggable tear-off
        pop.appearance = ClassicChrome.schemeAppearance
        let controller = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 400))
        list.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: container.topAnchor),
            list.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        controller.view = container
        pop.contentViewController = controller
        pop.contentSize = NSSize(width: 280, height: 400)
        pop.delegate = self
        popover = pop
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)

        list.select(id: currentID)
        list.focusFilter()
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        restoreFocus()
        onFinish?(outcome)
        popover?.close()
    }

    /// Restore the editor, not its chooser. A click-away may already have
    /// selected another editor; never undo that choice or activate a window.
    private func restoreFocus() {
        guard let window = invokingWindow, let responder = invokingResponder,
              anchor?.window === window else { return }
        if let view = responder as? NSView, view.window !== window { return }
        if let current = window.firstResponder,
           current !== responder && current !== anchor && current !== window {
            guard let editor = current as? NSTextView, editor.isFieldEditor,
                  editor.delegate as? NSView === responder else { return }
        }
        window.makeFirstResponder(responder)
    }

    // MARK: - Tear-off → hand the session to the global palette

    // Only choosers backed by a floating palette can tear off; a palette-less
    // picker (e.g. list styles) previews in place and can't be floated.
    public func popoverShouldDetach(_ popover: NSPopover) -> Bool { palette != nil }

    public func detachableWindow(for popover: NSPopover) -> NSWindow? {
        // Configure-only: the detach commits (or doesn't) in popoverDidClose.
        detachRequested = true
        return palette?.windowForDetach(selecting: list.selectedItem?.id)
    }

    public func popoverDidClose(_ notification: Notification) {
        defer { teardown() }
        guard !finished else {            // Return/Esc already ended the session
            cancelRequestedDetach()
            return
        }
        finished = true
        // Did this close hand the session to the palette (tear-off), or was it a
        // plain click-away? The close reason is authoritative, but the panel
        // visibility fallback only counts when a detachment was prepared.
        let reason = notification.userInfo?[NSPopover.closeReasonUserInfoKey]
        let reasonIsDetach = (reason as? NSPopover.CloseReason) == .detachToWindow
            || (reason as? String) == NSPopover.CloseReason.detachToWindow.rawValue
        let detached = detachRequested && (reasonIsDetach || palette?.isShowingPanel == true)
        if detached {
            onDetach?()           // bank the attached browsing as one undo step
            palette?.didDetach()
        } else {
            cancelRequestedDetach()
        }
        // Click-away keeps the try-on; after a tear-off this is a no-op end plus
        // the control re-sync and page refocus.
        if !detached { restoreFocus() }
        onFinish?(.commit)
    }

    /// A drag that asked the palette for its window but did not tear off.
    private func cancelRequestedDetach() {
        guard detachRequested else { return }
        detachRequested = false
        palette?.cancelDetach()
    }

    private func teardown() {
        detachRequested = false
        popover = nil
        palette = nil
        anchor = nil
        invokingWindow = nil
        invokingResponder = nil
        onPreview = nil
        onDetach = nil
        onFinish = nil
    }
}
