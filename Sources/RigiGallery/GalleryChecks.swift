import AppKit
import RigiUI

/// Command-line modes: a normal run keeps the window open; auxiliary modes
/// exercise the real views and exit, so CI can run them headless.
enum GalleryMode {
    case normal, smokeTest, screenshot(String)

    static var current: GalleryMode {
        let arguments = CommandLine.arguments
        if arguments.contains("--smoke-test") { return .smokeTest }
        if let index = arguments.firstIndex(of: "--screenshot"),
           arguments.indices.contains(index + 1) {
            return .screenshot(arguments[index + 1])
        }
        return .normal
    }

    /// Auxiliary modes run as accessories: no Dock tile, no activation chase.
    static var auxiliaryRun: Bool {
        let arguments = CommandLine.arguments
        return arguments.contains("--smoke-test") || arguments.contains("--screenshot")
    }
}

/// Opens the gallery plus a representative palette inside bounded runloop
/// turns and asserts on the actual views. Prints SMOKE OK / SMOKE FAIL <name>.
enum GallerySmokeTest {

    @MainActor
    static func run(_ controller: GalleryController) -> Int32 {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if !condition() {
                failures.append(name)
                print("SMOKE FAIL \(name)")
            }
        }
        let settle = { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)) }
        let window = controller.window

        settle()
        window.layoutIfNeeded()
        check(window.isVisible, "window ordered front")
        check(window.contentView?.subviews.contains { $0 is ClassicPanelView } == true,
              "panel surface")
        check((window.contentView?.bounds.height ?? 0) >= window.contentMinSize.height,
              "gallery retains its minimum content height")
        check(controller.toolbarStack.arrangedSubviews.count == 7, "toolbar controls")
        check(controller.statusBar.superview != nil, "status bar")
        check(controller.specimenLabel.attributedStringValue.length > 0, "specimen rendered")
        check(controller.chooser.title == controller.model.family, "chooser shows family")

        // Live preview then Esc-style cancel through the real session path:
        // previews apply without registering; cancel restores, no undo left.
        let original = controller.model.family
        controller.model.beginTryOn()
        controller.model.previewFamily("Georgia")
        check(controller.model.family == "Georgia", "live preview applies")
        controller.model.endTryOn(.cancel)
        check(controller.model.family == original, "cancel restores")
        check(!controller.model.undo.canUndo, "cancel leaves no undo")

        // A committed edit registers exactly one step; undo restores the value.
        controller.model.edit { $0.family = "Menlo" }
        check(controller.model.undo.canUndo, "commit registers undo")
        controller.model.undo.undo()
        check(controller.model.family == original, "undo restores")

        // The attached picker presents for real.
        controller.presentTryOnPicker()
        check(controller.tryOnPopover.isActive, "try-on popover active")

        // The tear-off contract: configure the panel and commit the detach,
        // which is the same pair of calls NSPopover makes on a real drag.
        let detachWindow = controller.tearOffPalette.windowForDetach(selecting: controller.model.family)
        controller.tearOffPalette.didDetach()
        check(detachWindow is ClassicPaletteWindow, "detach window type")
        check(controller.tearOffPalette.isOpen, "palette marked open")
        settle()
        check(controller.chooser.representsOpenPalette, "chooser engaged elsewhere")
        controller.tearOffPalette.close()
        check(!controller.chooser.representsOpenPalette, "palette close restores")

        // The generic PaletteCenter palette floats for real.
        let center = PaletteCenter.shared
        center.resetLayout()
        controller.inspectorPalette.showPanel()
        settle()
        check(controller.inspectorPalette.isPresented, "inspector presented")
        check(controller.inspectorPalette.isFloating, "inspector floating")

        // A second palette of the same default group joins it as a tab.
        controller.swatchesPalette.showPanel()
        settle()
        let paletteTitles: Set<String> = ["Inspector", "Swatches"]
        let shownPanels = {
            NSApp.windows.filter { $0 is ClassicPaletteWindow && $0.isVisible && paletteTitles.contains($0.title) }
        }
        check(center.groupMembers(of: GalleryPaletteKind.inspector)
                == [GalleryPaletteKind.inspector, GalleryPaletteKind.swatches], "default group")
        check(controller.swatchesPalette.isFloating, "swatches floating")
        check(shownPanels().count == 1, "grouped palettes share one panel")

        // The tool palette: a ClassicToolGrid and a ClassicColorPair that
        // shows the specimen's colors and reports swaps to the model.
        controller.toolsPalette.showPanel()
        settle()
        check(controller.toolsPalette.isFloating, "tools floating")
        let toolsView = NSApp.windows.first { $0.title == "Tools" && $0.isVisible }?.contentView
        let grid = toolsView.flatMap { firstDescendant(of: $0, as: ClassicToolGrid.self) }
        let pair = toolsView.flatMap { firstDescendant(of: $0, as: ClassicColorPair.self) }
        check(grid?.slots.count == ToolsContent.slots.count, "tool grid slots")
        check(grid?.selectedToolID == "brush", "tool grid selection")
        check(pair?.foreground == controller.model.color, "color pair shows the ink")
        let ink = controller.model.color
        pair?.onSwap?()
        settle()
        check(controller.model.specimen.highlight == ink && pair?.background == ink,
              "color pair swap reaches the model and comes back")
        controller.model.undo.undo()
        settle()

        // The inspector's own menu shows as a triangle in its title bar.
        let inspectorPanel = NSApp.windows.first {
            $0 is ClassicPaletteWindow && $0.isVisible && ($0.title == "Inspector" || $0.title == "Swatches")
        }
        controller.inspectorPalette.bringToFront()
        settle()
        let menuButton = (inspectorPanel?.contentView?.accessibilityChildren() ?? [])
            .compactMap { $0 as? NSAccessibilityElement }
            .first { $0.accessibilityRole() == .menuButton }
        check(menuButton?.accessibilityLabel() == "Inspector Menu", "palette menu triangle")

        // A workspace brings back the palettes it saved.
        let workspace = "Smoke \(ProcessInfo.processInfo.processIdentifier)"
        center.saveWorkspace(named: workspace)
        center.closeAll()
        settle()
        check(!controller.inspectorPalette.isPresented, "palettes closed")
        check(center.applyWorkspace(named: workspace), "workspace applied")
        settle()
        check(controller.inspectorPalette.isFloating && controller.swatchesPalette.isFloating,
              "workspace reopens its palettes")
        center.deleteWorkspace(named: workspace)
        check(!center.workspaceNames.contains(workspace), "workspace deleted")

        // The status bar's editable zoom, accessory and progress.
        let statusBar = controller.statusBar
        statusBar.onZoomTo?(250)
        check(controller.model.zoomPercent == 250, "status bar zoom typed")
        check(controller.familyLabel.superview != nil, "status bar accessory")
        controller.model.edit { $0.family = "Georgia" }
        check(controller.familyLabel.stringValue == "Georgia", "status bar accessory follows the family")
        controller.model.undo.undo()
        statusBar.showProgress(fraction: 0.5)
        check(statusBar.isShowingProgress, "status bar progress")
        statusBar.hideProgress()
        check(!statusBar.isShowingProgress, "status bar progress hidden")

        // The inspector's value slider follows the zoom; the swatches' button
        // bar adds an ink.
        controller.inspectorPalette.bringToFront()
        settle()
        let inspectorView = NSApp.windows.first { $0 is ClassicPaletteWindow && $0.isVisible
            && $0.title == "Inspector" }?.contentView
        let valueSlider = inspectorView.flatMap { firstDescendant(of: $0, as: ClassicValueSlider.self) }
        check(valueSlider?.value == 250, "value slider follows the model")
        controller.swatchesPalette.bringToFront()
        settle()
        let swatchesView = NSApp.windows.first { $0 is ClassicPaletteWindow && $0.isVisible
            && $0.title == "Swatches" }?.contentView
        let buttonBar = swatchesView.flatMap { firstDescendant(of: $0, as: ClassicPaletteButtonBar.self) }
        check(buttonBar?.isEnabled(item: "add") == true, "button bar add enabled")
        check(buttonBar?.isEnabled(item: "remove") == false, "button bar remove disabled")
        controller.model.zoomPercent = 100

        // Hiding keeps palettes open; restoring brings their panel back.
        center.hideAll()
        check(center.isHidingPalettes, "palettes hidden")
        check(shownPanels().isEmpty, "no palette panel on screen")
        check(controller.inspectorPalette.isPresented, "hidden palette stays presented")
        center.restoreAll()
        check(!center.isHidingPalettes && shownPanels().count == 1, "palettes restored")
        center.closeAll()

        print(failures.isEmpty ? "SMOKE OK" : "SMOKE FAILED \(failures.count)")
        return failures.isEmpty ? 0 : 1
    }
}

/// Renders the gallery's content view to a PNG for the CI artifact.
enum GalleryScreenshot {

    @MainActor
    static func write(_ controller: GalleryController, to path: String) -> Int32 {
        func fail(_ message: String) -> Int32 {
            FileHandle.standardError.write(Data("screenshot: \(message)\n".utf8))
            return 1
        }
        let window = controller.window
        window.orderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        window.layoutIfNeeded()
        window.displayIfNeeded()
        guard let view = window.contentView else { return fail("no content view") }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        let rep = view.bitmapImageRepForCachingDisplay(in: bounds)
            ?? NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)
        guard let bitmap = rep else { return fail("could not allocate bitmap") }
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return fail("PNG encoding failed")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            return fail(error.localizedDescription)
        }
        print("screenshot: wrote \(path) (\(bitmap.pixelsWide)×\(bitmap.pixelsHigh))")
        return 0
    }
}

@MainActor
private func firstDescendant<View: NSView>(of view: NSView, as type: View.Type) -> View? {
    if let match = view as? View { return match }
    for subview in view.subviews {
        if let match = firstDescendant(of: subview, as: type) { return match }
    }
    return nil
}
