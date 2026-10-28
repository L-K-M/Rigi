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
        check(window.contentView is ClassicPanelView, "panel surface")
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
        controller.inspectorPalette.showPanel()
        settle()
        check(controller.inspectorPalette.isPresented, "inspector presented")
        check(controller.inspectorPalette.isFloating, "inspector floating")

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
