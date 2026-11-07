import AppKit

/// Where each part of a ClassicColorPair sits, kept in a value type so tests
/// exercise the hit areas without a window. Frames use a top-left origin
/// (the control is flipped).
///
/// ```
///  ┌──────┐   ↷        foreground: top left, drawn on top
///  │  FG  ├─────┐      background: bottom right, behind it
///  │      │     │      swap: the arrow at the top right
///  └──┬───┘ BG  │      reset: the small pair at the bottom left
///  ▪▫ └─────────┘
/// ```
public struct ClassicColorPairLayout {

    public enum Part: CaseIterable {
        case foreground, background, swap, reset
    }

    /// The control's intrinsic size: as wide as two 24 pt tool cells and
    /// their gap, so it sits flush under a two-column tool grid.
    public static let size = CGSize(width: 49, height: 42)

    public let foreground = CGRect(x: 4, y: 3, width: 24, height: 24)
    public let background = CGRect(x: 19, y: 15, width: 24, height: 24)
    public let swap = CGRect(x: 31, y: 1, width: 15, height: 13)
    public let reset = CGRect(x: 2, y: 29, width: 15, height: 12)

    public init() {}

    public func frame(of part: Part) -> CGRect {
        switch part {
        case .foreground: return foreground
        case .background: return background
        case .swap: return swap
        case .reset: return reset
        }
    }

    /// The part under `point`. The foreground square lies over the
    /// background one, so their overlap is the foreground's; the small swap
    /// and reset targets win over the squares they touch.
    public func part(at point: CGPoint) -> Part? {
        for part in [Part.swap, .reset, .foreground, .background] where frame(of: part).contains(point) {
            return part
        }
        return nil
    }
}

/// The classic foreground and background color squares of a paint
/// application's tool palette, with a swap arrow and a reset to black and
/// white.
///
/// The control shows colors the application owns and reports what the
/// person asked for; it never changes its colors itself. Set `foreground`
/// and `background` from the application's state, including after a swap
/// or reset.
public final class ClassicColorPair: NSView, NSViewToolTipOwner, ClassicChromeDrawing {

    public var foreground: NSColor = .black {
        didSet { colorsDidChange() }
    }

    public var background: NSColor = .white {
        didSet { colorsDidChange() }
    }

    public var isEnabled = true {
        didSet {
            needsDisplay = true
            syncAccessibility()
        }
    }

    /// Clicks on the foreground square, usually to open a color picker.
    public var onEditForeground: (() -> Void)?
    /// Clicks on the background square.
    public var onEditBackground: (() -> Void)?
    /// Clicks on the swap arrow.
    public var onSwap: (() -> Void)?
    /// Clicks on the small black-and-white pair.
    public var onReset: (() -> Void)?

    /// Shortcut hints the tool tips show, such as "X" and "D"; the
    /// application handles the keys.
    public var swapShortcut: String? { didSet { syncAccessibility() } }
    public var resetShortcut: String? { didSet { syncAccessibility() } }

    private let layout = ClassicColorPairLayout()
    private var pressedPart: ClassicColorPairLayout.Part?
    private var toolTipParts: [NSView.ToolTipTag: ClassicColorPairLayout.Part] = [:]
    private var accessibilityParts: [PartAccessibilityElement] = []

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Colors")
        syncAccessibility()
    }

    public convenience init() {
        self.init(frame: NSRect(origin: .zero, size: ClassicColorPairLayout.size))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    public override var intrinsicContentSize: NSSize { ClassicColorPairLayout.size }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Tracking

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        pressedPart = layout.part(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        defer {
            pressedPart = nil
            needsDisplay = true
        }
        guard let part = pressedPart,
              layout.part(at: convert(event.locationInWindow, from: nil)) == part else { return }

        perform(part)
    }

    /// The one place a pick turns into a report, for clicks and VoiceOver.
    func perform(_ part: ClassicColorPairLayout.Part) {
        guard isEnabled else { return }

        switch part {
        case .foreground: onEditForeground?()
        case .background: onEditBackground?()
        case .swap: onSwap?()
        case .reset: onReset?()
        }
    }

    // MARK: Tool tips and accessibility

    func title(of part: ClassicColorPairLayout.Part) -> String {
        switch part {
        case .foreground: return "Foreground Color"
        case .background: return "Background Color"
        case .swap: return Self.withShortcut("Swap Colors", swapShortcut)
        case .reset: return Self.withShortcut("Default Colors", resetShortcut)
        }
    }

    private static func withShortcut(_ title: String, _ shortcut: String?) -> String {
        shortcut.map { "\(title) (\($0))" } ?? title
    }

    @MainActor
    public func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
                     point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        toolTipParts[tag].map(title(of:)) ?? ""
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rebuildToolTips()
    }

    private func rebuildToolTips() {
        removeAllToolTips()
        toolTipParts.removeAll()
        for part in ClassicColorPairLayout.Part.allCases {
            toolTipParts[addToolTip(layout.frame(of: part), owner: self, userData: nil)] = part
        }
    }

    /// Each part, for VoiceOver: a button named after what it does, the two
    /// squares reporting their color.
    private final class PartAccessibilityElement: NSAccessibilityElement {
        var onPress: (() -> Void)?

        override func accessibilityPerformPress() -> Bool {
            onPress?()
            return true
        }
    }

    public override func accessibilityChildren() -> [Any]? { accessibilityParts }

    private func syncAccessibility() {
        if accessibilityParts.isEmpty {
            accessibilityParts = ClassicColorPairLayout.Part.allCases.map { part in
                let element = PartAccessibilityElement()
                element.setAccessibilityParent(self)
                element.setAccessibilityRole(.button)
                element.setAccessibilityFrameInParentSpace(layout.frame(of: part))
                element.onPress = { [weak self] in self?.perform(part) }
                return element
            }
        }

        for (part, element) in zip(ClassicColorPairLayout.Part.allCases, accessibilityParts) {
            element.setAccessibilityLabel(title(of: part))
            element.setAccessibilityEnabled(isEnabled)
            switch part {
            case .foreground: element.setAccessibilityValue(Self.describe(foreground))
            case .background: element.setAccessibilityValue(Self.describe(background))
            case .swap, .reset: element.setAccessibilityValue(nil)
            }
        }
    }

    /// A color as VoiceOver reads it: sRGB components as percentages.
    static func describe(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "" }
        let percent = { (value: CGFloat) in Int((value * 100).rounded()) }
        return "red \(percent(rgb.redComponent)) percent, "
            + "green \(percent(rgb.greenComponent)) percent, "
            + "blue \(percent(rgb.blueComponent)) percent"
    }

    private func colorsDidChange() {
        needsDisplay = true
        syncAccessibility()
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self) && isEnabled
        drawSwatch(background, in: layout.background, pressed: pressedPart == .background, active: active)
        drawSwatch(foreground, in: layout.foreground, pressed: pressedPart == .foreground, active: active)
        drawSwapArrow(in: layout.swap, pressed: pressedPart == .swap, active: active)
        drawResetPair(in: layout.reset, pressed: pressedPart == .reset, active: active)
    }

    /// A square of color in a dark hairline frame with a white inner rule,
    /// so black and white swatches both read against the panel.
    private func drawSwatch(_ color: NSColor, in rect: CGRect, pressed: Bool, active: Bool) {
        ClassicChrome.bezelBorder(active).setFill()
        rect.fill()
        NSColor.white.setFill()
        rect.insetBy(dx: 1, dy: 1).fill()

        let fill = rect.insetBy(dx: 2, dy: 2)
        (isEnabled ? color : color.blended(withFraction: 0.5, of: .white) ?? color).setFill()
        fill.fill()

        if pressed {
            NSColor(calibratedWhite: 0, alpha: 0.25).setFill()
            fill.fill()
        }
    }

    /// A small bent double arrow from the foreground's corner to the
    /// background's.
    private func drawSwapArrow(in rect: CGRect, pressed: Bool, active: Bool) {
        let color = pressed ? NSColor.black : ClassicChrome.glyphColor(active)
        color.set()

        let left = CGPoint(x: rect.minX + 3, y: rect.midY + 1)
        let top = CGPoint(x: rect.maxX - 4, y: rect.minY + 3)
        let curve = NSBezierPath()
        curve.lineWidth = 1.2
        curve.move(to: left)
        curve.curve(to: CGPoint(x: top.x, y: rect.maxY - 2),
                    controlPoint1: CGPoint(x: left.x, y: top.y),
                    controlPoint2: CGPoint(x: top.x, y: top.y))
        curve.stroke()

        // Heads at both ends: left-pointing at the start, down at the end.
        let head = NSBezierPath()
        head.move(to: CGPoint(x: left.x - 2, y: left.y))
        head.line(to: CGPoint(x: left.x + 2, y: left.y - 3))
        head.line(to: CGPoint(x: left.x + 2, y: left.y + 3))
        head.close()
        let end = CGPoint(x: top.x, y: rect.maxY - 1)
        head.move(to: end)
        head.line(to: CGPoint(x: end.x - 3, y: end.y - 4))
        head.line(to: CGPoint(x: end.x + 3, y: end.y - 4))
        head.close()
        head.fill()
    }

    /// Two overlapping mini swatches, black over white: the default colors.
    private func drawResetPair(in rect: CGRect, pressed: Bool, active: Bool) {
        let side: CGFloat = 8
        let back = CGRect(x: rect.minX + 5, y: rect.minY + 3, width: side, height: side)
        let front = CGRect(x: rect.minX + 1, y: rect.minY, width: side, height: side)
        for (square, color) in [(back, NSColor.white), (front, NSColor.black)] {
            ClassicChrome.bezelBorder(active).setFill()
            square.fill()
            color.setFill()
            square.insetBy(dx: 1, dy: 1).fill()
        }
        if pressed {
            NSColor(calibratedWhite: 0, alpha: 0.25).setFill()
            back.union(front).fill()
        }
    }
}
