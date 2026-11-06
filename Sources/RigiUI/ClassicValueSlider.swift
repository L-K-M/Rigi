import AppKit

/// A labelled value with a slider and a number field kept in step, for
/// settings such as brush size, opacity or a color component.
///
/// The slider reports `.tracking` while it is dragged and `.committed` when
/// it is released; a typed value, Return, leaving the field and the arrow
/// keys report `.committed`. An application that records undo does so on
/// `.committed`, so one drag is one step. Values are clamped to the range
/// and rounded to `fractionDigits`; text that is not a number puts the field
/// back to the current value without reporting.
public final class ClassicValueSlider: NSView, NSTextFieldDelegate {

    public enum Phase: Equatable { case tracking, committed }

    public static let sliderWidth: CGFloat = 110
    public static let fieldWidth: CGFloat = 40

    /// Clamped to `range` and rounded to `fractionDigits`. Setting it does
    /// not report a change.
    public var value: Double {
        get { currentValue }
        set {
            currentValue = normalized(newValue)
            syncControls()
        }
    }

    public var range: ClosedRange<Double> {
        didSet {
            slider.minValue = range.lowerBound
            slider.maxValue = range.upperBound
            value = currentValue
        }
    }

    public var isEnabled = true {
        didSet {
            slider.isEnabled = isEnabled
            field.isEnabled = isEnabled
            titleLabel.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        }
    }

    /// Width of the label column, so rows in a form line up.
    public var titleWidth: CGFloat {
        get { titleWidthConstraint.constant }
        set { titleWidthConstraint.constant = newValue }
    }

    public var onChange: ((Double, Phase) -> Void)?

    private let fractionDigits: Int
    private var currentValue: Double
    /// Set once a drag has reported `.tracking`, so its release reports
    /// `.committed` even when the value stayed put.
    private var isTracking = false
    private let titleLabel: NSTextField
    private let slider = NSSlider()
    private let field = NSTextField()
    private let unitLabel: NSTextField
    private var titleWidthConstraint: NSLayoutConstraint!

    /// `title` labels the row and names both controls for VoiceOver; nil
    /// leaves the label out, for a row whose label is elsewhere.
    /// `fractionDigits` is limited to 0 through 15.
    public init(title: String?, range: ClosedRange<Double>, value: Double,
                unit: String = "", fractionDigits: Int = 0) {
        precondition(range.lowerBound.isFinite && range.upperBound.isFinite,
                     "A value slider needs a finite range")
        self.range = range
        self.fractionDigits = min(max(0, fractionDigits), Self.maximumFractionDigits)
        currentValue = range.lowerBound
        titleLabel = NSTextField(labelWithString: title ?? "")
        unitLabel = NSTextField(labelWithString: unit)
        super.init(frame: .zero)

        configure(title: title)
        self.value = value
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure(title: String?) {
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.alignment = .right
        titleLabel.isHidden = title == nil

        slider.controlSize = .small
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))

        field.controlSize = .small
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.alignment = .right
        field.delegate = self
        field.target = self
        field.action = #selector(fieldCommitted(_:))

        unitLabel.font = .systemFont(ofSize: 11)
        unitLabel.isHidden = unitLabel.stringValue.isEmpty

        accessibilityTitle = title
        applyAccessibilityTitle()

        let row = NSStackView(views: [titleLabel, slider, field, unitLabel])
        row.spacing = 4
        row.setCustomSpacing(6, after: titleLabel)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        titleWidthConstraint = titleLabel.widthAnchor.constraint(equalToConstant: 62)
        NSLayoutConstraint.activate([
            titleWidthConstraint,
            slider.widthAnchor.constraint(equalToConstant: Self.sliderWidth),
            field.widthAnchor.constraint(equalToConstant: Self.fieldWidth),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    // MARK: Changes

    @objc private func sliderMoved(_ sender: NSSlider) {
        commit(sender.doubleValue, phase: Self.phase(after: NSApp.currentEvent?.type))
    }

    /// A press or drag on the knob is still tracking; its release, an
    /// arrow key, or any other way the slider moves is a finished change.
    static func phase(after event: NSEvent.EventType?) -> Phase {
        switch event {
        case .leftMouseDown?, .leftMouseDragged?: return .tracking
        default: return .committed
        }
    }

    /// What VoiceOver calls the slider and its field; it starts as the
    /// title. Set it when the row's label is not the slider's own.
    public var accessibilityTitle: String? {
        didSet { applyAccessibilityTitle() }
    }

    private func applyAccessibilityTitle() {
        slider.setAccessibilityLabel(accessibilityTitle)
        field.setAccessibilityLabel(accessibilityTitle.map { "\($0) value" })
    }

    @objc private func fieldCommitted(_ sender: NSTextField) {
        commitField()
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        commitField()
    }

    /// Up and Down step the value by one unit of its precision, ten with
    /// Shift.
    public func control(_ control: NSControl, textView: NSTextView,
                        doCommandBy selector: Selector) -> Bool {
        let direction: Double
        switch selector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveUpAndModifySelection(_:)):
            direction = 1
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveDownAndModifySelection(_:)):
            direction = -1
        default:
            return false
        }

        let shifted = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        step(by: direction * (shifted ? 10 : 1))
        return true
    }

    /// Moves the value by `steps` units of its precision and reports it.
    func step(by steps: Double) {
        commit(currentValue + steps * stepSize, phase: .committed)
        field.currentEditor()?.selectAll(nil)
    }

    private var stepSize: Double { pow(10, -Double(fractionDigits)) }

    private func commitField() {
        guard let typed = Self.number(from: field.stringValue) else {
            syncControls()
            return
        }
        commit(typed, phase: .committed)
    }

    /// The one path user changes take: normalize, show, report.
    func commit(_ raw: Double, phase: Phase) {
        guard isEnabled, raw.isFinite else {
            syncControls()
            return
        }

        let next = normalized(raw)
        let changed = next != currentValue
        let endsDrag = phase == .committed && isTracking
        currentValue = next
        isTracking = phase == .tracking && (changed || isTracking)
        syncControls()
        guard changed || endsDrag else { return }

        onChange?(next, phase)
    }

    /// A Double holds about 15 significant decimal digits; more fraction
    /// digits round nothing, and past about 308 the scale overflows.
    static let maximumFractionDigits = 15

    private func normalized(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        let scale = pow(10, Double(fractionDigits))
        let scaled = clamped * scale
        // A value too large to scale has no fraction digits left to round.
        guard scaled.isFinite else { return clamped }
        return scaled.rounded() / scale
    }

    private func syncControls() {
        slider.doubleValue = currentValue
        let text = Self.format(currentValue, fractionDigits: fractionDigits)
        if field.stringValue != text {
            field.stringValue = text
        }
        field.setAccessibilityValue(text + (unitLabel.stringValue.isEmpty ? "" : " \(unitLabel.stringValue)"))
    }

    static func format(_ value: Double, fractionDigits: Int) -> String {
        String(format: "%.\(max(0, fractionDigits))f", value)
    }

    /// Accepts the field's own format, a leading sign, a decimal comma, and
    /// a trailing unit or percent sign typed along with the number.
    static func number(from text: String) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        while let last = trimmed.last, !last.isNumber, last != "." {
            trimmed.removeLast()
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: Test access

    var sliderControl: NSSlider { slider }
    var fieldControl: NSTextField { field }
}
