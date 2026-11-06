import AppKit
import XCTest

@testable import RigiUI

@MainActor
final class PaletteMenuWorkspaceTests: XCTestCase {
  private var palettes: [Palette] = []

  override func tearDown() {
    for palette in palettes {
      palette.close()
    }
    palettes = []
    super.tearDown()
  }

  // MARK: - Palette menus

  func testATriangleOffersTheShownPalettesMenuAndOnlyThat() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let a = makePalette("a", title: "Alpha", dock: dock, menu: ["New", "Delete"])
    let b = makePalette("b", title: "Beta", dock: dock, menu: nil)
    a.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    let chrome = panel.chrome

    XCTAssertTrue(chrome.showsMenuButton)
    XCTAssertEqual(menuButtonElement(in: chrome)?.accessibilityLabel(), "Alpha Menu")

    b.showPanel()
    drainRunLoop()
    b.bringToFront()
    XCTAssertFalse(chrome.showsMenuButton, "Beta has no menu")
    XCTAssertNil(menuButtonElement(in: chrome))

    a.bringToFront()
    XCTAssertTrue(chrome.showsMenuButton)
    // The tabs end before the triangle rather than under it.
    let lastTab = try XCTUnwrap(chrome.tabRects.last)
    XCTAssertLessThanOrEqual(lastTab.maxX, chrome.menuButtonRect.minX)
  }

  func testTheTitleBarMenuLeadsWithThePalettesOwnCommands() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let a = makePalette("a", title: "Alpha", dock: dock, menu: ["New", "Delete"])
    a.showPanel()
    let group = try XCTUnwrap(dock.groupID(of: a))

    // Asked twice, as two right-clicks would: each menu gets its own copy.
    _ = dock.menu(forGroup: group, tab: nil)
    let menu = try XCTUnwrap(dock.menu(forGroup: group, tab: nil))

    XCTAssertEqual(menu.items.first?.title, "Alpha")
    XCTAssertEqual(menu.items.first?.submenu?.items.map(\.title), ["New", "Delete"])
    XCTAssertTrue(menu.items.contains { $0.title == "Close Alpha" })
  }

  // MARK: - Workspaces

  func testAWorkspaceBringsBackItsGroupsPlacesAndOpenPalettes() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let a = makePalette("a", title: "Alpha", dock: dock)
    let b = makePalette("b", title: "Beta", dock: dock)
    let c = makePalette("c", title: "Gamma", dock: dock)
    a.showPanel()
    b.showPanel()
    let shared = try XCTUnwrap(a.hostingPanel)
    let group = try XCTUnwrap(dock.groupID(of: a))
    dock.move(group, to: NSRect(origin: NSPoint(x: 240, y: 300), size: shared.frame.size))
    let savedFrame = shared.frame

    dock.saveWorkspace(named: "  Painting ")

    // Rearrange: Beta on its own, Alpha closed, Gamma open.
    dock.separate(b)
    a.close()
    c.showPanel()
    XCTAssertEqual(dock.members(of: kind("b")), [kind("b")])

    XCTAssertTrue(dock.applyWorkspace(named: "Painting"))

    XCTAssertTrue(a.isFloating)
    XCTAssertTrue(b.isFloating)
    XCTAssertFalse(c.isPresented, "Gamma was not open in the workspace")
    XCTAssertEqual(dock.members(of: kind("a")), [kind("a"), kind("b")])
    let restored = try XCTUnwrap(a.hostingPanel)
    XCTAssertIdentical(b.hostingPanel, restored)
    XCTAssertEqual(restored.frame, savedFrame)
    XCTAssertFalse(dock.applyWorkspace(named: "Unknown"))
  }

  func testWorkspacesAreListedSortedPersistAndCanBeDeleted() {
    let store = PaletteLayoutStore.memory()
    do {
      let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
      let a = makePalette("a", title: "Alpha", dock: dock)
      a.showPanel()
      dock.saveWorkspace(named: "Photo 10")
      dock.saveWorkspace(named: "photo 9")
      dock.saveWorkspace(named: "Ink")
      a.close()
    }

    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    XCTAssertEqual(dock.workspaceNames, ["Ink", "photo 9", "Photo 10"])

    dock.deleteWorkspace(named: "Ink")
    XCTAssertEqual(dock.workspaceNames, ["photo 9", "Photo 10"])
    XCTAssertEqual(PaletteDock(store: store, legacyFrame: { _ in nil }).workspaceNames,
                   ["photo 9", "Photo 10"])
  }

  func testASavedWorkspaceIsCheckedLikeTheLayout() throws {
    let suite = "tests.palette.workspaces.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PaletteLayoutStore.userDefaults(defaults)

    var group = PaletteLayout.Group(id: "one", kinds: ["a", "a", "b"])
    group.dockedBelow = "missing"
    var future = PaletteLayout(groups: [group])
    future.version = PaletteLayout.currentVersion + 1
    store.saveWorkspaces([
      "Good": PaletteWorkspace(layout: PaletteLayout(groups: [group]), openKinds: ["b", "x", "b"]),
      "Future": PaletteWorkspace(layout: future, openKinds: []),
      "": PaletteWorkspace(layout: PaletteLayout(), openKinds: []),
    ])

    let loaded = store.loadWorkspaces()

    XCTAssertEqual(Array(loaded.keys), ["Good"])
    XCTAssertEqual(loaded["Good"]?.layout.groups.first?.kinds, ["a", "b"])
    XCTAssertNil(loaded["Good"]?.layout.groups.first?.dockedBelow)
    XCTAssertEqual(loaded["Good"]?.openKinds, ["b"])

    defaults.set(Data("garbage".utf8), forKey: PaletteLayoutStore.workspacesKey)
    XCTAssertTrue(store.loadWorkspaces().isEmpty)
  }

  // MARK: - Helpers

  private func kind(_ identifier: String) -> PaletteKind {
    PaletteKind(identifier)
  }

  private func makePalette(
    _ identifier: String,
    title: String,
    dock: PaletteDock,
    menu: [String]? = nil
  ) -> Palette {
    _ = NSApplication.shared
    let palette = Palette(
      definition: PaletteDefinition(
        kind: kind(identifier), title: title, contentSize: NSSize(width: 220, height: 160)),
      target: { NSObject() },
      makeContent: { MenuTestContent(menuTitles: menu) },
      dock: dock
    )
    palettes.append(palette)
    return palette
  }

  private func menuButtonElement(in chrome: PaletteChromeView) -> NSAccessibilityElement? {
    (chrome.accessibilityChildren() ?? [])
      .compactMap { $0 as? NSAccessibilityElement }
      .first { $0.accessibilityRole() == .menuButton }
  }

  private func drainRunLoop() {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
  }
}

@MainActor
private final class MenuTestContent: NSViewController, PaletteContent {
  typealias Target = NSObject

  private let menuTitles: [String]?
  /// One menu kept for the palette's life, as a content would.
  private lazy var ownMenu: NSMenu? = menuTitles.map { titles in
    let menu = NSMenu()
    for title in titles {
      menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
    }
    return menu
  }

  init(menuTitles: [String]?) {
    self.menuTitles = menuTitles
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func loadView() {
    view = NSView()
  }

  var paletteMenu: NSMenu? { ownMenu }

  func retarget(to target: NSObject?) {}
}
