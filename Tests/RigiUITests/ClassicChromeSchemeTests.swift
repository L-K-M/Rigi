import AppKit
import XCTest

@testable import RigiUI

/// The opt-in chrome schemes: `classicLight` keeps the original colors,
/// `neutralGray` and `dark` resolve distinct palettes, every scheme stays
/// grayscale with readable text and borders, Increase Contrast strengthens
/// text and meaningful outlines in every scheme, and `ClassicChrome.apply`
/// plus the workspace accessibility notification repaint chrome — windows,
/// palettes, popovers — without touching document views.
@MainActor
final class ClassicChromeSchemeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        ClassicChrome.apply(scheme: .classicLight)
        ClassicChromeEnvironment.increaseContrastOverride = nil
    }

    override func tearDown() {
        ClassicChrome.apply(scheme: .classicLight)
        ClassicChromeEnvironment.increaseContrastOverride = nil
        super.tearDown()
    }

    // MARK: - Default compatibility

    /// Every public chrome accessor still resolves the literal it drew
    /// before schemes existed, so the default output is unchanged while
    /// Increase Contrast is off.
    func testClassicLightKeepsTheOriginalChromeColors() {
        ClassicChromeEnvironment.increaseContrastOverride = false
        XCTAssertEqual(ClassicChrome.scheme, .classicLight)

        func check(_ actual: NSColor, _ white: CGFloat, alpha: CGFloat = 1,
                   _ name: String) {
            let expected = NSColor(calibratedWhite: white, alpha: alpha)
            XCTAssertTrue(actual.isEqual(expected),
                          "\(name): \(actual) != calibratedWhite \(white) @ \(alpha)")
        }

        check(ClassicChrome.barTopHighlight, 1.0, alpha: 0.6, "barTopHighlight")
        check(ClassicChrome.barBottomBorder(true), 0.45, "barBottomBorder active")
        check(ClassicChrome.barBottomBorder(false), 0.60, "barBottomBorder inactive")
        check(ClassicChrome.barInnerLine(true), 0.66, "barInnerLine active")
        check(ClassicChrome.barInnerLine(false), 0.80, "barInnerLine inactive")
        check(ClassicChrome.bezelBorder(true), 0.47, "bezelBorder active")
        check(ClassicChrome.bezelBorder(false), 0.65, "bezelBorder inactive")
        check(ClassicChrome.glyphColor(true), 0.18, "glyphColor active")
        check(ClassicChrome.glyphColor(false), 0.45, "glyphColor inactive")
        check(ClassicChrome.titleColor(true), 0.13, "titleColor active")
        check(ClassicChrome.titleColor(false), 0.45, "titleColor inactive")
        check(ClassicChrome.arrowColor(true), 0.25, "arrowColor active")
        check(ClassicChrome.arrowColor(false), 0.50, "arrowColor inactive")
        check(ClassicChrome.segmentSeparator(true), 0.55, "segmentSeparator active")
        check(ClassicChrome.segmentSeparator(false), 0.70, "segmentSeparator inactive")
        check(ClassicChrome.windowBorder(), 0.45, "windowBorder")
        check(ClassicChrome.wellBorder(true), 0.55, "wellBorder active")
        check(ClassicChrome.wellBorder(false), 0.68, "wellBorder inactive")
        check(ClassicChrome.swatchFrame(true), 0.35, "swatchFrame active")
        check(ClassicChrome.swatchFrame(false), 0.55, "swatchFrame inactive")
        check(ClassicChrome.tabSideHairline(), 0.55, "tabSideHairline")
        check(ClassicChrome.tabSeparator(), 0.62, "tabSeparator")
        check(ClassicChrome.etchedSeparatorLeading(true), 0.58, "etched leading active")
        check(ClassicChrome.etchedSeparatorLeading(false), 0.72, "etched leading inactive")
        check(ClassicChrome.etchedSeparatorTrailing(), 1.0, alpha: 0.8, "etched trailing")
        check(ClassicChrome.ruleDark(), 0.68, "ruleDark")
        check(ClassicChrome.ruleLight(), 1.0, alpha: 0.85, "ruleLight")
        check(ClassicChrome.listWellRule(), 0.74, "listWellRule")
        check(ClassicChrome.secondaryText(), 0.45, "secondaryText")
        check(ClassicChrome.fieldInsetShadow(), 0, alpha: 0.07, "fieldInsetShadow")
        check(ClassicChrome.wellInsetShadow(), 0, alpha: 0.06, "wellInsetShadow")
        check(ClassicChrome.pressedOverlay(), 0, alpha: 0.25, "pressedOverlay")
        check(ClassicChrome.innerHintHighlight(true), 1.0, alpha: 0.55, "inner hint highlight active")
        check(ClassicChrome.innerHintHighlight(false), 1.0, alpha: 0.35, "inner hint highlight inactive")
        check(ClassicChrome.innerHintShadow(true), 0.25, alpha: 0.22, "inner hint shadow active")
        check(ClassicChrome.innerHintShadow(false), 0.25, alpha: 0.12, "inner hint shadow inactive")
        check(ClassicChrome.engravedShadow(true), 1.0, alpha: 0.65, "engraved shadow active")
        check(ClassicChrome.engravedShadow(false), 1.0, alpha: 0.4, "engraved shadow inactive")

        let palette = ClassicChrome.scheme.palette
        check(palette.engravedText(0.22, true), 0.22, "engraved text active")
        check(palette.engravedText(0.22, false), 0.48, "engraved text inactive")
        check(palette.engravedText(0.38, false), 0.62, "engraved text inactive capped")

        XCTAssertTrue(ClassicChrome.pressedGlyph().isEqual(NSColor.black), "pressedGlyph")
        XCTAssertTrue(ClassicChrome.wellFill().isEqual(NSColor.white), "wellFill")
        XCTAssertTrue(ClassicChrome.swatchInnerRule().isEqual(NSColor.white), "swatchInnerRule")
        XCTAssertTrue(ClassicChrome.disabledSwatchBlend().isEqual(NSColor.white), "disabledSwatchBlend")
    }

    /// The bezel gradient is the most visible chrome surface; rasterizing it
    /// proves the default scheme draws the same pixels as the old literals.
    func testClassicLightBezelGradientIsUnchanged() {
        let drawn = ClassicChrome.bezelGradient(.normal, active: true)
        let original = ClassicChrome.gradient(top: 1.00, bottom: 0.86)
        XCTAssertEqual(gradientPixels(drawn), gradientPixels(original))
    }

    // MARK: - Distinctness and grayscale

    func testEachSchemeResolvesADistinctPalette() {
        var signatures: [ClassicChromeScheme: String] = [:]
        for scheme in ClassicChromeScheme.allCases {
            ClassicChrome.apply(scheme: scheme)
            signatures[scheme] = paletteSignature()
        }
        let schemes = ClassicChromeScheme.allCases
        for i in schemes.indices {
            for j in schemes.indices where j > i {
                XCTAssertNotEqual(signatures[schemes[i]], signatures[schemes[j]],
                                  "\(schemes[i]) and \(schemes[j]) draw identical chrome")
            }
        }
    }

    /// An opt-in scheme recolors most chrome roles, not just one accent.
    func testOptInSchemesRecolorMostChromeRoles() {
        ClassicChrome.apply(scheme: .classicLight)
        let light = paletteColors().map(colorSignature)
        let lightGradients = gradientSignatures()

        for scheme in [ClassicChromeScheme.neutralGray, .dark] {
            ClassicChrome.apply(scheme: scheme)
            let colors = paletteColors().map(colorSignature)
            let differing = zip(light, colors).filter { $0 != $1 }.count
            XCTAssertGreaterThan(differing, colors.count / 2,
                                 "\(scheme) should recolor most chrome roles")
            XCTAssertNotEqual(gradientSignatures(), lightGradients,
                              "\(scheme) should redraw the gradients")
        }
    }

    /// Every resolved chrome color is a shade of gray — the schemes are
    /// neutral by design, so nothing introduces color into the chrome.
    func testAllSchemeColorsAreGrayscale() {
        for scheme in ClassicChromeScheme.allCases {
            ClassicChrome.apply(scheme: scheme)
            for color in paletteColors() {
                let rgb = srgb(color)
                XCTAssertNotNil(rgb, "\(scheme): \(color) did not convert to sRGB")
                guard let rgb else { continue }
                XCTAssertEqual(rgb.r, rgb.g, accuracy: 0.02,
                               "\(scheme): \(color) is not gray")
                XCTAssertEqual(rgb.g, rgb.b, accuracy: 0.02,
                               "\(scheme): \(color) is not gray")
            }
        }
    }

    // MARK: - Readability

    /// Glyphs and titles stay readable over every stop of the bezel
    /// gradient, borders stay visible, and secondary text keeps the same
    /// floor the original hint gray had on white.
    func testChromeTextBordersAndSecondaryTextKeepReadableContrast() {
        for scheme in ClassicChromeScheme.allCases {
            ClassicChrome.apply(scheme: scheme)
            let stops = gradientLuminances(ClassicChrome.bezelGradient(.normal, active: true))
            XCTAssertFalse(stops.isEmpty)
            let glyph = colorLuminance(ClassicChrome.glyphColor(true))
            let title = colorLuminance(ClassicChrome.titleColor(true))
            let border = colorLuminance(ClassicChrome.bezelBorder(true))
            let secondary = colorLuminance(ClassicChrome.secondaryText())
            let well = colorLuminance(ClassicChrome.wellFill())
            guard let glyph, let title, let border, let secondary, let well else {
                XCTFail("\(scheme): a chrome color did not convert to sRGB")
                continue
            }
            for stop in stops {
                XCTAssertGreaterThanOrEqual(contrastRatio(glyph, stop), 2.5,
                    "\(scheme): glyph contrast \(contrastRatio(glyph, stop)) over fill \(stop)")
                XCTAssertGreaterThanOrEqual(contrastRatio(title, stop), 2.5,
                    "\(scheme): title contrast \(contrastRatio(title, stop)) over fill \(stop)")
                XCTAssertGreaterThanOrEqual(contrastRatio(border, stop), 1.5,
                    "\(scheme): border contrast \(contrastRatio(border, stop)) over fill \(stop)")
            }
            XCTAssertGreaterThanOrEqual(contrastRatio(secondary, well), 3.0,
                "\(scheme): secondary text contrast \(contrastRatio(secondary, well)) on wells")
        }
    }

    // MARK: - Increase Contrast

    /// classicLight honors Increase Contrast like the opt-in schemes: text
    /// and meaningful outlines darken, while gradients, fills, and the
    /// decorative roles keep their exact original values.
    func testClassicLightHonorsIncreaseContrast() {
        ClassicChrome.apply(scheme: .classicLight)
        ClassicChromeEnvironment.increaseContrastOverride = false
        let normalSignature = paletteSignature()
        let normalGradients = gradientSignatures()

        func darker(_ name: String, _ resolve: () -> NSColor) {
            ClassicChromeEnvironment.increaseContrastOverride = false
            let normal = srgb(resolve())?.r
            ClassicChromeEnvironment.increaseContrastOverride = true
            let strong = srgb(resolve())?.r
            guard let normal, let strong else {
                XCTFail("classicLight \(name) did not convert to sRGB")
                return
            }
            XCTAssertLessThan(strong, normal,
                              "classicLight \(name) strengthens under Increase Contrast")
        }

        let p = ClassicChrome.scheme.palette
        for active in [true, false] {
            let state = active ? "active" : "inactive"
            darker("barBottomBorder \(state)") { p.barBottomBorder(active) }
            darker("barInnerLine \(state)") { p.barInnerLine(active) }
            darker("bezelBorder \(state)") { p.bezelBorder(active) }
            darker("wellBorder \(state)") { p.wellBorder(active) }
            darker("swatchFrame \(state)") { p.swatchFrame(active) }
            darker("segmentSeparator \(state)") { p.segmentSeparator(active) }
            darker("etchedSeparatorLeading \(state)") { p.etchedSeparatorLeading(active) }
            darker("glyphColor \(state)") { p.glyphColor(active) }
            darker("titleColor \(state)") { p.titleColor(active) }
            darker("arrowColor \(state)") { p.arrowColor(active) }
            darker("engravedText \(state)") { p.engravedText(0.22, active) }
        }
        darker("windowBorder") { p.windowBorder() }
        darker("tabSideHairline") { p.tabSideHairline() }
        darker("tabSeparator") { p.tabSeparator() }
        darker("ruleDark") { p.ruleDark() }
        darker("listWellRule") { p.listWellRule() }
        darker("secondaryText") { p.secondaryText() }

        ClassicChromeEnvironment.increaseContrastOverride = true
        XCTAssertNotEqual(paletteSignature(), normalSignature)
        XCTAssertEqual(gradientSignatures(), normalGradients,
                       "surfaces and gradients do not move")
        XCTAssertTrue(ClassicChrome.wellFill().isEqual(NSColor.white),
                      "wells stay white under Increase Contrast")
        XCTAssertTrue(ClassicChrome.pressedGlyph().isEqual(NSColor.black),
                      "the pressed glyph is already at full strength")

        ClassicChromeEnvironment.increaseContrastOverride = false
        XCTAssertEqual(paletteSignature(), normalSignature,
                       "the original colors return when the setting clears")
    }

    /// The opt-in schemes resolve stronger outlines and text while Increase
    /// Contrast is on: darker on light chrome, lighter on dark chrome.
    func testIncreaseContrastStrengthensOptInChrome() {
        for scheme in [ClassicChromeScheme.neutralGray, .dark] {
            ClassicChrome.apply(scheme: scheme)
            ClassicChromeEnvironment.increaseContrastOverride = false
            let border = srgb(ClassicChrome.bezelBorder(true))
            let glyph = srgb(ClassicChrome.glyphColor(true))
            let title = srgb(ClassicChrome.titleColor(true))
            ClassicChromeEnvironment.increaseContrastOverride = true
            let strongBorder = srgb(ClassicChrome.bezelBorder(true))
            let strongGlyph = srgb(ClassicChrome.glyphColor(true))
            let strongTitle = srgb(ClassicChrome.titleColor(true))
            guard let border, let glyph, let title,
                  let strongBorder, let strongGlyph, let strongTitle else {
                XCTFail("\(scheme): a chrome color did not convert to sRGB")
                continue
            }
            if scheme == .dark {
                XCTAssertGreaterThan(strongBorder.r, border.r, "\(scheme) border lightens")
                XCTAssertGreaterThan(strongGlyph.r, glyph.r, "\(scheme) glyph lightens")
                XCTAssertGreaterThan(strongTitle.r, title.r, "\(scheme) title lightens")
            } else {
                XCTAssertLessThan(strongBorder.r, border.r, "\(scheme) border darkens")
                XCTAssertLessThan(strongGlyph.r, glyph.r, "\(scheme) glyph darkens")
                XCTAssertLessThan(strongTitle.r, title.r, "\(scheme) title darkens")
            }
        }
    }

    // MARK: - Dynamic switch

    /// AppKit posts accessibility display changes on the workspace's own
    /// notification center — not `NotificationCenter.default`. Posting
    /// there repaints existing chrome, re-resolving colors cached in view
    /// state through `ClassicChromeSchemeAware`, while document content
    /// stays untouched.
    func testAccessibilityDisplayOptionsRepaintChromeFromWorkspaceCenter() throws {
        let window = ClassicWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = root
        let document = SchemeDocumentProbe(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let chrome = SchemeChromeProbe(frame: NSRect(x: 0, y: 200, width: 120, height: 40))
        root.addSubview(document)
        root.addSubview(chrome)
        window.orderFrontRegardless()
        settle()

        ClassicChromeEnvironment.increaseContrastOverride = false
        chrome.chromeSchemeDidChange()
        let normalGlyph = try XCTUnwrap(srgb(chrome.cachedGlyph))
        chrome.invalidations = 0
        chrome.schemeChanges = 0
        document.invalidations = 0

        ClassicChromeEnvironment.increaseContrastOverride = true
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared)
        settle()

        XCTAssertGreaterThan(chrome.invalidations, 0,
                             "the workspace accessibility post repaints chrome")
        XCTAssertGreaterThan(chrome.schemeChanges, 0,
                             "colors cached in view state re-resolve")
        let strongGlyph = try XCTUnwrap(srgb(chrome.cachedGlyph))
        XCTAssertLessThan(strongGlyph.r, normalGlyph.r,
                          "the cached glyph follows Increase Contrast")
        XCTAssertEqual(document.invalidations, 0,
                       "document views must not repaint")
    }

    /// A scheme change repaints `ClassicChromeDrawing` chrome — including
    /// app-owned views — adopts the scheme appearance on them, and leaves
    /// document views untouched.
    func testSchemeChangeRepaintsChromeAndUpdatesWindowAppearance() throws {
        let window = ClassicWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = root
        let document = SchemeDocumentProbe(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let chrome = SchemeChromeProbe(frame: NSRect(x: 0, y: 200, width: 120, height: 40))
        root.addSubview(document)
        root.addSubview(chrome)
        window.orderFrontRegardless()
        settle()

        chrome.invalidations = 0
        document.invalidations = 0
        let documentAppearance = document.effectiveAppearance.name
        ClassicChrome.apply(scheme: .dark)

        XCTAssertEqual(ClassicChrome.scheme, .dark)
        XCTAssertGreaterThan(chrome.invalidations, 0, "chrome must repaint")
        XCTAssertEqual(document.invalidations, 0, "document views must not repaint")
        XCTAssertEqual(chrome.effectiveAppearance.name, .darkAqua,
                       "chrome adopts the scheme appearance")
        XCTAssertEqual(document.effectiveAppearance.name, documentAppearance,
                       "document views keep the window appearance")

        chrome.invalidations = 0
        ClassicChrome.apply(scheme: .classicLight)
        XCTAssertGreaterThan(chrome.invalidations, 0)
        XCTAssertEqual(chrome.effectiveAppearance.name, .aqua,
                       "switching back restores the aqua chrome appearance")
    }

    /// The floating palette panel is a ClassicPaletteWindow: it adopts the
    /// scheme appearance on creation and follows a later scheme change.
    func testPalettePanelFollowsTheScheme() throws {
        let palette = Palette(
            definition: PaletteDefinition(
                kind: PaletteKind("tests.scheme.panel"), title: "Scheme Panel",
                contentSize: NSSize(width: 200, height: 120)),
            target: { NSObject() },
            makeContent: SchemeTestContent.init)
        defer { drainClose(palette) }

        palette.showPanel()
        settle()
        let panel = try XCTUnwrap(palette.hostingPanel)
        XCTAssertEqual(panel.appearance?.name, .aqua)
        let probe = try XCTUnwrap(firstDescendant(of: panel.contentView, as: SchemeChromeProbe.self))
        probe.invalidations = 0

        ClassicChrome.apply(scheme: .dark)
        XCTAssertEqual(panel.appearance?.name, .darkAqua,
                       "an open palette panel follows the scheme")
        XCTAssertGreaterThan(probe.invalidations, 0, "palette chrome repaints")
        XCTAssertEqual(probe.effectiveAppearance.name, .darkAqua)

        ClassicChrome.apply(scheme: .classicLight)
        XCTAssertEqual(panel.appearance?.name, .aqua)
    }

    /// The attached palette popover adopts the scheme appearance both when
    /// presented and when the scheme changes while it is open.
    func testPalettePopoverFollowsTheScheme() throws {
        let (window, anchor) = try makeAnchorWindow()
        defer { window.close() }
        let palette = Palette(
            definition: PaletteDefinition(
                kind: PaletteKind("tests.scheme.popover"), title: "Scheme Popover",
                contentSize: NSSize(width: 200, height: 120)),
            target: { NSObject() },
            makeContent: SchemeTestContent.init)
        defer { drainClose(palette) }

        palette.present(from: anchor)
        let popover = try XCTUnwrap(palette.presentedPopover)
        XCTAssertEqual(popover.appearance?.name, .aqua)
        let contentView = try XCTUnwrap(popover.contentViewController?.view)
        let probe = try XCTUnwrap(firstDescendant(of: contentView, as: SchemeChromeProbe.self))
        probe.invalidations = 0

        ClassicChrome.apply(scheme: .dark)
        XCTAssertEqual(popover.appearance?.name, .darkAqua,
                       "an open popover follows the scheme")
        XCTAssertGreaterThan(probe.invalidations, 0)
        XCTAssertEqual(probe.effectiveAppearance.name, .darkAqua)

        ClassicChrome.apply(scheme: .neutralGray)
        XCTAssertEqual(popover.appearance?.name, .aqua,
                       "neutral gray keeps the aqua appearance")
    }

    /// The try-on picker popover follows the scheme the same way.
    func testTryOnPopoverFollowsTheScheme() throws {
        let (window, anchor) = try makeAnchorWindow()
        defer { window.close() }
        let picker = TryOnPopover(hint: "Preview")
        picker.present(from: anchor, palette: nil,
                       items: [PickerItem(id: "one", title: "One")], currentID: "one",
                       specimenFont: { _ in .systemFont(ofSize: 13) },
                       onPreview: { _ in }, onDetach: {}, onFinish: { _ in })
        let popover = try XCTUnwrap(picker.presentedPopover)
        XCTAssertEqual(popover.appearance?.name, .aqua)

        ClassicChrome.apply(scheme: .dark)
        XCTAssertEqual(popover.appearance?.name, .darkAqua)
        let list = try XCTUnwrap(popover.contentViewController?.view.subviews
            .compactMap { $0 as? PickerListView }.first)
        XCTAssertEqual(list.effectiveAppearance.name, .darkAqua,
                       "the picker's well adopts the scheme appearance")

        popover.close()
        settle()
    }

    /// View-state chrome colors — the picker's well fill and hint — refresh
    /// through `ClassicChromeSchemeAware`, and dimmed rows re-resolve.
    func testPickerListWellAndHintFollowTheScheme() throws {
        let window = ClassicWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let picker = PickerListView(hint: "Pick one")
        picker.setItems([
            PickerItem(id: "a", title: "Able"),
            PickerItem(id: "b", title: "Baker", dimmed: true),
        ])
        // A popover would give the picker the scheme appearance; pin aqua
        // here so the light baseline does not depend on the host's setting.
        picker.appearance = NSAppearance(named: .aqua)
        window.contentView = picker
        window.orderFrontRegardless()
        settle()

        let scroll = try XCTUnwrap(picker.subviews.compactMap { $0 as? NSScrollView }.first)
        let hint = try XCTUnwrap(picker.subviews.compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "Pick one" })
        XCTAssertTrue(hint.textColor?.isEqual(ClassicChrome.secondaryText()) ?? false)

        // The well region is painted by the table's appearance-driven
        // background over the scroll well: sample its pixels below the rows.
        let wellRect = scroll.convert(scroll.bounds, to: picker)
        let sampleRect = NSRect(x: wellRect.minX, y: wellRect.minY,
                                width: wellRect.width, height: wellRect.height * 0.4)
        let lightWell = try XCTUnwrap(patchLuminance(of: picker, in: sampleRect))
        XCTAssertGreaterThan(lightWell, 0.7, "the light well is bright")

        ClassicChrome.apply(scheme: .dark)
        picker.displayIfNeeded()
        XCTAssertEqual(picker.effectiveAppearance.name, .darkAqua,
                       "the picker adopts the scheme appearance")
        XCTAssertTrue(hint.textColor?.isEqual(ClassicChrome.secondaryText()) ?? false,
                      "the hint color follows the scheme")
        let darkWell = try XCTUnwrap(patchLuminance(of: picker, in: sampleRect))
        XCTAssertLessThan(darkWell, 0.5, "the dark well is not bright")
        XCTAssertLessThan(darkWell, lightWell - 0.2,
                          "the well region follows the scheme")
    }

    /// The palette button bar bakes the glyph tint into its images, so a
    /// scheme change must re-tint them from the original templates.
    func testPaletteButtonBarRetintsGlyphsOnSchemeChange() throws {
        let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        XCTAssertNotNil(image)
        image?.isTemplate = true
        let bar = ClassicPaletteButtonBar(items: [
            .init(id: "add", title: "Add", image: image ?? NSImage(), action: {})
        ])
        let window = ClassicWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 60))
        bar.frame = NSRect(x: 4, y: 4, width: 100, height: ClassicPaletteButtonBar.height)
        window.contentView?.addSubview(bar)
        window.orderFrontRegardless()
        settle()

        let button = try XCTUnwrap(bar.button(for: "add"))
        let lightGlyph = try XCTUnwrap(imageLuminance(button.image))

        ClassicChrome.apply(scheme: .dark)
        let darkGlyph = try XCTUnwrap(imageLuminance(button.image))
        XCTAssertGreaterThan(darkGlyph, lightGlyph,
                             "glyphs brighten on dark chrome")
    }

    // MARK: - Helpers

    private func settle(_ seconds: TimeInterval = 0.2) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func makeAnchorWindow() throws -> (window: NSWindow, anchor: NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 80, height: 24))
        try XCTUnwrap(window.contentView).addSubview(anchor)
        window.orderFrontRegardless()
        return (window, anchor)
    }

    /// A popover closes asynchronously, and a palette is app global, so a
    /// leaked one would defer the next presentation instead of failing here.
    private func drainClose(_ palette: Palette,
                            file: StaticString = #filePath, line: UInt = #line) {
        palette.close()
        let deadline = Date(timeIntervalSinceNow: 1)
        while palette.isPresented || palette.presentedPopover != nil, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertFalse(palette.isPresented, "The palette did not close.", file: file, line: line)
        XCTAssertNil(palette.presentedPopover, "The popover did not close.", file: file, line: line)
    }

    private func firstDescendant<View: NSView>(of view: NSView?, as type: View.Type) -> View? {
        guard let view else { return nil }
        if let match = view as? View { return match }
        for subview in view.subviews {
            if let match = firstDescendant(of: subview, as: type) { return match }
        }
        return nil
    }

    // MARK: - Color math

    private struct RGB {
        var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    }

    private func srgb(_ color: NSColor) -> RGB? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        return RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
    }

    private func colorSignature(_ color: NSColor) -> String {
        guard let rgb = srgb(color) else { return "?" }
        return String(format: "%.4f,%.4f,%.4f,%.4f", rgb.r, rgb.g, rgb.b, rgb.a)
    }

    private func paletteColors() -> [NSColor] {
        let p = ClassicChrome.scheme.palette
        var colors: [NSColor] = [p.barTopHighlight()]
        for active in [true, false] {
            colors += [
                p.barBottomBorder(active), p.barInnerLine(active), p.bezelBorder(active),
                p.wellBorder(active), p.swatchFrame(active), p.segmentSeparator(active),
                p.etchedSeparatorLeading(active), p.glyphColor(active), p.titleColor(active),
                p.arrowColor(active), p.engravedText(0.22, active), p.engravedText(0.38, active),
                p.engravedShadow(active), p.innerHintHighlight(active), p.innerHintShadow(active),
            ]
        }
        colors += [
            p.windowBorder(), p.tabSideHairline(), p.tabSeparator(), p.etchedSeparatorTrailing(),
            p.ruleDark(), p.ruleLight(), p.listWellRule(), p.secondaryText(), p.pressedGlyph(),
            p.wellFill(), p.fieldInsetShadow(), p.wellInsetShadow(), p.swatchInnerRule(),
            p.pressedOverlay(), p.disabledSwatchBlend(),
        ]
        return colors
    }

    private func paletteSignature() -> String {
        paletteColors().map(colorSignature).joined(separator: "|")
            + "##" + gradientSignatures().joined(separator: "|")
    }

    private func gradientSignatures() -> [String] {
        let p = ClassicChrome.scheme.palette
        var gradients = [
            p.toolbarGradient(true), p.statusBarGradient(true), p.panelGradient(true),
            p.paletteTitleBarGradient(), p.selectedTabGradient(),
        ]
        for active in [true, false] {
            for state in [ClassicChrome.BezelState.normal, .on, .pressed] {
                gradients.append(p.bezelGradient(state, active))
            }
        }
        return gradients.map { gradientLuminances($0).map { String(format: "%.3f", $0) }.joined(separator: ",") }
    }

    /// WCAG-style relative luminance of an sRGB color.
    private func colorLuminance(_ color: NSColor) -> CGFloat? {
        guard let rgb = srgb(color) else { return nil }
        func linear(_ v: CGFloat) -> CGFloat {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }

    private func contrastRatio(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Luminance down the middle of a vertical gradient, top to bottom.
    private func gradientLuminances(_ gradient: NSGradient, samples: Int = 12) -> [CGFloat] {
        let width = 8
        let height = samples * 4
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        var result: [CGFloat] = []
        for i in 0..<samples {
            let y = height - 1 - (i * height / samples) - height / (samples * 2)
            guard let color = rep.colorAt(x: width / 2, y: y),
                  let luminance = colorLuminance(color) else { continue }
            result.append(luminance)
        }
        return result
    }

    /// RGBA bytes of a gradient raster, for pixel-exact parity checks.
    private func gradientPixels(_ gradient: NSGradient) -> [UInt8] {
        let width = 16
        let height = 64
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let data = rep.bitmapData
        else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        return Array(UnsafeBufferPointer(start: data, count: width * height * 4))
    }

    /// Mean luminance of a patch of `view` rendered fresh — what the chrome
    /// actually paints, independent of how AppKit stores the color.
    private func patchLuminance(of view: NSView, in rect: NSRect) -> CGFloat? {
        let patch = rect.intersection(view.bounds)
        guard patch.width >= 8, patch.height >= 8 else { return nil }
        let width = max(1, Int(patch.width))
        let height = max(1, Int(patch.height))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let data = rep.bitmapData
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.cacheDisplay(in: patch, to: rep)
        NSGraphicsContext.restoreGraphicsState()
        var total: CGFloat = 0
        var count = 0
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let offset = y * rep.bytesPerRow + x * 4
                let r = CGFloat(data[offset]) / 255
                let g = CGFloat(data[offset + 1]) / 255
                let b = CGFloat(data[offset + 2]) / 255
                total += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }
        return count > 0 ? total / CGFloat(count) : nil
    }

    /// Mean luminance of an image's opaque pixels — the baked glyph tint.
    private func imageLuminance(_ image: NSImage?) -> CGFloat? {
        guard let image else { return nil }
        let size = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let data = rep.bitmapData
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        var total: CGFloat = 0
        var weight: CGFloat = 0
        for i in stride(from: 0, to: size * size * 4, by: 4) {
            let alpha = CGFloat(data[i + 3]) / 255
            guard alpha > 0.05 else { continue }
            let r = CGFloat(data[i]) / 255
            let g = CGFloat(data[i + 1]) / 255
            let b = CGFloat(data[i + 2]) / 255
            total += (0.2126 * r + 0.7152 * g + 0.0722 * b) * alpha
            weight += alpha
        }
        return weight > 0 ? total / weight : nil
    }
}

/// A chrome view that counts its invalidations, like the activation tests',
/// and bakes one resolved color into view state — re-resolved through
/// `ClassicChromeSchemeAware`, like `StatusBarView`'s fields do.
@MainActor
private final class SchemeChromeProbe: NSView, ClassicChromeDrawing, ClassicChromeSchemeAware {
    var invalidations = 0
    var schemeChanges = 0
    var cachedGlyph = ClassicChrome.glyphColor(true)

    /// The protocol requirement is nonisolated; the refresh walk only ever
    /// runs it on the main thread.
    nonisolated func chromeSchemeDidChange() {
        MainActor.assumeIsolated {
            schemeChanges += 1
            cachedGlyph = ClassicChrome.glyphColor(true)
        }
    }

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if newValue { invalidations += 1 }
            super.needsDisplay = newValue
        }
    }
}

/// A plain view standing in for document content: it must never be
/// invalidated or re-appearanced by a scheme change.
@MainActor
private final class SchemeDocumentProbe: NSView {
    var invalidations = 0
    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if newValue { invalidations += 1 }
            super.needsDisplay = newValue
        }
    }
}

/// Minimal palette content carrying one chrome probe, so tests can watch a
/// scheme change reach inside a popover or panel.
@MainActor
private final class SchemeTestContent: NSViewController, PaletteContent {
    typealias Target = NSObject

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let probe = SchemeChromeProbe(frame: NSRect(x: 8, y: 8, width: 80, height: 24))
        root.addSubview(probe)
        view = root
    }

    func retarget(to target: NSObject?) {}
}
