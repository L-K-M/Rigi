import AppKit
import RigiUI

/// The gallery's whole editable state. Committed mutations register one undo
/// step each; a try-on session previews without registering and collapses into
/// a single undo on commit (or restores on cancel). Editing semantics stay
/// here in the app layer — RigiUI owns only presentation.
@MainActor
final class GalleryModel {

    static let fontSizeRange = 1.0...288.0

    struct Specimen: Equatable {
        var family = "Helvetica"
        var size = 18.0
        var bold = false, italic = false, underline = false
        var color = NSColor(calibratedWhite: 0.15, alpha: 1)
    }

    let undo = UndoManager()
    var onChange: (() -> Void)?
    var zoomPercent = 100 { didSet { onChange?() } }
    private(set) var specimen = Specimen()
    private var tryOnBase: Specimen?

    var family: String { specimen.family }
    var size: Double { specimen.size }
    var color: NSColor { specimen.color }

    /// One committed edit = one undo step.
    func edit(_ mutate: (inout Specimen) -> Void) {
        var next = specimen
        mutate(&next)
        guard next != specimen else { return }
        apply(next)
    }

    // MARK: Try-on session

    func beginTryOn() { tryOnBase = specimen }
    func previewFamily(_ family: String) { specimen.family = family; onChange?() }
    /// Tear-off banks the attached browsing as the session's single undo step.
    func bankTryOn() { endTryOn(.commit) }

    func endTryOn(_ outcome: TryOnPopover.Outcome) {
        guard let base = tryOnBase else { return }
        tryOnBase = nil
        if outcome == .commit {
            guard specimen != base else { return }
            undo.registerUndo(withTarget: self) { $0.apply(base) }
        } else {
            specimen = base
        }
        onChange?()
    }

    /// Applies a state and registers restoring the previous one; while undoing,
    /// that registration lands on the redo stack automatically.
    private func apply(_ next: Specimen) {
        let current = specimen
        specimen = next
        onChange?()
        undo.registerUndo(withTarget: self) { $0.apply(current) }
    }
}

/// Owns the single gallery window: a classic toolbar, an inset well holding a
/// rendered specimen, the status bar, and the wiring into both palette systems
/// — the try-on picker with its floating tear-off, and the generic inspector.
@MainActor
final class GalleryController: NSObject, NSWindowDelegate {

    static let families = ["Helvetica", "Helvetica Neue", "Arial", "Futura",
                           "Gill Sans", "Palatino", "Times New Roman", "Georgia",
                           "American Typewriter", "Courier New", "Menlo", "Avenir Next"]
    static let sizePresets = ["9", "10", "12", "14", "18", "24", "36"]
    static let specimenTexts = ["The quick brown fox jumps over the lazy dog",
                                "Sphinx of black quartz, judge my vow",
                                "AaBbCc 0123456789"]
    private static let idleMessage =
        "Typeface opens the try-on picker — drag it off to float · Inspector hosts the generic palette"

    let model: GalleryModel
    let window: ClassicWindow
    let toolControl = ClassicToolControl(frame: .zero)
    let chooser = ClassicChooserControl(width: 128)
    let sizeField = ClassicSizeField(presets: GalleryController.sizePresets, width: 56)
    let colorWell = ClassicColorWell(frame: .zero)
    let specimenPopUp = ClassicPopUp(width: 96)
    let toolbarStack = NSStackView(frame: .zero)
    let statusBar = StatusBarView(frame: .zero)
    let specimenLabel = NSTextField(labelWithString: "")
    let tryOnPopover = TryOnPopover(hint: "Return keeps · Esc reverts · drag off to float")
    let tearOffPalette: GalleryTearOffPalette
    let inspectorPalette: Palette
    private var specimenText: String

    override init() {
        let model = GalleryModel()
        self.model = model
        specimenText = Self.specimenTexts[0]
        tearOffPalette = GalleryTearOffPalette(
            items: Self.families.map { PickerItem(id: $0, title: $0) }
        ) { Self.specimenFont(for: $0) }
        inspectorPalette = PaletteCenter.shared.palette(
            for: PaletteDefinition(kind: PaletteKind("inspector"), title: "Inspector",
                                   contentSize: NSSize(width: 224, height: 118),
                                   frameAutosaveName: "RigiGallery.inspector"),
            target: { model },
            makeContent: { InspectorContent() })
        window = ClassicWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 470),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()
        window.title = "Rigi Gallery"
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = NSSize(width: 640, height: 380)
        window.delegate = self
        buildContent()
        wire()
        syncSpecimen()
        statusBar.message = Self.idleMessage
    }

    // MARK: Layout

    private func buildContent() {
        let content = ClassicPanelView()
        window.contentView = content

        let bar = ClassicBarView(style: .toolbar)
        toolControl.segmentCount = 3
        for (index, label) in ["B", "I", "U"].enumerated() {
            toolControl.setLabel(label, forSegment: index)
            toolControl.setWidth(25, forSegment: index)
        }
        toolControl.trackingMode = .selectAny
        chooser.title = model.family
        sizeField.stringValue = Self.trimmed(model.size)
        colorWell.color = model.color
        specimenPopUp.addItems(withTitles: ["Quick fox", "Sphinx", "Alphabet"])

        toolbarStack.orientation = .horizontal
        toolbarStack.spacing = ClassicMetrics.controlSpacing
        toolbarStack.alignment = .centerY
        for view in [toolControl, EtchedSeparatorView(), chooser, sizeField,
                     colorWell, EtchedSeparatorView(), specimenPopUp] {
            toolbarStack.addArrangedSubview(view)
        }

        let inspectorButton = ClassicToolbarButton(frame: .zero)
        inspectorButton.title = "Inspector"
        inspectorButton.target = self
        inspectorButton.action = #selector(inspectorPressed(_:))

        for view in [toolbarStack, inspectorButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(view)
        }
        let inset = ClassicMetrics.horizontalInset
        NSLayoutConstraint.activate([
            toolbarStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: inset),
            toolbarStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            inspectorButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -inset),
            inspectorButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            inspectorButton.leadingAnchor.constraint(greaterThanOrEqualTo: toolbarStack.trailingAnchor,
                                                     constant: ClassicMetrics.controlSpacing)
        ])

        let insetBox = ClassicInsetBox()
        specimenLabel.alignment = .center
        specimenLabel.lineBreakMode = .byTruncatingTail
        insetBox.embed(specimenLabel)

        for view in [bar, insetBox, statusBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        for edge in [bar, statusBar] {
            edge.leadingAnchor.constraint(equalTo: content.leadingAnchor).isActive = true
            edge.trailingAnchor.constraint(equalTo: content.trailingAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: ClassicMetrics.toolbarHeight),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: ClassicMetrics.statusBarHeight),
            insetBox.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: inset),
            insetBox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            insetBox.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            insetBox.bottomAnchor.constraint(equalTo: statusBar.topAnchor, constant: -6)
        ])
    }

    // MARK: Wiring

    private func wire() {
        let model = self.model
        model.onChange = { [weak self] in self?.syncSpecimen() }
        toolControl.target = self; toolControl.action = #selector(traitsChanged)
        specimenPopUp.target = self; specimenPopUp.action = #selector(specimenChanged)
        colorWell.target = self; colorWell.action = #selector(colorChanged)
        chooser.onPresent = { [weak self] in self?.presentTryOnPicker() }
        sizeField.onCommit = { [weak self] text in self?.commitSizeText(text) }
        statusBar.onZoomIn = { [weak self] in self?.zoom(by: 10) }
        statusBar.onZoomOut = { [weak self] in self?.zoom(by: -10) }
        statusBar.onZoomReset = { [weak self] in self?.zoom(to: 100) }
        tearOffPalette.onPick = { item in model.edit { $0.family = item.id } }
        tearOffPalette.onFinish = { [weak self] in self?.window.makeKey() }
        tearOffPalette.onVisibilityChange = { [weak self] open in
            self?.paletteVisibilityDidChange(open)
        }
    }

    /// The chooser summons the floating palette while it lives torn off; else
    /// the attached try-on presents and the model opens a preview session.
    func presentTryOnPicker() {
        if tearOffPalette.isOpen { return tearOffPalette.bringToFront() }
        guard !tryOnPopover.isActive else { return }
        let model = self.model
        model.beginTryOn()
        tryOnPopover.present(from: chooser, palette: tearOffPalette,
                             items: Self.families.map { PickerItem(id: $0, title: $0) },
                             currentID: model.family,
                             specimenFont: { Self.specimenFont(for: $0) },
                             onPreview: { item in model.previewFamily(item.id) },
                             onDetach: { model.bankTryOn() },
                             onFinish: { outcome in model.endTryOn(outcome) })
    }

    static func specimenFont(for item: PickerItem) -> NSFont {
        NSFont(name: item.id, size: 13) ?? .systemFont(ofSize: 13)
    }

    static func trimmed(_ size: Double) -> String {
        size.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(size))" : "\(size)"
    }

    // MARK: Actions

    @objc private func traitsChanged() {
        model.edit {
            $0.bold = toolControl.isSelected(forSegment: 0)
            $0.italic = toolControl.isSelected(forSegment: 1)
            $0.underline = toolControl.isSelected(forSegment: 2)
        }
    }

    @objc private func specimenChanged() {
        let index = specimenPopUp.indexOfSelectedItem
        guard Self.specimenTexts.indices.contains(index) else { return }
        specimenText = Self.specimenTexts[index]
        syncSpecimen()
    }

    @objc private func colorChanged() { model.edit { $0.color = colorWell.color } }

    @objc private func inspectorPressed(_ sender: Any?) {
        guard let anchor = sender as? NSView else { return }
        inspectorPalette.present(from: anchor)
    }

    private func commitSizeText(_ text: String) {
        guard let size = Double(text), GalleryModel.fontSizeRange.contains(size) else {
            return syncSpecimen()
        }
        model.edit { $0.size = size }
    }

    private func zoom(by delta: Int) { zoom(to: model.zoomPercent + delta) }

    private func zoom(to percent: Int) {
        model.zoomPercent = max(25, min(400, percent))
        statusBar.setZoom(percent: model.zoomPercent)
    }

    private func paletteVisibilityDidChange(_ open: Bool) {
        chooser.representsOpenPalette = open
        statusBar.message = open
            ? "Typefaces floats — picks commit to the specimen"
            : Self.idleMessage
    }

    private func syncSpecimen() {
        let size = CGFloat(model.size * Double(model.zoomPercent) / 100)
        var font = NSFont(name: model.family, size: size) ?? .systemFont(ofSize: size)
        let manager = NSFontManager.shared
        if model.specimen.bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if model.specimen.italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: model.color]
        if model.specimen.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        specimenLabel.attributedStringValue = NSAttributedString(string: specimenText,
                                                               attributes: attributes)
        chooser.title = model.family
        sizeField.stringValue = Self.trimmed(model.size)
        colorWell.color = model.color
        toolControl.setSelected(model.specimen.bold, forSegment: 0)
        toolControl.setSelected(model.specimen.italic, forSegment: 1)
        toolControl.setSelected(model.specimen.underline, forSegment: 2)
    }

    // MARK: NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model.undo }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}
