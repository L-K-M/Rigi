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

  /// The view half of the triangle's hit area: no band, band cursor or tab
  /// lies over it. The window half, AppKit's own resize zones, is kept off
  /// by the style mask (PalettePanelTests).
  func testEveryPointOfTheTriangleTakesTheClickRatherThanTheResizeBand() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let a = makePalette("a", title: "Alpha", dock: dock, menu: ["New", "Delete"],
                        sizing: .resizable(minimumContentSize: NSSize(width: 120, height: 80)))
    a.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    let chrome = panel.chrome
    let content = try XCTUnwrap(panel.contentView)
    XCTAssertTrue(chrome.showsMenuButton)

    let rect = chrome.menuButtonRect
    // Nor does a resize cursor show anywhere over it: pointer and press
    // agree on what the triangle's points do.
    let border = try XCTUnwrap(chrome.subviews.first { $0 is PaletteResizeBorderView })
    let triangleInBorder = border.convert(rect, from: chrome)
    for band in PaletteResizeBorderView.cursorBands(in: border.bounds) {
      XCTAssertFalse(band.rect.intersects(triangleInBorder),
                     "a resize cursor band \(band.rect) reaches the triangle \(triangleInBorder)")
    }

    var x = rect.minX + 0.5
    while x < rect.maxX {
      let point = chrome.convert(NSPoint(x: x, y: rect.midY), to: nil)
      let hit = content.hitTest(point)
      // The chrome draws the triangle and takes its presses itself; the
      // band overlay and the tabs are views of their own.
      XCTAssertTrue(
        hit === chrome,
        "a press at \(x - rect.minX) pt into the triangle's \(rect.width) pt goes to \(String(describing: hit))")
      x += 1
    }
  }

  /// The triangle's hit area gives way to a resize band only where there
  /// is one: a fixed palette keeps the whole 16 pt, and the triangle is
  /// drawn in the same place either way.
  func testOnlyAResizablePaletteNarrowsTheTriangleForItsBand() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let fixed = makePalette("fixed", title: "Fixed", dock: dock, menu: ["New"])
    let resizable = makePalette("sized", title: "Sized", dock: dock, menu: ["New"],
                                sizing: .resizable(minimumContentSize: NSSize(width: 120, height: 80)))
    fixed.showPanel()
    resizable.showPanel()
    let fixedChrome = try XCTUnwrap(fixed.hostingPanel).chrome
    let sizedChrome = try XCTUnwrap(resizable.hostingPanel).chrome

    XCTAssertEqual(fixedChrome.menuButtonRect.width, 16)
    XCTAssertEqual(fixedChrome.menuButtonRect.maxX, fixedChrome.titleBarRect.maxX - 2)
    XCTAssertEqual(sizedChrome.menuButtonRect.maxX,
                   sizedChrome.titleBarRect.maxX - PaletteResizeBorderView.bandWidth)
    XCTAssertEqual(fixedChrome.titleBarRect.maxX - fixedChrome.menuGlyphCenterX,
                   sizedChrome.titleBarRect.maxX - sizedChrome.menuGlyphCenterX)
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

  func testOwnPaletteMenusFollowTheAppliedChromeScheme() throws {
    let previous = ClassicChrome.scheme
    defer { ClassicChrome.apply(scheme: previous) }
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let palette = makePalette("scheme", title: "Scheme", dock: dock, menu: ["New"])
    palette.showPanel()
    let group = try XCTUnwrap(dock.groupID(of: palette))
    ClassicChrome.apply(scheme: .dark)
    let context = try XCTUnwrap(dock.menu(forGroup: group, tab: nil))
    XCTAssertEqual(context.appearance?.name, .darkAqua)
    XCTAssertEqual(context.items.first?.submenu?.appearance?.name, .darkAqua)
  }

  func testTheTriangleFollowsWhetherTheContentHasAMenuForItsTarget() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    var target: NSObject? = NSObject()
    let palette = Palette(
      definition: PaletteDefinition(
        kind: kind("t"), title: "Targeted", contentSize: NSSize(width: 220, height: 160)),
      target: { target },
      makeContent: { TargetMenuContent() },
      dock: dock
    )
    palettes.append(palette)
    palette.showPanel()
    let chrome = try XCTUnwrap(palette.hostingPanel).chrome
    XCTAssertTrue(chrome.showsMenuButton)

    // The front document closes: the content has nothing to offer.
    target = nil
    palette.retarget()
    XCTAssertFalse(chrome.showsMenuButton)

    target = NSObject()
    palette.retarget()
    XCTAssertTrue(chrome.showsMenuButton)
  }

  func testAnEmptyMenuShowsNoTriangle() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let a = makePalette("a", title: "Alpha", dock: dock, menu: [])
    a.showPanel()

    XCTAssertFalse(try XCTUnwrap(a.hostingPanel).chrome.showsMenuButton)
  }

  func testTheTitleBarMenusCommandsReachTheDock() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let a = makePalette("a", title: "Alpha", dock: dock)
    let b = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let group = try XCTUnwrap(dock.groupID(of: a))

    // Choosing an item sends its action the way AppKit does.
    func choose(_ title: String, tab: Int?) throws {
      let menu = try XCTUnwrap(dock.menu(forGroup: group, tab: tab))
      let item = try XCTUnwrap(menu.items.first { $0.title == title }, title)
      let action = try XCTUnwrap(item.action)
      XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item), title)
    }

    try choose("Collapse", tab: nil)
    XCTAssertTrue(dock.isCollapsed(group))
    try choose("Expand", tab: nil)
    XCTAssertFalse(dock.isCollapsed(group))

    try choose("Move Beta to a New Panel", tab: 1)
    XCTAssertEqual(dock.members(of: kind("b")), [kind("b")])

    try choose("Close Alpha", tab: nil)
    XCTAssertFalse(a.isPresented)
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
    menu: [String]? = nil,
    sizing: PaletteSizing = .fixed
  ) -> Palette {
    _ = NSApplication.shared
    let palette = Palette(
      definition: PaletteDefinition(
        kind: kind(identifier), title: title, contentSize: NSSize(width: 220, height: 160),
        sizing: sizing),
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

/// Offers a menu only while it has a target, as a document-bound palette would.
@MainActor
private final class TargetMenuContent: NSViewController, PaletteContent {
  typealias Target = NSObject
  private var target: NSObject?

  override func loadView() { view = NSView() }

  var paletteMenu: NSMenu? {
    guard target != nil else { return nil }
    let menu = NSMenu()
    menu.addItem(withTitle: "Act", action: nil, keyEquivalent: "")
    return menu
  }

  func retarget(to target: NSObject?) { self.target = target }
}
