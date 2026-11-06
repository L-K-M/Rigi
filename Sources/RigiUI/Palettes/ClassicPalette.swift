import AppKit

// The floating palette's window and chrome: a borderless, non-activating NSPanel
// that floats above document windows and hides while the app is inactive — the
// classic utility-palette contract — and the view that draws its own half-height
// classic title bar, since a borderless window has no title bar of its own.

/// The floating palette's window: borderless (the chrome draws its own classic
/// half-height title bar), non-activating so clicks never pull focus from the
/// document, floating above document windows, and hidden while the app is
/// inactive — the classic utility-palette contract.
public class ClassicPaletteWindow: NSPanel {

    /// A panel-local undo manager (a palette's own "best-effort" stack for
    /// edits that should not join the front document's undo history). nil
    /// routes ⌘Z as usual.
    public var paletteUndoManager: UndoManager?

    public override var undoManager: UndoManager? { paletteUndoManager ?? super.undoManager }

    public init(contentSize: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        configureClassicPalettePanel()
    }

    /// The style mask is fixed at construction, so panels inside the module
    /// that need extra bits — the generic palette panel adds `.closable` —
    /// state theirs here on the same shell.
    init(contentSize: NSSize, styleMask: NSWindow.StyleMask) {
        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: styleMask,
                   backing: .buffered, defer: false)
        configureClassicPalettePanel()
    }

    private func configureClassicPalettePanel() {
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        appearance = NSAppearance(named: .aqua)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Borderless windows refuse key status by default; palette controls (a
    // filter field, the close button) need it. becomesKeyOnlyIfNeeded keeps
    // ordinary clicks from grabbing it.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

// MARK: - Palette chrome

/// Draws the palette's classic shell: the ClassicWindow silhouette with a
/// tighter top radius (a small panel reads better with less sweep), a
/// half-height title bar in the bar gradient with engraved lettering and a
/// small red close dot — the standard close button at palette scale — the
/// panel-gradient body, and a hairline window border. Palettes hide when the
/// app deactivates, so the chrome always draws at full (active) strength.
public final class PaletteChromeView: NSView {

    /// Half the standard title bar — the classic cue that this isn't a document
    /// window.
    public static let titleBarHeight: CGFloat = 16

    /// The inset the chrome keeps between its hairline border and embedded
    /// content, so a full-bleed body never paints over the window edge.
    static let contentInset: CGFloat = 1

    /// Tighter than the document windows' top radius; the bottom keeps the
    /// shared gentle rounding.
    private static let topCornerRadius: CGFloat = 6

    /// Extra hit slop around the close dot, as the old custom tracking had.
    private static let closeButtonSlop: CGFloat = 3

    public var onClose: (@MainActor () -> Void)?
    public var title: String {
        didSet {
            updateCloseButtonAccessibility()
            updateMenuButtonAccessibility()
            needsDisplay = true
        }
    }

    /// The titles of a palette group's tabs, drawn in the title bar in place
    /// of the single centered title. Fewer than two shows the plain title.
    var tabTitles: [String] = [] {
        didSet {
            guard tabTitles != oldValue else { return }
            updateTabAccessibility()
            updateCloseButtonAccessibility()
            needsDisplay = true
        }
    }

    var selectedTabIndex = 0 {
        didSet {
            guard selectedTabIndex != oldValue else { return }
            updateTabAccessibility()
            needsDisplay = true
        }
    }

    /// Takes over title-bar presses — tab picks, moves with snapping, tab
    /// drags, collapse — for the generic palette panel. Without one the bar
    /// drags the window as a plain palette does.
    weak var titleBarDelegate: PaletteTitleBarDelegate?

    /// Shows the menu triangle at the right end of the bar, for a palette
    /// whose content offers a menu.
    var showsMenuButton = false {
        didSet {
            guard showsMenuButton != oldValue else { return }
            updateTabAccessibility()
            needsDisplay = true
        }
    }

    /// Marks the bar as where a dragged palette lands as a tab when dropped.
    var isDropTarget = false {
        didSet {
            guard isDropTarget != oldValue else { return }
            needsDisplay = true
        }
    }

    private let closeButton = PaletteCloseButton(frame: .zero)
    private weak var embeddedView: NSView?
    private var declaredSizeConstraints: [NSLayoutConstraint] = []
    private var resizeBorder: PaletteResizeBorderView?
    private var tabElements: [PaletteTabAccessibilityElement] = []
    private var menuButtonElement: PaletteTabAccessibilityElement?

    public init(title: String) {
        self.title = title
        super.init(frame: .zero)

        closeButton.target = self
        closeButton.action = #selector(closePressed)
        addSubview(closeButton)
        setAccessibilityElement(false)
        updateCloseButtonAccessibility()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Hosts the palette content below the title bar, inset 1 pt at the sides
    /// and bottom so the full-bleed list never paints over the window border.
    /// The content sits below the close button in z-order, keeping the bar's
    /// only control on top.
    public func embedContent(_ view: NSView) {
        guard embeddedView !== view || view.superview !== self else { return }

        removeEmbeddedContent()
        embeddedView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view, positioned: .below, relativeTo: closeButton)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: Self.titleBarHeight),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentInset),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentInset),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentInset)
        ])
    }

    /// A borderless window has no frame view to resize it from, so a resizable
    /// palette grows its own edges: an overlay that claims only a band along
    /// the sides and the bottom and lets every other point through to the
    /// palette below. The top edge is left to the title bar, which drags the
    /// panel.
    /// Takes the embedded body out of the chrome, as a collapsed palette or a
    /// tab moving to another group needs. A body already moved into another
    /// chrome is left where it is.
    func removeEmbeddedContent() {
        if embeddedView?.superview === self {
            embeddedView?.removeFromSuperview()
        }
        // The size pins sit on the body itself, so they would travel with it.
        NSLayoutConstraint.deactivate(declaredSizeConstraints)
        embeddedView = nil
        declaredSizeConstraints = []
    }

    /// Shows or hides the resize bands, installing them on first use; a
    /// palette group is resizable only while a resizable palette is showing.
    func setResizeBorderEnabled(_ enabled: Bool) {
        if enabled, resizeBorder == nil {
            installResizeBorder()
        }
        resizeBorder?.isHidden = !enabled
    }

    var isResizeBorderEnabled: Bool { resizeBorder.map { !$0.isHidden } ?? false }

    func installResizeBorder() {
        guard resizeBorder == nil else { return }

        let border = PaletteResizeBorderView()
        resizeBorder = border
        border.interactiveSibling = closeButton
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: topAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Weakly pins the embedded content to `size`, so the chrome's fitting
    /// size reports the palette's declared size even when the body — a scroll
    /// view, typically — contributes no height of its own: left at that, the
    /// chrome fits its title bar alone and a panel that takes its size from
    /// its content opens as a bare pill.
    ///
    /// The priority sits below `windowSizeStayPut`, so a resizable panel's own
    /// frame still wins once the user drags its edge.
    func applyDeclaredContentSize(_ size: NSSize) {
        guard let view = embeddedView else { return }

        NSLayoutConstraint.deactivate(declaredSizeConstraints)
        declaredSizeConstraints = [
            view.widthAnchor.constraint(equalToConstant: size.width),
            view.heightAnchor.constraint(equalToConstant: size.height)
        ]
        for constraint in declaredSizeConstraints {
            constraint.priority = .defaultLow
        }
        NSLayoutConstraint.activate(declaredSizeConstraints)
    }

    private var titleBarRect: NSRect {
        NSRect(x: 0, y: bounds.height - Self.titleBarHeight,
               width: bounds.width, height: Self.titleBarHeight)
    }

    private var closeBoxRect: NSRect {
        let bar = titleBarRect
        return NSRect(x: 6, y: bar.minY + ((bar.height - 9) / 2).rounded(), width: 9, height: 9)
    }

    public override func layout() {
        super.layout()
        layoutCloseButton()
    }

    // `resizeSubviews` (below, with the title-bar mouse handling) covers
    // constraint-free resizes, `layout` the Auto Layout passes; the dot's
    // button and the tabs' accessibility frames track the bar either way.

    /// A real control over the drawn dot: hit area padded like the old
    /// custom tracking's, so clicks land the same while keyboard focus and
    /// VoiceOver come for free.
    private func layoutCloseButton() {
        closeButton.frame = closeBoxRect.insetBy(
            dx: -Self.closeButtonSlop, dy: -Self.closeButtonSlop)
    }

    /// The dot closes every tab of a group, and says so.
    private func updateCloseButtonAccessibility() {
        if tabTitles.count > 1 {
            closeButton.toolTip = "Close All Tabs"
            closeButton.setAccessibilityLabel("Close all tabs: " + tabTitles.joined(separator: ", "))
        } else {
            closeButton.toolTip = "Close \(title) Palette"
            closeButton.setAccessibilityLabel("Close \(title) palette")
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let silhouette = ClassicChrome.windowSilhouette(in: bounds, top: Self.topCornerRadius)
        NSGraphicsContext.saveGraphicsState()
        silhouette.addClip()

        ClassicChrome.gradient(top: 0.97, bottom: 0.86).draw(in: bounds, angle: 90)

        let bar = titleBarRect
        ClassicChrome.gradient(top: 0.965, bottom: 0.80).draw(in: bar, angle: 90)
        ClassicChrome.barTopHighlight.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        ClassicChrome.barBottomBorder(true).setFill()
        NSRect(x: 0, y: bar.minY, width: bounds.width, height: 1).fill()

        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0.45, alpha: 1).setStroke()
        let border = ClassicChrome.windowSilhouette(in: bounds.insetBy(dx: 0.5, dy: 0.5),
                                                    top: Self.topCornerRadius)
        border.lineWidth = 1
        border.stroke()

        if tabTitles.count > 1 {
            drawTabs(in: bar)
        } else {
            drawTitle(in: bar)
        }

        if showsMenuButton {
            drawMenuButton()
        }

        if isDropTarget {
            drawDropTarget(in: bar)
        }
    }

    // MARK: - Tabs

    /// Tab text sits this far in from either side of its tab.
    private static let tabPadding: CGFloat = 8

    /// Where the tabs start: clear of the close dot and its hit slop.
    private var tabStripMinX: CGFloat { closeBoxRect.maxX + Self.closeButtonSlop + 3 }

    /// Each tab's rectangle in the title bar, left to right. Tabs take their
    /// titles' widths, and share the bar equally once those no longer fit.
    var tabRects: [NSRect] {
        guard tabTitles.count > 1 else { return [] }

        let bar = titleBarRect
        let end = showsMenuButton ? menuButtonRect.minX : bar.maxX - 6
        let available = max(0, end - tabStripMinX)
        let natural = tabTitles.map {
            ceil(ClassicText.engraved($0, size: 10.5, weight: .medium).size().width) + 2 * Self.tabPadding
        }
        let total = natural.reduce(0, +)
        let widths = total <= available
            ? natural
            : Array(repeating: floor(available / CGFloat(natural.count)), count: natural.count)

        var x = tabStripMinX
        return widths.map { width in
            defer { x += width }
            return NSRect(x: x, y: bar.minY + 1, width: width, height: bar.height - 1)
        }
    }

    /// The tab under `point`, in this view's coordinates.
    func tabIndex(at point: NSPoint) -> Int? {
        tabRects.firstIndex { $0.contains(point) }
    }

    /// Where the menu triangle sits and takes clicks: the bar's right end,
    /// stopping where a resizable palette's right band begins, so the
    /// pointer and a press agree on every point.
    var menuButtonRect: NSRect {
        let bar = titleBarRect
        let maxX = bar.maxX - PaletteResizeBorderView.bandWidth
        return NSRect(x: bar.maxX - 18, y: bar.minY, width: maxX - (bar.maxX - 18), height: bar.height)
    }

    private func drawMenuButton() {
        let rect = menuButtonRect
        ClassicChrome.arrowColor(true).setFill()
        let triangle = NSBezierPath()
        let midX = rect.midX.rounded(), midY = rect.midY.rounded()
        triangle.move(to: NSPoint(x: midX - 3.5, y: midY + 2))
        triangle.line(to: NSPoint(x: midX + 3.5, y: midY + 2))
        triangle.line(to: NSPoint(x: midX, y: midY - 2))
        triangle.close()
        triangle.fill()
    }

    private func drawTabs(in bar: NSRect) {
        let rects = tabRects
        for (index, rect) in rects.enumerated() {
            let selected = index == selectedTabIndex
            if selected {
                // The picked tab opens into the body: body-tone fill, side
                // hairlines, and no bottom border under it.
                ClassicChrome.gradient(top: 0.985, bottom: 0.97).draw(in: rect, angle: 90)
                NSColor(calibratedWhite: 0.55, alpha: 1).setFill()
                NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height).fill()
                NSRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()
                ClassicChrome.gradient(top: 0.985, bottom: 0.97).draw(
                    in: NSRect(x: rect.minX + 1, y: bar.minY, width: rect.width - 2, height: 1),
                    angle: 90)
            } else if index + 1 < rects.count, index + 1 != selectedTabIndex {
                NSColor(calibratedWhite: 0.62, alpha: 1).setFill()
                NSRect(x: rect.maxX - 1, y: rect.minY + 3, width: 1, height: rect.height - 6).fill()
            }

            let title = ClassicText.engraved(
                tabTitles[index], size: 10.5, weight: selected ? .medium : .regular,
                gray: selected ? 0.22 : 0.38)
            let height = title.size().height
            title.draw(in: NSRect(
                x: rect.minX + Self.tabPadding,
                y: (rect.midY - height / 2).rounded(),
                width: max(0, rect.width - 2 * Self.tabPadding),
                height: height))
        }
    }

    private func drawDropTarget(in bar: NSRect) {
        NSColor.keyboardFocusIndicatorColor.setStroke()
        let ring = NSBezierPath(roundedRect: bar.insetBy(dx: 1.5, dy: 1.5), xRadius: 3, yRadius: 3)
        ring.lineWidth = 2
        ring.stroke()
    }

    /// VoiceOver reads the tabs as a radio group of tab buttons, since they are
    /// drawn rather than built from controls.
    private func updateTabAccessibility() {
        updateMenuButtonAccessibility()
        guard tabTitles.count > 1 else {
            tabElements = []
            return
        }

        let rects = tabRects
        tabElements = tabTitles.enumerated().map { index, title in
            let element = PaletteTabAccessibilityElement()
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilitySubrole(.tabButtonSubrole)
            element.setAccessibilityLabel(title)
            element.setAccessibilityValue(NSNumber(value: index == selectedTabIndex))
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(index < rects.count ? rects[index] : .zero)
            element.onPress = { [weak self] in
                guard let self else { return }
                self.titleBarDelegate?.titleBar(self, selectTabAt: index)
            }
            return element
        }
    }

    public override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + tabElements + (menuButtonElement.map { [$0] } ?? [])
    }

    private func updateMenuButtonAccessibility() {
        guard showsMenuButton else {
            menuButtonElement = nil
            return
        }

        let element = menuButtonElement ?? PaletteTabAccessibilityElement()
        element.setAccessibilityRole(.menuButton)
        element.setAccessibilityLabel("\(title) Menu")
        element.setAccessibilityParent(self)
        element.setAccessibilityFrameInParentSpace(menuButtonRect)
        element.onPress = { [weak self] in
            guard let self else { return }
            self.titleBarDelegate?.titleBarMenuButtonPressed(self)
        }
        menuButtonElement = element
    }

    private func drawTitle(in bar: NSRect) {
        let styled = ClassicText.engraved(title, size: 10.5, weight: .medium)
        let size = styled.size()
        styled.draw(at: NSPoint(x: (bar.midX - size.width / 2).rounded(),
                                y: (bar.midY - size.height / 2).rounded()))
    }

    // MARK: - Mouse: title-bar dragging

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Empty title-bar regions drag the panel; the close button, a real
    /// subview, keeps normal event handling on its own.
    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard titleBarRect.contains(point) else { return }

        if showsMenuButton, menuButtonRect.contains(point), let titleBarDelegate {
            titleBarDelegate.titleBarMenuButtonPressed(self)
        } else if let titleBarDelegate {
            titleBarDelegate.titleBar(self, mouseDown: event, onTab: tabIndex(at: point))
        } else {
            window?.performDrag(with: event)
        }
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard titleBarRect.contains(point), let titleBarDelegate else {
            return super.menu(for: event)
        }

        return titleBarDelegate.titleBar(self, menuForTabAt: tabIndex(at: point))
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutCloseButton()
        updateTabAccessibility()
    }

    @objc private func closePressed() {
        onClose?()
    }
}

/// Receives the palette title bar's presses when the chrome belongs to a
/// palette group.
@MainActor
protocol PaletteTitleBarDelegate: AnyObject {
    /// A press in the title bar, on tab `tab` or on the bar itself.
    func titleBar(_ chrome: PaletteChromeView, mouseDown event: NSEvent, onTab tab: Int?)
    /// An assistive technology pressed tab `index`.
    func titleBar(_ chrome: PaletteChromeView, selectTabAt index: Int)
    /// The contextual menu for tab `tab`, or for the bar itself.
    func titleBar(_ chrome: PaletteChromeView, menuForTabAt tab: Int?) -> NSMenu?
    /// The menu triangle was clicked or pressed.
    func titleBarMenuButtonPressed(_ chrome: PaletteChromeView)
}

/// One drawn tab, as assistive technologies see it.
/// Assistive technologies call in on the main thread, where the chrome that
/// sets `onPress` lives.
final class PaletteTabAccessibilityElement: NSAccessibilityElement {
    var onPress: (() -> Void)?

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}

/// The standard red close button at palette scale, as a real NSButton so
/// keyboard focus and VoiceOver reach it natively — only its drawing is
/// custom. Floating palettes close on the first click without activating the
/// app window.
@MainActor
final class PaletteCloseButton: NSButton {

    /// The dot itself; the view is the dot plus hit slop on every side.
    static let dotDiameter: CGFloat = 9

    private static let fill = NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1)
    private static let pressedFill = NSColor(calibratedRed: 0.78, green: 0.27, blue: 0.25, alpha: 1)
    private static let stroke = NSColor(calibratedRed: 0.88, green: 0.27, blue: 0.24, alpha: 1)

    private var dotRect: NSRect {
        NSRect(x: (bounds.width - Self.dotDiameter) / 2,
               y: (bounds.height - Self.dotDiameter) / 2,
               width: Self.dotDiameter, height: Self.dotDiameter)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        focusRingType = .default
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The red dot darkens while pressed like the real one.
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: dotRect.insetBy(dx: 0.5, dy: 0.5))
        (isHighlighted ? Self.pressedFill : Self.fill).setFill()
        circle.fill()
        Self.stroke.setStroke()
        circle.lineWidth = 1
        circle.stroke()
    }

    override func drawFocusRingMask() {
        NSBezierPath(ovalIn: dotRect.insetBy(dx: -2, dy: -2)).fill()
    }

    override var focusRingMaskBounds: NSRect { dotRect.insetBy(dx: -2, dy: -2) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
