import AppKit

/// Shared dimensions for compact document windows and inspector forms.
public enum ClassicMetrics {
    public static let toolbarHeight: CGFloat = 34
    public static let statusBarHeight: CGFloat = 22
    public static let controlSpacing: CGFloat = 9
    public static let horizontalInset: CGFloat = 10
    public static let formSpacing: CGFloat = 8
}

/// A classic backing for app-owned toolbar or inspector content.
/// Subclass only to compose controls; editing semantics belong to the app.
open class ClassicBarView: NSView {
    public enum Style { case toolbar, panel }

    private let style: Style

    public override init(frame: NSRect) {
        style = .toolbar
        super.init(frame: frame)
    }

    public init(style: Style) {
        self.style = style
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    open override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        if style == .panel {
            ClassicChrome.gradient(top: active ? 0.97 : 0.975,
                                   bottom: active ? 0.86 : 0.92).draw(in: bounds, angle: 90)
            return
        }

        ClassicChrome.gradient(top: active ? 0.965 : 0.975,
                               bottom: active ? 0.795 : 0.90).draw(in: bounds, angle: 90)
        ClassicChrome.barTopHighlight.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        NSColor(calibratedWhite: active ? 0.66 : 0.80, alpha: 1).setFill()
        NSRect(x: 0, y: 1, width: bounds.width, height: 1).fill()
        ClassicChrome.barBottomBorder(active).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

/// Native menu/keyboard/accessibility behavior with Rigi's bezel. Use this when
/// an inspector needs AppKit's represented objects, tags, or mixed menu states.
public final class ClassicPopUpButton: NSPopUpButton {
    public override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width, height: ClassicChrome.controlHeight)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self) && isEnabled
        let outline = ClassicChrome.bezelOutline(in: bounds)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        ClassicChrome.bezelGradient(isHighlighted ? .pressed : .normal, active: active)
            .draw(in: bounds, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder(active).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let arrowWidth: CGFloat = 16
        ClassicChrome.drawStackedChevrons(cx: bounds.maxX - arrowWidth / 2,
                                         cy: bounds.midY, active: active)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(string: titleOfSelectedItem ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: ClassicChrome.titleColor(active),
            .paragraphStyle: paragraph
        ])
        title.draw(in: NSRect(x: 8, y: ((bounds.height - title.size().height) / 2).rounded(),
                              width: max(0, bounds.width - arrowWidth - 12), height: title.size().height))
    }
}
