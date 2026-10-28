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
    /// that need extra bits — the generic palette panel adds `.closable`, and
    /// `.resizable` for resizable palettes — state theirs here on the same
    /// shell.
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
            needsDisplay = true
        }
    }

    private let closeButton = PaletteCloseButton(frame: .zero)
    private weak var embeddedView: NSView?
    private var declaredSizeConstraints: [NSLayoutConstraint] = []

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
        guard embeddedView !== view else { return }

        embeddedView?.removeFromSuperview()
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
    func installResizeBorder() {
        let border = PaletteResizeBorderView()
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

    /// `resizeSubviews` covers constraint-free resizes, `layout` the Auto
    /// Layout passes; the dot's button tracks the bar either way.
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutCloseButton()
    }

    /// A real control over the drawn dot: hit area padded like the old
    /// custom tracking's, so clicks land the same while keyboard focus and
    /// VoiceOver come for free.
    private func layoutCloseButton() {
        closeButton.frame = closeBoxRect.insetBy(
            dx: -Self.closeButtonSlop, dy: -Self.closeButtonSlop)
    }

    private func updateCloseButtonAccessibility() {
        closeButton.toolTip = "Close \(title) Palette"
        closeButton.setAccessibilityLabel("Close \(title) palette")
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

        drawTitle(in: bar)
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
        if titleBarRect.contains(point) {
            window?.performDrag(with: event)
        }
    }

    @objc private func closePressed() {
        onClose?()
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
