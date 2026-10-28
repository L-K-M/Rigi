import AppKit
import RigiUI

/// RigiGallery — one window exercising the RigiUI surface end to end.
///   swift run RigiGallery                       interactive window
///   swift run RigiGallery --smoke-test          build, exercise, assert, exit
///   swift run RigiGallery --screenshot out.png  render the content to PNG
@main
@MainActor
enum GalleryApplication {

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(GalleryMode.auxiliaryRun ? .accessory : .regular)
        app.mainMenu = makeMainMenu()

        let controller = GalleryController()
        controller.window.orderFront(nil)

        switch GalleryMode.current {
        case .normal:            app.run()
        case .smokeTest:         exit(GallerySmokeTest.run(controller))
        case .screenshot(let p): exit(GalleryScreenshot.write(controller, to: p))
        }
    }

    /// Minimal menu bar: Quit, plus Undo/Redo so ⌘Z reaches the window's undo
    /// manager through the responder chain.
    private static func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit RigiGallery",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector("redo:"), keyEquivalent: "Z")
        editItem.submenu = editMenu
        return menu
    }
}
