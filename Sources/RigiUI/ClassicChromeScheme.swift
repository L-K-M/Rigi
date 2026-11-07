// ClassicChromeScheme.swift — opt-in chrome color schemes.
//
// `ClassicChromeScheme` names the chrome palettes `ClassicChrome` resolves its
// semantic colors from. `classicLight` is the original chrome and stays the
// default; `neutralGray` and `dark` are opt-in. The library never persists a
// choice: the application owns the preference and calls
// `ClassicChrome.apply(scheme:)` on the main thread when it changes.
//
// A scheme recolors chrome only — gradients, engraving, glyphs, borders,
// wells, and palette title/body/tab chrome. Document and canvas content keeps
// the window's own appearance and is not invalidated.

import AppKit

/// The chrome color scheme `ClassicChrome` draws with.
public enum ClassicChromeScheme: String, CaseIterable, Sendable {
    /// The original light chrome: white highlights, gray gradients, dark
    /// engraving. The default; Increase Contrast still strengthens its
    /// text and meaningful outlines.
    case classicLight
    /// Graphite chrome: softer gray gradients and wells, still light content.
    case neutralGray
    /// Dark chrome: deep gradients, light lettering, dark wells.
    case dark

    /// The scheme's name for a consumer's preference UI.
    public var displayName: String {
        switch self {
        case .classicLight: return "Classic Light"
        case .neutralGray: return "Neutral Gray"
        case .dark: return "Dark"
        }
    }
}

extension ClassicChromeScheme {
    /// The resolved color table for the scheme.
    var palette: ClassicChromePalette {
        switch self {
        case .classicLight: return .classicLight
        case .neutralGray: return .neutralGray
        case .dark: return .dark
        }
    }
}

extension ClassicChrome {
    /// The `NSAppearance` matching the applied scheme, for palette windows,
    /// popovers, and chrome containers so their native controls follow.
    /// Internal: `apply(scheme:)` installs it; consumers do not set it.
    static var schemeAppearance: NSAppearance? {
        switch scheme {
        case .classicLight, .neutralGray: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Applies `scheme` to all Rigi chrome: existing windows, palettes, and
    /// popovers adopt the scheme's appearance, `ClassicChromeDrawing` views —
    /// including app-owned chrome — repaint in the new colors, and native
    /// controls inside chrome follow. Document content is left alone.
    ///
    /// Call on the main thread when the application's preference changes.
    /// Rigi does not persist the choice.
    @MainActor
    public static func apply(scheme newScheme: ClassicChromeScheme) {
        ClassicChromeRefresh.install()
        guard newScheme != scheme else { return }
        scheme = newScheme
        ClassicChromeRefresh.apply()
    }
}

extension Notification.Name {
    /// Posted after `ClassicChrome.apply(scheme:)` changes the chrome scheme,
    /// so Rigi-owned popovers can adopt the scheme appearance and repaint.
    static let classicChromeSchemeDidChange =
        Notification.Name("RigiUI.classicChromeSchemeDidChange")
}

/// A chrome view that keeps resolved colors in view state — an explicit
/// `backgroundColor`, a baked `attributedStringValue`, a pre-tinted image —
/// rather than resolving them in `draw`. `ClassicChromeRefresh` calls
/// `chromeSchemeDidChange` so those colors follow `ClassicChrome.apply`.
protocol ClassicChromeSchemeAware: AnyObject {
    func chromeSchemeDidChange()
}

/// Repaints chrome for the applied scheme or an accessibility display
/// change. Mirrors the activation redraw in `ClassicChromeActivation`, but
/// also adopts the scheme's `NSAppearance` on chrome containers so semantic
/// colors in native subviews follow.
enum ClassicChromeRefresh {

    private static var observersInstalled = false

    /// Observes Increase Contrast changes on the workspace's own
    /// notification center — where AppKit posts them — so every scheme
    /// re-resolves its strengthened text and outlines. Installed on the
    /// first `ClassicChrome.scheme` read, so default-scheme chrome follows
    /// the setting without an explicit `apply` call.
    static func install() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ClassicChromeRefresh.apply() }
        }
    }

    /// Marks every chrome surface in every window for the current scheme.
    @MainActor
    static func apply() {
        for window in NSApplication.shared.windows {
            if window is ClassicPaletteWindow {
                window.appearance = ClassicChrome.schemeAppearance
            }
            refresh(window.contentView)
        }
        NotificationCenter.default.post(name: .classicChromeSchemeDidChange, object: nil)
    }

    /// Adopts the scheme appearance on one chrome subtree and repaints it.
    /// Non-chrome views are only traversed — document views never conform to
    /// `ClassicChromeDrawing`, so their content is never invalidated.
    static func refresh(_ view: NSView?) {
        guard let view else { return }
        if view is any ClassicChromeDrawing {
            view.appearance = ClassicChrome.schemeAppearance
            (view as? ClassicChromeSchemeAware)?.chromeSchemeDidChange()
            view.needsDisplay = true
        }
        view.subviews.forEach { refresh($0) }
    }
}

/// Workspace facts the chrome palette resolves at draw time.
enum ClassicChromeEnvironment {
    /// Test hook: overrides the workspace's Increase Contrast flag.
    static var increaseContrastOverride: Bool?

    static var increaseContrast: Bool {
        increaseContrastOverride
            ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
}

/// A 1.0-alpha calibrated-white chrome color. `strong` replaces `level`
/// while Increase Contrast is on; the schemes pass one for the text and
/// meaningful outlines the setting is meant to strengthen.
private func chrome(_ level: CGFloat, strong: CGFloat? = nil) -> NSColor {
    let resolved = strong != nil && ClassicChromeEnvironment.increaseContrast
        ? strong! : level
    return NSColor(calibratedWhite: resolved, alpha: 1)
}

/// A calibrated-white shade at a fixed alpha (gloss highlights, inner seams,
/// pressed overlays).
private func shade(_ white: CGFloat, _ alpha: CGFloat) -> NSColor {
    NSColor(calibratedWhite: white, alpha: alpha)
}

/// The resolved chrome colors for one scheme. `ClassicChrome`'s accessors
/// forward here; every color resolves at draw time so a scheme change only
/// needs the chrome invalidation `ClassicChromeRefresh` performs.
struct ClassicChromePalette {

    // Surfaces and gradients.
    var barTopHighlight: () -> NSColor
    var toolbarGradient: (Bool) -> NSGradient
    var statusBarGradient: (Bool) -> NSGradient
    var panelGradient: (Bool) -> NSGradient
    var paletteTitleBarGradient: () -> NSGradient
    var selectedTabGradient: () -> NSGradient
    var bezelGradient: (ClassicChrome.BezelState, Bool) -> NSGradient

    // Borders, rules, and separators.
    var barBottomBorder: (Bool) -> NSColor
    var barInnerLine: (Bool) -> NSColor
    var bezelBorder: (Bool) -> NSColor
    var windowBorder: () -> NSColor
    var wellBorder: (Bool) -> NSColor
    var swatchFrame: (Bool) -> NSColor
    var segmentSeparator: (Bool) -> NSColor
    var tabSideHairline: () -> NSColor
    var tabSeparator: () -> NSColor
    var etchedSeparatorLeading: (Bool) -> NSColor
    var etchedSeparatorTrailing: () -> NSColor
    var ruleDark: () -> NSColor
    var ruleLight: () -> NSColor
    var listWellRule: () -> NSColor

    // Text, glyphs, and engraving.
    var glyphColor: (Bool) -> NSColor
    var titleColor: (Bool) -> NSColor
    var arrowColor: (Bool) -> NSColor
    var secondaryText: () -> NSColor
    var pressedGlyph: () -> NSColor
    var engravedText: (CGFloat, Bool) -> NSColor
    var engravedShadow: (Bool) -> NSColor
    var innerHintHighlight: (Bool) -> NSColor
    var innerHintShadow: (Bool) -> NSColor

    // Wells, fields, and swatches.
    var wellFill: () -> NSColor
    var fieldInsetShadow: () -> NSColor
    var wellInsetShadow: () -> NSColor
    var swatchInnerRule: () -> NSColor
    var pressedOverlay: () -> NSColor
    var disabledSwatchBlend: () -> NSColor
}

extension ClassicChromePalette {

    /// The original chrome colors, unchanged while Increase Contrast is
    /// off: the default scheme. The setting still darkens its text and
    /// meaningful outlines — surfaces, fills, and decorative roles do not
    /// move.
    static let classicLight = ClassicChromePalette(
        barTopHighlight: { shade(1.0, 0.6) },
        toolbarGradient: { active in
            ClassicChrome.gradient(
                top: active ? 0.965 : 0.975, bottom: active ? 0.795 : 0.90)
        },
        statusBarGradient: { active in
            ClassicChrome.gradient(
                top: active ? 0.94 : 0.965, bottom: active ? 0.78 : 0.885)
        },
        panelGradient: { active in
            ClassicChrome.gradient(
                top: active ? 0.97 : 0.975, bottom: active ? 0.86 : 0.92)
        },
        paletteTitleBarGradient: {
            ClassicChrome.gradient(top: 0.965, bottom: 0.80)
        },
        selectedTabGradient: {
            ClassicChrome.gradient(top: 0.985, bottom: 0.97)
        },
        bezelGradient: { state, active in
            guard active else {
                switch state {
                case .normal: return ClassicChrome.gradient(top: 0.99, bottom: 0.94)
                case .on: return ClassicChrome.gradient(top: 0.84, bottom: 0.90)
                case .pressed: return ClassicChrome.gradient(top: 0.60, bottom: 0.74)
                }
            }
            switch state {
            case .normal: return ClassicChrome.gradient(top: 1.00, bottom: 0.86)
            case .on: return ClassicChrome.gradient(top: 0.68, bottom: 0.82)
            case .pressed: return ClassicChrome.gradient(top: 0.60, bottom: 0.74)
            }
        },
        barBottomBorder: { active in
            chrome(active ? 0.45 : 0.60, strong: active ? 0.32 : 0.47)
        },
        barInnerLine: { active in
            chrome(active ? 0.66 : 0.80, strong: active ? 0.53 : 0.67)
        },
        bezelBorder: { active in
            chrome(active ? 0.47 : 0.65, strong: active ? 0.34 : 0.52)
        },
        windowBorder: { chrome(0.45, strong: 0.30) },
        wellBorder: { active in
            chrome(active ? 0.55 : 0.68, strong: active ? 0.42 : 0.55)
        },
        swatchFrame: { active in
            chrome(active ? 0.35 : 0.55, strong: active ? 0.22 : 0.42)
        },
        segmentSeparator: { active in
            chrome(active ? 0.55 : 0.70, strong: active ? 0.42 : 0.57)
        },
        tabSideHairline: { chrome(0.55, strong: 0.42) },
        tabSeparator: { chrome(0.62, strong: 0.49) },
        etchedSeparatorLeading: { active in
            chrome(active ? 0.58 : 0.72, strong: active ? 0.45 : 0.59)
        },
        etchedSeparatorTrailing: { shade(1.0, 0.8) },
        ruleDark: { chrome(0.68, strong: 0.55) },
        ruleLight: { shade(1.0, 0.85) },
        listWellRule: { chrome(0.74, strong: 0.61) },
        glyphColor: { active in
            chrome(active ? 0.18 : 0.45, strong: active ? 0.05 : 0.30)
        },
        titleColor: { active in
            chrome(active ? 0.13 : 0.45, strong: active ? 0.0 : 0.30)
        },
        arrowColor: { active in
            chrome(active ? 0.25 : 0.50, strong: active ? 0.12 : 0.35)
        },
        secondaryText: { chrome(0.45, strong: 0.30) },
        pressedGlyph: { .black },
        engravedText: { gray, active in
            let level = active ? gray : min(gray + 0.26, 0.62)
            let resolved = ClassicChromeEnvironment.increaseContrast
                ? max(level - 0.12, 0) : level
            return NSColor(calibratedWhite: resolved, alpha: 1)
        },
        engravedShadow: { active in shade(1.0, active ? 0.65 : 0.4) },
        innerHintHighlight: { active in shade(1.0, active ? 0.55 : 0.35) },
        innerHintShadow: { active in shade(0.25, active ? 0.22 : 0.12) },
        wellFill: { .white },
        fieldInsetShadow: { shade(0, 0.07) },
        wellInsetShadow: { shade(0, 0.06) },
        swatchInnerRule: { .white },
        pressedOverlay: { shade(0, 0.25) },
        disabledSwatchBlend: { .white }
    )

    /// Graphite chrome: the same construction on a grayer, softer palette.
    /// Wells stay light; outlines and text deepen under Increase Contrast.
    static let neutralGray = ClassicChromePalette(
        barTopHighlight: { shade(1.0, 0.45) },
        toolbarGradient: { active in
            ClassicChrome.gradient(
                top: active ? 0.93 : 0.94, bottom: active ? 0.74 : 0.83)
        },
        statusBarGradient: { active in
            ClassicChrome.gradient(
                top: active ? 0.885 : 0.92, bottom: active ? 0.71 : 0.815)
        },
        panelGradient: { active in
            ClassicChrome.gradient(
                top: active ? 0.925 : 0.94, bottom: active ? 0.81 : 0.875)
        },
        paletteTitleBarGradient: {
            ClassicChrome.gradient(top: 0.93, bottom: 0.755)
        },
        selectedTabGradient: {
            ClassicChrome.gradient(top: 0.95, bottom: 0.895)
        },
        bezelGradient: { state, active in
            guard active else {
                switch state {
                case .normal: return ClassicChrome.gradient(top: 0.94, bottom: 0.885)
                case .on: return ClassicChrome.gradient(top: 0.83, bottom: 0.885)
                case .pressed: return ClassicChrome.gradient(top: 0.64, bottom: 0.75)
                }
            }
            switch state {
            case .normal: return ClassicChrome.gradient(top: 0.95, bottom: 0.80)
            case .on: return ClassicChrome.gradient(top: 0.74, bottom: 0.85)
            case .pressed: return ClassicChrome.gradient(top: 0.64, bottom: 0.75)
            }
        },
        barBottomBorder: { active in
            chrome(active ? 0.50 : 0.66, strong: active ? 0.36 : 0.52)
        },
        barInnerLine: { active in
            chrome(active ? 0.70 : 0.82, strong: active ? 0.55 : 0.68)
        },
        bezelBorder: { active in
            chrome(active ? 0.52 : 0.68, strong: active ? 0.36 : 0.54)
        },
        windowBorder: { chrome(0.50, strong: 0.34) },
        wellBorder: { active in
            chrome(active ? 0.58 : 0.70, strong: active ? 0.42 : 0.56)
        },
        swatchFrame: { active in
            chrome(active ? 0.40 : 0.60, strong: active ? 0.26 : 0.46)
        },
        segmentSeparator: { active in
            chrome(active ? 0.60 : 0.73, strong: active ? 0.44 : 0.60)
        },
        tabSideHairline: { chrome(0.60, strong: 0.44) },
        tabSeparator: { chrome(0.66, strong: 0.50) },
        etchedSeparatorLeading: { active in
            chrome(active ? 0.62 : 0.75, strong: active ? 0.46 : 0.62)
        },
        etchedSeparatorTrailing: { shade(1.0, 0.7) },
        ruleDark: { chrome(0.66, strong: 0.50) },
        ruleLight: { shade(1.0, 0.8) },
        listWellRule: { chrome(0.72, strong: 0.55) },
        glyphColor: { active in
            chrome(active ? 0.24 : 0.50, strong: active ? 0.10 : 0.36)
        },
        titleColor: { active in
            chrome(active ? 0.18 : 0.50, strong: active ? 0.06 : 0.36)
        },
        arrowColor: { active in
            chrome(active ? 0.32 : 0.55, strong: active ? 0.16 : 0.42)
        },
        secondaryText: { chrome(0.48, strong: 0.32) },
        pressedGlyph: { .black },
        engravedText: { gray, active in
            let level = active ? gray : min(gray + 0.26, 0.62)
            let resolved = ClassicChromeEnvironment.increaseContrast
                ? max(level - 0.10, 0.05) : level
            return NSColor(calibratedWhite: resolved, alpha: 1)
        },
        engravedShadow: { active in shade(1.0, active ? 0.55 : 0.38) },
        innerHintHighlight: { active in shade(1.0, active ? 0.45 : 0.30) },
        innerHintShadow: { active in shade(0.25, active ? 0.18 : 0.10) },
        wellFill: { shade(0.97, 1) },
        fieldInsetShadow: { shade(0, 0.06) },
        wellInsetShadow: { shade(0, 0.05) },
        swatchInnerRule: { .white },
        pressedOverlay: { shade(0, 0.25) },
        disabledSwatchBlend: { .white }
    )

    /// Dark chrome: deep gradients, light lettering, dark wells. Outlines and
    /// text strengthen toward white under Increase Contrast.
    static let dark = ClassicChromePalette(
        barTopHighlight: { shade(1.0, 0.15) },
        toolbarGradient: { active in
            ClassicChrome.gradient(
                top: active ? 0.33 : 0.345, bottom: active ? 0.21 : 0.26)
        },
        statusBarGradient: { active in
            ClassicChrome.gradient(
                top: active ? 0.30 : 0.335, bottom: active ? 0.185 : 0.25)
        },
        panelGradient: { active in
            ClassicChrome.gradient(
                top: active ? 0.295 : 0.33, bottom: active ? 0.21 : 0.255)
        },
        paletteTitleBarGradient: {
            ClassicChrome.gradient(top: 0.335, bottom: 0.225)
        },
        selectedTabGradient: {
            ClassicChrome.gradient(top: 0.37, bottom: 0.29)
        },
        bezelGradient: { state, active in
            guard active else {
                switch state {
                case .normal: return ClassicChrome.gradient(top: 0.37, bottom: 0.315)
                case .on: return ClassicChrome.gradient(top: 0.46, bottom: 0.41)
                case .pressed: return ClassicChrome.gradient(top: 0.26, bottom: 0.36)
                }
            }
            switch state {
            case .normal: return ClassicChrome.gradient(top: 0.44, bottom: 0.33)
            case .on: return ClassicChrome.gradient(top: 0.52, bottom: 0.43)
            case .pressed: return ClassicChrome.gradient(top: 0.26, bottom: 0.36)
            }
        },
        barBottomBorder: { active in
            chrome(active ? 0.62 : 0.72, strong: active ? 0.80 : 0.86)
        },
        barInnerLine: { active in
            chrome(active ? 0.18 : 0.28, strong: active ? 0.10 : 0.20)
        },
        bezelBorder: { active in
            chrome(active ? 0.60 : 0.70, strong: active ? 0.78 : 0.84)
        },
        windowBorder: { chrome(0.62, strong: 0.82) },
        wellBorder: { active in
            chrome(active ? 0.60 : 0.70, strong: active ? 0.78 : 0.84)
        },
        swatchFrame: { active in
            chrome(active ? 0.68 : 0.76, strong: active ? 0.84 : 0.88)
        },
        segmentSeparator: { active in
            chrome(active ? 0.55 : 0.68, strong: active ? 0.74 : 0.80)
        },
        tabSideHairline: { chrome(0.64, strong: 0.80) },
        tabSeparator: { chrome(0.56, strong: 0.74) },
        etchedSeparatorLeading: { active in
            chrome(active ? 0.72 : 0.80, strong: active ? 0.86 : 0.90)
        },
        etchedSeparatorTrailing: { shade(0.10, 0.7) },
        ruleDark: { chrome(0.72, strong: 0.86) },
        ruleLight: { shade(0.05, 0.75) },
        listWellRule: { chrome(0.62, strong: 0.78) },
        glyphColor: { active in
            chrome(active ? 0.88 : 0.60, strong: active ? 0.97 : 0.74)
        },
        titleColor: { active in
            chrome(active ? 0.92 : 0.62, strong: active ? 1.0 : 0.76)
        },
        arrowColor: { active in
            chrome(active ? 0.80 : 0.56, strong: active ? 0.92 : 0.70)
        },
        secondaryText: { chrome(0.68, strong: 0.82) },
        pressedGlyph: { .white },
        engravedText: { gray, active in
            let level = 1.12 - gray
            let resolved = active ? level : max(level - 0.26, 0.45)
            let strong = ClassicChromeEnvironment.increaseContrast
                ? min(resolved + 0.08, 0.98) : resolved
            return NSColor(calibratedWhite: strong, alpha: 1)
        },
        engravedShadow: { active in shade(0.0, active ? 0.45 : 0.30) },
        innerHintHighlight: { active in shade(1.0, active ? 0.14 : 0.08) },
        innerHintShadow: { active in shade(0.0, active ? 0.30 : 0.20) },
        wellFill: { shade(0.17, 1) },
        fieldInsetShadow: { shade(1.0, 0.05) },
        wellInsetShadow: { shade(1.0, 0.045) },
        swatchInnerRule: { shade(0.22, 1) },
        pressedOverlay: { shade(0, 0.30) },
        disabledSwatchBlend: { shade(0.30, 1) }
    )
}

// MARK: - Semantic chrome accessors
//
// These resolve the applied scheme at call time. The pre-existing accessors
// (`glyphColor`, `bezelGradient`, …) forward to the same palette; the ones
// below cover the surfaces, wells, and chrome parts that previously held
// literal grays, so app-owned chrome can resolve them too.

extension ClassicChrome {

    /// The toolbar bar's vertical gradient (format bars, tool strips).
    public static func toolbarGradient(active: Bool) -> NSGradient {
        scheme.palette.toolbarGradient(active)
    }

    /// The status bar's vertical gradient.
    public static func statusBarGradient(active: Bool) -> NSGradient {
        scheme.palette.statusBarGradient(active)
    }

    /// The panel and palette-body vertical gradient.
    public static func panelGradient(active: Bool) -> NSGradient {
        scheme.palette.panelGradient(active)
    }

    /// A floating palette's title-bar gradient; palettes always draw at full
    /// (active) strength.
    public static func paletteTitleBarGradient() -> NSGradient {
        scheme.palette.paletteTitleBarGradient()
    }

    /// The fill of the selected palette tab.
    public static func selectedTabGradient() -> NSGradient {
        scheme.palette.selectedTabGradient()
    }

    /// The floating palette window's hairline silhouette stroke.
    public static func windowBorder() -> NSColor {
        scheme.palette.windowBorder()
    }

    /// The hairline beside a selected palette tab.
    public static func tabSideHairline() -> NSColor {
        scheme.palette.tabSideHairline()
    }

    /// The hairline between unselected palette tabs.
    public static func tabSeparator() -> NSColor {
        scheme.palette.tabSeparator()
    }

    /// The darker line of an etched separator.
    public static func etchedSeparatorLeading(_ active: Bool) -> NSColor {
        scheme.palette.etchedSeparatorLeading(active)
    }

    /// The lighter line of an etched separator.
    public static func etchedSeparatorTrailing() -> NSColor {
        scheme.palette.etchedSeparatorTrailing()
    }

    /// The dark line of a `ClassicRuleView` ornament.
    public static func ruleDark() -> NSColor {
        scheme.palette.ruleDark()
    }

    /// The light line of a `ClassicRuleView` ornament.
    public static func ruleLight() -> NSColor {
        scheme.palette.ruleLight()
    }

    /// The fill of an inset well (picker lists, size fields, inset boxes).
    public static func wellFill() -> NSColor {
        scheme.palette.wellFill()
    }

    /// The hairline border of an inset well.
    public static func wellBorder(_ active: Bool) -> NSColor {
        scheme.palette.wellBorder(active)
    }

    /// The faint top inner shadow of a text-entry well.
    public static func fieldInsetShadow() -> NSColor {
        scheme.palette.fieldInsetShadow()
    }

    /// The faint top inner shadow of an inset box.
    public static func wellInsetShadow() -> NSColor {
        scheme.palette.wellInsetShadow()
    }

    /// The frame around a color well's swatch.
    public static func swatchFrame(_ active: Bool) -> NSColor {
        scheme.palette.swatchFrame(active)
    }

    /// The light rule between a swatch frame and its color.
    public static func swatchInnerRule() -> NSColor {
        scheme.palette.swatchInnerRule()
    }

    /// The glyph color for pressed indicators that must stay readable on
    /// chrome (the color pair's swap arrow).
    public static func pressedGlyph() -> NSColor {
        scheme.palette.pressedGlyph()
    }

    /// The dimming overlay on a pressed color swatch.
    public static func pressedOverlay() -> NSColor {
        scheme.palette.pressedOverlay()
    }

    /// The color disabled color swatches blend toward.
    public static func disabledSwatchBlend() -> NSColor {
        scheme.palette.disabledSwatchBlend()
    }

    /// Secondary chrome text (picker hints, dimmed rows, captions).
    public static func secondaryText() -> NSColor {
        scheme.palette.secondaryText()
    }

    /// The hairline rules framing a picker's inset well.
    public static func listWellRule() -> NSColor {
        scheme.palette.listWellRule()
    }

    /// The mid-tone line under a bar's top highlight.
    public static func barInnerLine(_ active: Bool) -> NSColor {
        scheme.palette.barInnerLine(active)
    }

    /// The light seam inside a raised bezel's top edge.
    public static func innerHintHighlight(_ active: Bool) -> NSColor {
        scheme.palette.innerHintHighlight(active)
    }

    /// The dark seam inside a sunken bezel's top edge.
    public static func innerHintShadow(_ active: Bool) -> NSColor {
        scheme.palette.innerHintShadow(active)
    }

    /// The drop shadow under engraved chrome lettering.
    public static func engravedShadow(_ active: Bool) -> NSColor {
        scheme.palette.engravedShadow(active)
    }
}
