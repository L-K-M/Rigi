import AppKit
import RigiUI

/// The gallery's TearOffPalette: the floating backing a try-on popover hands
/// its session to when dragged off — ClassicPaletteWindow + PaletteChromeView
/// + PickerListView, the same pieces the library's own palettes use. Picks
/// while it floats are committed edits (the attached browsing was already
/// banked as one undo when the detach landed).
@MainActor
final class GalleryTearOffPalette: TearOffPalette {

    var onPick: ((PickerItem) -> Void)?
    var onFinish: (() -> Void)?
    var onVisibilityChange: ((Bool) -> Void)?

    private(set) var isOpen = false
    private var panel: ClassicPaletteWindow?
    private let list = PickerListView(hint: "Applies to the gallery specimen")
    private let items: [PickerItem]

    init(items: [PickerItem], specimenFont: @escaping (PickerItem) -> NSFont) {
        self.items = items
        list.specimenFont = specimenFont
    }

    var isShowingPanel: Bool { panel?.isVisible == true }

    /// Builds and primes the panel for NSPopoverDelegate.detachableWindow —
    /// not open yet; AppKit commits the detach afterwards (didDetach).
    func windowForDetach(selecting id: String?) -> NSWindow {
        let panel = ensurePanel()
        list.clearFilter()
        list.select(id: id)
        let mouse = NSEvent.mouseLocation
        panel.setFrameTopLeftPoint(NSPoint(x: mouse.x - 24, y: mouse.y + 8))
        return panel
    }

    func didDetach() {
        setOpen(true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen, let panel = self.panel else { return }
            if !panel.isVisible { panel.orderFront(nil) }
            panel.invalidateShadow()
        }
    }

    func bringToFront() {
        guard isOpen, let panel else { return }
        panel.orderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        setOpen(false)
        onFinish?()
    }

    private func setOpen(_ open: Bool) {
        guard isOpen != open else { return }
        isOpen = open
        onVisibilityChange?(open)
    }

    private func ensurePanel() -> ClassicPaletteWindow {
        if let panel { return panel }
        let panel = ClassicPaletteWindow(contentSize: NSSize(
            width: 280, height: 400 + PaletteChromeView.titleBarHeight))
        let chrome = PaletteChromeView(title: "Typefaces")
        chrome.onClose = { [weak self] in self?.close() }
        panel.contentView = chrome
        list.setItems(items)
        list.onPick = { [weak self] item in self?.onPick?(item) }
        // Return / Esc just hand focus back — picks already committed.
        list.onCommit = { [weak self] in self?.onFinish?() }
        list.onCancel = { [weak self] in self?.onFinish?() }
        chrome.embedContent(list)
        self.panel = panel
        return panel
    }
}

/// Content for the generic PaletteCenter palette: a small settings form the
/// subsystem hosts as an attached popover and, torn off, as a floating panel.
@MainActor
final class InspectorContent: NSViewController, PaletteContent {

    private weak var model: GalleryModel?
    private let sizeField = ClassicSizeField(presets: GalleryController.sizePresets, width: 64)
    private let colorWell = ClassicColorWell(frame: .zero)
    private let emphasisPopUp = ClassicPopUpButton(frame: .zero, pullsDown: false)

    override func loadView() {
        let root = ClassicPanelView()
        emphasisPopUp.addItems(withTitles: ["Regular", "Bold", "Italic"])
        let rows = NSStackView(views: [
            formRow("Size", sizeField),
            formRow("Ink", colorWell),
            formRow("Emphasis", emphasisPopUp)
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = ClassicMetrics.formSpacing
        rows.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        rows.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: root.topAnchor),
            rows.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sizeField.onCommit = { [weak self] text in self?.commitSize(text) }
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        emphasisPopUp.target = self
        emphasisPopUp.action = #selector(emphasisChanged)
    }

    // MARK: PaletteContent

    func retarget(to target: GalleryModel?) {
        model = target
        sync()
    }

    func paletteDidPresent(_ presentation: PalettePresentation) { sync() }

    // MARK: Edits (each a committed, undoable change on the model)

    private func commitSize(_ text: String) {
        guard let model, let size = Double(text), GalleryModel.fontSizeRange.contains(size) else {
            return sync()
        }
        model.edit { $0.size = size }
    }

    @objc private func colorChanged() {
        model?.edit { $0.color = colorWell.color }
    }

    @objc private func emphasisChanged() {
        let index = emphasisPopUp.indexOfSelectedItem
        model?.edit { $0.bold = index == 1; $0.italic = index == 2 }
    }

    private func formRow(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.font = .systemFont(ofSize: 11)
        let row = NSStackView(views: [label, control])
        row.spacing = 6
        label.widthAnchor.constraint(equalToConstant: 60).isActive = true
        return row
    }

    private func sync() {
        let active = model != nil
        sizeField.isEnabled = active
        colorWell.isEnabled = active
        emphasisPopUp.isEnabled = active
        guard let model else { return }
        sizeField.stringValue = GalleryController.trimmed(model.size)
        colorWell.color = model.color
        let specimen = model.specimen
        emphasisPopUp.selectItem(at: specimen.bold ? 1 : specimen.italic ? 2 : 0)
    }
}

enum GalleryPaletteKind {
    static let inspector = PaletteKind("inspector")
    static let swatches = PaletteKind("swatches")
}

/// A second generic palette, resizable, that groups with the inspector as a
/// tab: a row of ink swatches, each a committed edit on the model.
@MainActor
final class SwatchesContent: NSViewController, PaletteContent {

    private static let inks: [NSColor] = [
        .black, .darkGray, .systemRed, .systemOrange, .systemGreen, .systemBlue, .systemPurple
    ]

    private weak var model: GalleryModel?
    private var buttons: [NSButton] = []

    override func loadView() {
        let root = ClassicPanelView()
        buttons = Self.inks.enumerated().map { index, ink in
            let button = NSButton(title: "", target: self, action: #selector(pick(_:)))
            button.tag = index
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = ink.cgColor
            button.layer?.borderColor = NSColor(calibratedWhite: 0.45, alpha: 1).cgColor
            button.layer?.borderWidth = 1
            button.setAccessibilityLabel("Ink \(index + 1)")
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            return button
        }
        let row = NSStackView(views: buttons)
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: root.topAnchor),
            row.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        ])
        view = root
    }

    func retarget(to target: GalleryModel?) {
        model = target
        for button in buttons { button.isEnabled = target != nil }
    }

    @objc private func pick(_ sender: NSButton) {
        guard Self.inks.indices.contains(sender.tag) else { return }
        model?.edit { $0.color = Self.inks[sender.tag] }
    }
}
