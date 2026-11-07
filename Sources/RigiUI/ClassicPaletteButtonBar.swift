import AppKit

/// The strip of small icon buttons at the foot of a palette: new,
/// duplicate, delete and the like. Leading items sit at the left, trailing
/// ones (usually delete) at the right, on the panel backing under a
/// hairline.
///
/// Each item is a real button: it takes the keyboard focus, reads its
/// title to VoiceOver and shows it as the tool tip. The application enables
/// and disables items as its selection changes.
public final class ClassicPaletteButtonBar: ClassicBarView, ClassicChromeSchemeAware {

    public struct Item {
        public let id: String
        /// What the button does, as a tool tip and to VoiceOver.
        public let title: String
        /// A 16 pt glyph; template images take the chrome's gray.
        public let image: NSImage
        public let action: () -> Void

        public init(id: String, title: String, image: NSImage, action: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.image = image
            self.action = action
        }
    }

    public static let height: CGFloat = 24
    static let buttonSize = NSSize(width: 26, height: 18)

    private var buttons: [String: ClassicToolbarButton] = [:]
    private var actions: [ButtonAction] = []
    private var itemImages: [String: NSImage] = [:]

    public init(items: [Item], trailingItems: [Item] = []) {
        let ids = (items + trailingItems).map(\.id)
        precondition(Set(ids).count == ids.count, "Palette button ids must be unique")

        super.init(style: .panel)

        let leading = NSStackView(views: items.map(makeButton))
        let trailing = NSStackView(views: trailingItems.map(makeButton))
        for stack in [leading, trailing] {
            stack.spacing = 2
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: leading.trailingAnchor, constant: 8),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    public func setEnabled(_ enabled: Bool, forItem id: String) {
        buttons[id]?.isEnabled = enabled
    }

    public func isEnabled(item id: String) -> Bool {
        buttons[id]?.isEnabled ?? false
    }

    /// The button for item `id`. Module-internal; tests press it.
    func button(for id: String) -> NSButton? {
        buttons[id]
    }

    private func makeButton(_ item: Item) -> NSView {
        let target = ButtonAction(item.action)
        actions.append(target)

        let button = ClassicToolbarButton(image: Self.tinted(item.image), target: target,
                                          action: #selector(ButtonAction.run(_:)))
        button.imagePosition = .imageOnly
        button.toolTip = item.title
        button.setAccessibilityLabel(item.title)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.buttonSize.width),
            button.heightAnchor.constraint(equalToConstant: Self.buttonSize.height),
        ])
        buttons[item.id] = button
        itemImages[item.id] = item.image
        return button
    }

    /// The tint is baked into each button's image, so a scheme change
    /// re-tints from the original template glyphs.
    func chromeSchemeDidChange() {
        for (id, image) in itemImages {
            buttons[id]?.image = Self.tinted(image)
        }
    }

    /// A template icon in the chrome's glyph gray: the bezel button draws
    /// its image as it is, and a template's own color is black.
    static func tinted(_ image: NSImage) -> NSImage {
        guard image.isTemplate else { return image }

        let tinted = NSImage(size: image.size, flipped: false) { bounds in
            image.draw(in: bounds)
            ClassicChrome.glyphColor(true).setFill()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.accessibilityDescription = image.accessibilityDescription
        return tinted
    }

    /// The hairline that separates the strip from the palette body above.
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ClassicChrome.barBottomBorder(ClassicChrome.active(for: self)).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    /// A button's target: the bar keeps them, since buttons hold targets weakly.
    private final class ButtonAction: NSObject {
        private let handler: () -> Void

        init(_ handler: @escaping () -> Void) {
            self.handler = handler
        }

        @objc func run(_ sender: Any?) {
            handler()
        }
    }
}
