import AppKit

// A thin classic footer: engraved contextual info on the left (current style,
// page count, or hover help) and a momentary − / percent / + zoom cluster on the
// right, drawn with the same gradient-bezel chrome as the format bar. The window
// controller supplies the message text and handles the zoom callbacks. Like the
// rest of the chrome, it mutes when the window isn't active (the engraved label
// is re-set from the window's main/key notifications, since text color is view
// state rather than something resolved at draw time).
//
// Between the message and the zoom cluster sit, when the application asks for
// them, a progress bar with a cancel button and accessory views such as an
// information pop-up.
public final class StatusBarView: NSView, NSTextFieldDelegate, ClassicChromeDrawing, ClassicChromeSchemeAware {

    private let label = NSTextField(labelWithString: "")
    private let trailingRow = NSStackView()
    private let progressIndicator = NSProgressIndicator()
    private let cancelButton = NSButton()
    private var accessoryViews: [NSView] = []
    private var onCancel: (() -> Void)?
    private let zoomField = NSTextField()
    private var zoomPercent = 100
    private var activationObservers: [NSObjectProtocol] = []
    private let zoomControl = ClassicSegmentedControl(
        glyphs: [
            .letter("−", font: .systemFont(ofSize: 12)),
            .letter("100%", font: .systemFont(ofSize: 10)),
            .letter("+", font: .systemFont(ofSize: 12))
        ],
        mode: .momentary,
        segmentWidths: [20, 44, 20],
        height: 17)

    public var message: String = "" {
        didSet { refreshLabel() }
    }

    public var onZoomIn: (() -> Void)?
    public var onZoomOut: (() -> Void)?
    public var onZoomReset: (() -> Void)?
    /// A zoom typed into the percentage, when `isZoomEditable` is on. The
    /// application clamps it to the zooms it supports and calls `setZoom`.
    public var onZoomTo: ((Int) -> Void)?

    /// Makes the percentage an editable field: click it, type a zoom, press
    /// Return. Off, clicking the percentage resets to 100%.
    public var isZoomEditable = false {
        didSet { syncZoomPresentation() }
    }

    public func setZoom(percent: Int) {
        zoomPercent = percent
        syncZoomPresentation()
    }

    /// Views shown left of the zoom cluster, such as an information pop-up.
    public func setAccessoryViews(_ views: [NSView]) {
        for view in accessoryViews {
            trailingRow.removeView(view)
        }
        accessoryViews = views
        for view in views {
            trailingRow.insertView(view, at: trailingRow.views(in: .trailing).count - 1, in: .trailing)
        }
    }

    /// Shows a progress bar, determinate for a `fraction` from 0 to 1 and
    /// indeterminate for nil, with a cancel button when `cancel` is given.
    /// Call again to update; `hideProgress()` removes it.
    public func showProgress(fraction: Double?, cancel: (() -> Void)? = nil) {
        if let fraction {
            progressIndicator.isIndeterminate = false
            progressIndicator.doubleValue = min(max(fraction, 0), 1)
            progressIndicator.stopAnimation(nil)
        } else {
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
        }
        onCancel = cancel
        progressIndicator.isHidden = false
        cancelButton.isHidden = cancel == nil
    }

    public func hideProgress() {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        cancelButton.isHidden = true
        onCancel = nil
    }

    public var isShowingProgress: Bool { !progressIndicator.isHidden }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        zoomControl.target = self
        zoomControl.action = #selector(zoomClicked)
        zoomControl.toolTip = "Zoom out · click the percentage to reset to 100% · zoom in"

        configureZoomField()
        configureProgress()

        trailingRow.orientation = .horizontal
        trailingRow.alignment = .centerY
        trailingRow.spacing = 8
        trailingRow.setViews([progressIndicator, cancelButton, zoomControl], in: .trailing)
        trailingRow.setCustomSpacing(4, after: progressIndicator)
        trailingRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trailingRow)
        addSubview(zoomField)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingRow.leadingAnchor, constant: -12),
            trailingRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            trailingRow.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Over the percentage segment: 20 pt of minus button, then 44.
            zoomField.leadingAnchor.constraint(equalTo: zoomControl.leadingAnchor, constant: 21),
            zoomField.widthAnchor.constraint(equalToConstant: 42),
            zoomField.centerYAnchor.constraint(equalTo: zoomControl.centerYAnchor),
        ])
        syncZoomPresentation()
    }

    private func configureZoomField() {
        zoomField.font = .systemFont(ofSize: 10)
        zoomField.alignment = .center
        zoomField.isBordered = false
        zoomField.drawsBackground = false
        zoomField.focusRingType = .none
        zoomField.delegate = self
        zoomField.target = self
        zoomField.action = #selector(zoomTyped(_:))
        zoomField.toolTip = "Type a zoom and press Return"
        zoomField.setAccessibilityLabel("Zoom")
        zoomField.translatesAutoresizingMaskIntoConstraints = false
        zoomField.isHidden = true
    }

    private func configureProgress() {
        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.isHidden = true
        progressIndicator.setAccessibilityLabel("Progress")
        progressIndicator.widthAnchor.constraint(equalToConstant: 110).isActive = true

        cancelButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                     accessibilityDescription: "Cancel")
        cancelButton.imagePosition = .imageOnly
        cancelButton.isBordered = false
        cancelButton.contentTintColor = .secondaryLabelColor
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.toolTip = "Cancel"
        cancelButton.setAccessibilityLabel("Cancel")
        cancelButton.isHidden = true
    }

    private func syncZoomPresentation() {
        let text = "\(zoomPercent)%"
        zoomField.isHidden = !isZoomEditable
        zoomControl.setGlyph(.letter(isZoomEditable ? "" : text, font: .systemFont(ofSize: 10)),
                             forSegment: 1)
        if zoomField.currentEditor() == nil {
            zoomField.stringValue = text
        }
        zoomControl.toolTip = isZoomEditable
            ? "Zoom out · type a zoom · zoom in"
            : "Zoom out · click the percentage to reset to 100% · zoom in"
    }

    @objc private func zoomTyped(_ sender: NSTextField) {
        commitZoomField()
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        commitZoomField()
    }

    /// Escape puts the shown zoom back.
    public func control(_ control: NSControl, textView: NSTextView,
                        doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        zoomField.stringValue = "\(zoomPercent)%"
        window?.makeFirstResponder(nil)
        return true
    }

    private func commitZoomField() {
        guard let percent = Self.zoomPercent(from: zoomField.stringValue) else {
            zoomField.stringValue = "\(zoomPercent)%"
            return
        }
        if percent != zoomPercent {
            onZoomTo?(percent)
        }
        zoomField.stringValue = "\(zoomPercent)%"
    }

    /// The largest zoom a person can type; the application clamps to the
    /// zooms it supports anyway, and anything past this is a typing slip.
    static let maximumTypedZoom = 1_000_000

    /// "250", "250%" or " 250 % ": a positive whole percentage up to
    /// `maximumTypedZoom`.
    static func zoomPercent(from text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        // Bounded on both sides before the conversion, which traps outside
        // Int's range; the rounded value must be positive, so "0.4" is
        // refused like "0".
        guard let value = Double(digits), value.isFinite, value > 0,
              value <= Double(maximumTypedZoom) else { return nil }
        let percent = Int(value.rounded())
        return percent > 0 ? percent : nil
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    // MARK: Test access

    var zoomFieldControl: NSTextField { zoomField }
    var cancelControl: NSButton { cancelButton }
    var progressControl: NSProgressIndicator { progressIndicator }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        activationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activationObservers.forEach(NotificationCenter.default.removeObserver)
        activationObservers = []
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification
        ]
        for name in names {
            activationObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.refreshLabel()
                })
        }
        refreshLabel()
    }

    private func refreshLabel() {
        label.attributedStringValue = ClassicText.engraved(
            message, size: 11, active: ClassicChrome.active(for: self))
    }

    /// The engraved label keeps its color in attributed-string state, so a
    /// scheme change re-sets it like an activation change does.
    func chromeSchemeDidChange() {
        refreshLabel()
    }

    @objc private func zoomClicked() {
        switch zoomControl.selectedSegment {
        case 0: onZoomOut?()
        case 1 where isZoomEditable: window?.makeFirstResponder(zoomField)
        case 1: onZoomReset?()
        case 2: onZoomIn?()
        default: break
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        ClassicChrome.statusBarGradient(active: active).draw(in: bounds, angle: 90)
        ClassicChrome.barBottomBorder(active).setFill()  // top border, mirroring the format bar's bottom
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        ClassicChrome.barTopHighlight.setFill()          // etched highlight just under it
        NSRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 1).fill()
    }
}
