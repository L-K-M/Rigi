import AppKit

/// Native segmented-control semantics, including per-segment help, accessibility,
/// and toolbar customization, with the same bezel as the formatting controls.
public final class ClassicToolControl: NSSegmentedControl {
    public override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width, height: ClassicChrome.controlHeight)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard segmentCount > 0 else { return }
        let active = ClassicChrome.active(for: self) && isEnabled
        let outline = ClassicChrome.bezelOutline(in: bounds)
        let fixedWidth = (0..<segmentCount).reduce(CGFloat.zero) { $0 + width(forSegment: $1) }
        let flexibleCount = (0..<segmentCount).filter { width(forSegment: $0) == 0 }.count
        let flexibleWidth = max(0, bounds.width - fixedWidth) / CGFloat(max(1, flexibleCount))
        var x = bounds.minX

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        for index in 0..<segmentCount {
            let segmentWidth = width(forSegment: index)
            let rect = NSRect(x: x, y: bounds.minY,
                              width: segmentWidth > 0 ? segmentWidth : flexibleWidth,
                              height: bounds.height)
            let pressed = cell?.isHighlighted == true && selectedSegment == index
            let state: ClassicChrome.BezelState = pressed ? .pressed
                : (isSelected(forSegment: index) ? .on : .normal)
            let enabled = active && isEnabled(forSegment: index)
            ClassicChrome.bezelGradient(state, active: enabled).draw(in: rect, angle: 90)
            ClassicChrome.drawInnerHint(state, in: rect, active: enabled)
            if let image = image(forSegment: index) {
                ClassicGlyph.image(image).draw(centeredIn: rect, active: enabled)
            } else {
                ClassicGlyph.letter(label(forSegment: index) ?? "", font: .systemFont(ofSize: 11))
                    .draw(centeredIn: rect, active: enabled)
            }
            if index > 0 {
                ClassicChrome.segmentSeparator(active).setFill()
                NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height).fill()
            }
            x = rect.maxX
        }
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder(active).setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }
}

/// An ordinary AppKit button with a compact classic bezel. Native tracking,
/// keyboard activation, and accessibility stay owned by NSButton.
public final class ClassicToolbarButton: NSButton {
    public override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(size.width, ClassicChrome.controlHeight + 8),
                      height: ClassicChrome.controlHeight)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self) && isEnabled
        let bezelState: ClassicChrome.BezelState = isHighlighted ? .pressed
            : (state == .on ? .on : .normal)
        let outline = ClassicChrome.bezelOutline(in: bounds)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        ClassicChrome.bezelGradient(bezelState, active: active).draw(in: bounds, angle: 90)
        ClassicChrome.drawInnerHint(bezelState, in: bounds, active: active)
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder(active).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        if let image, imagePosition == .imageOnly {
            ClassicGlyph.image(image).draw(centeredIn: bounds, active: active)
            return
        }
        ClassicGlyph.letter(title, font: .systemFont(ofSize: 11))
            .draw(centeredIn: bounds, active: active)
    }
}
