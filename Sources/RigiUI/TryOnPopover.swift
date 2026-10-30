import AppKit

/// Application-owned destination for a picker's tear-off. The application owns
/// item semantics and document edits; Rigi owns presentation and dismissal.
@MainActor
public protocol TearOffPalette: AnyObject {
    var isShowingPanel: Bool { get }
    func windowForDetach(selecting id: String?) -> NSWindow
    func didDetach()
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
    private var popover: NSPopover?
    private var palette: TearOffPalette?
    /// The control the picker was presented from; focus returns to it on close
    /// (interface guidelines: closing a picker returns focus to the invoking
    /// editor, chonk finding 18).
    private weak var anchor: NSView?
    private var onPreview: ((PickerItem) -> Void)?  // live, single-undo session
    private var onDetach: (() -> Void)?             // bank the session before the palette takes over
    private var onFinish: ((Outcome) -> Void)?     // end the session + refocus
    private var finished = false

    public init(hint: String) {
        list = PickerListView(hint: hint)
        super.init()
        list.onPick = { [weak self] item in self?.onPreview?(item) }
        list.onCommit = { [weak self] in self?.finish(.commit) }
        list.onCancel = { [weak self] in self?.finish(.cancel) }
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
        pop.appearance = NSAppearance(named: .aqua)
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
        onFinish?(outcome)
        popover?.close()
        restoreFocus()
    }

    /// Closing or committing an attached picker returns focus to the invoking
    /// control (guidelines §"Pickers": the editor keeps keyboard focus).
    private func restoreFocus() {
        guard let anchor, let window = anchor.window else { return }
        window.makeFirstResponder(anchor)
    }

    // MARK: - Tear-off → hand the session to the global palette

    // Only choosers backed by a floating palette can tear off; a palette-less
    // picker (e.g. list styles) previews in place and can't be floated.
    public func popoverShouldDetach(_ popover: NSPopover) -> Bool { palette != nil }

    public func detachableWindow(for popover: NSPopover) -> NSWindow? {
        // Configure-only: the detach commits (or doesn't) in popoverDidClose.
        palette?.windowForDetach(selecting: list.selectedItem?.id)
    }

    public func popoverDidClose(_ notification: Notification) {
        defer { teardown() }
        guard !finished else { return }   // Return/Esc already ended the session
        finished = true
        // Did this close hand the session to the palette (tear-off), or was it a
        // plain click-away? Check the documented close reason, with the panel's
        // actual visibility as a fallback signal.
        let reason = notification.userInfo?[NSPopover.closeReasonUserInfoKey]
        let detached = (reason as? NSPopover.CloseReason) == .detachToWindow
            || (reason as? String) == NSPopover.CloseReason.detachToWindow.rawValue
            || palette?.isShowingPanel == true
        if detached {
            onDetach?()           // bank the attached browsing as one undo step
            palette?.didDetach()
        }
        // Click-away keeps the try-on; after a tear-off this is a no-op end plus
        // the control re-sync and page refocus.
        onFinish?(.commit)
        restoreFocus()
    }

    private func teardown() {
        popover = nil
        palette = nil
        anchor = nil
        onPreview = nil
        onDetach = nil
        onFinish = nil
    }
}
