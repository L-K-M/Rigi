import AppKit
import XCTest

@testable import RigiUI

@MainActor
final class PaletteGroupTests: XCTestCase {
  private var palettes: [Palette] = []

  override func tearDown() {
    for palette in palettes {
      palette.close()
    }
    palettes = []
    super.tearDown()
  }

  // MARK: - Snapping and docking geometry

  func testAnEdgeWithinReachSnapsToTheScreenEdgeAndOneFartherOutDoesNot() {
    let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)

    XCTAssertEqual(
      PaletteSnapping.snapped(NSRect(x: 6, y: 300, width: 200, height: 300), to: [], within: [screen]),
      NSRect(x: 0, y: 300, width: 200, height: 300)
    )
    XCTAssertEqual(
      PaletteSnapping.snapped(NSRect(x: 795, y: 495, width: 200, height: 300), to: [], within: [screen]),
      NSRect(x: 800, y: 500, width: 200, height: 300)
    )
    let free = NSRect(x: 40, y: 300, width: 200, height: 300)
    XCTAssertEqual(PaletteSnapping.snapped(free, to: [], within: [screen]), free)
  }

  func testPalettesSnapFlushOnlyWhereTheyFaceEachOther() {
    let screen = NSRect(x: 0, y: 0, width: 2000, height: 1200)
    let other = NSRect(x: 300, y: 400, width: 200, height: 300)

    // Beside it, overlapping vertically: the gap closes.
    XCTAssertEqual(
      PaletteSnapping.snapped(NSRect(x: 505, y: 450, width: 200, height: 200), to: [other], within: [screen]).minX,
      500
    )
    // Level with it but far below: no pull sideways.
    XCTAssertEqual(
      PaletteSnapping.snapped(NSRect(x: 505, y: 50, width: 200, height: 200), to: [other], within: [screen]).minX,
      505
    )
    // Under it, a little off: the top meets its bottom and the left edges align.
    XCTAssertEqual(
      PaletteSnapping.snapped(NSRect(x: 304, y: 197, width: 200, height: 200), to: [other], within: [screen]),
      NSRect(x: 300, y: 200, width: 200, height: 200)
    )
  }

  func testAGroupDocksUnderTheWidestPaletteItsTopRestsOn() {
    let left = NSRect(x: 0, y: 500, width: 200, height: 300)
    let right = NSRect(x: 150, y: 500, width: 300, height: 300)

    XCTAssertEqual(
      PaletteSnapping.dockingParent(of: NSRect(x: 100, y: 300, width: 200, height: 200), among: [left, right]),
      1
    )
    // Touching only at a corner is not hanging below it.
    XCTAssertNil(
      PaletteSnapping.dockingParent(of: NSRect(x: 450, y: 300, width: 200, height: 200), among: [right])
    )
    // A gap is not docking either.
    XCTAssertNil(
      PaletteSnapping.dockingParent(of: NSRect(x: 0, y: 290, width: 200, height: 200), among: [left])
    )
  }

  // MARK: - Layout validation

  func testALoadedLayoutDropsWhatCannotBeRight() {
    var first = PaletteLayout.Group(id: "one", kinds: ["a", "b", "a", ""])
    first.selected = "missing"
    first.frame = CGRect(x: 0, y: 0, width: -5, height: 10)
    first.heights = ["b": 120, "z": 80, "a": .nan]
    first.dockedBelow = "two"

    var second = PaletteLayout.Group(id: "two", kinds: ["c", "b"])
    second.dockedBelow = "one"

    var stray = PaletteLayout.Group(id: "three", kinds: ["d"])
    stray.dockedBelow = "nowhere"
    stray.width = -1

    let duplicate = PaletteLayout.Group(id: "one", kinds: ["e"])
    let empty = PaletteLayout.Group(id: "four", kinds: [])

    let layout = PaletteLayout(groups: [first, second, stray, duplicate, empty]).validated()

    XCTAssertEqual(layout.groups.map(\.id), ["one", "two", "three"])
    XCTAssertEqual(layout.groups[0].kinds, ["a", "b"])
    XCTAssertEqual(layout.groups[0].selected, "a")
    XCTAssertNil(layout.groups[0].frame)
    XCTAssertEqual(layout.groups[0].heights, ["b": 120])
    XCTAssertEqual(layout.groups[1].kinds, ["c"])
    // Two groups hanging from each other: the circle is broken.
    XCTAssertTrue(layout.groups[0].dockedBelow == nil || layout.groups[1].dockedBelow == nil)
    XCTAssertNil(layout.groups[2].dockedBelow)
    XCTAssertNil(layout.groups[2].width)
  }

  func testAnUnreadableSavedLayoutStartsOver() throws {
    let suite = "tests.palette.layout.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PaletteLayoutStore.userDefaults(defaults)

    defaults.set(Data("not json".utf8), forKey: PaletteLayoutStore.defaultsKey)
    XCTAssertNil(store.load())

    var group = PaletteLayout.Group(id: "one", kinds: ["a"])
    group.frame = CGRect(x: 10, y: 20, width: 200, height: 300)
    store.save(PaletteLayout(groups: [group]))
    XCTAssertEqual(store.load()?.groups, [group])

    var future = PaletteLayout(groups: [group])
    future.version = PaletteLayout.currentVersion + 1
    store.save(future)
    XCTAssertNil(store.load())
  }

  // MARK: - Groups

  func testADefaultGroupShowsItsPalettesAsTabsOfOnePanel() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, aContent) = makePalette("a", title: "Alpha", dock: dock)
    let (b, bContent) = makePalette("b", title: "Beta", dock: dock)

    a.showPanel()
    b.showPanel()

    let panel = try XCTUnwrap(a.hostingPanel)
    XCTAssertIdentical(b.hostingPanel, panel)
    XCTAssertTrue(panel.isVisible)
    XCTAssertEqual(panel.chrome.tabTitles, ["Alpha", "Beta"])
    // Opened together, as at launch: the group's own pick, its first tab, stays.
    XCTAssertEqual(panel.chrome.selectedTabIndex, 0)
    XCTAssertIdentical(panel.embeddedController, aContent.first)

    drainRunLoop()
    b.bringToFront()

    XCTAssertEqual(panel.chrome.selectedTabIndex, 1)
    XCTAssertIdentical(panel.embeddedController, bContent.first)
    XCTAssertEqual(panel.title, "Beta")
    XCTAssertEqual(dock.members(of: kind("a")), [kind("a"), kind("b")])
  }

  func testClosingATabKeepsTheGroupAndTheCloseDotClosesTheRest() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)

    a.close()

    XCTAssertFalse(a.isPresented)
    XCTAssertTrue(panel.isVisible)
    XCTAssertEqual(panel.chrome.tabTitles, [], "One palette left shows a plain title")
    XCTAssertEqual(panel.chrome.title, "Beta")

    a.showPanel()
    XCTAssertIdentical(a.hostingPanel, panel, "A closed palette reopens in its group")

    let closeButton = try XCTUnwrap(panel.chrome.subviews.compactMap { $0 as? NSButton }.first)
    closeButton.performClick(nil)

    XCTAssertFalse(a.isPresented)
    XCTAssertFalse(b.isPresented)
    XCTAssertFalse(panel.isVisible)
  }

  func testDraggingATabOutTearsItOffAndDroppingItOnATitleBarMergesIt() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")], placement: .topLeading)])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    let group = try XCTUnwrap(dock.groupID(of: a))

    // Press on Beta's tab, slide along the strip, then pull down and away.
    let tab = panel.convertToScreen(panel.chrome.convert(panel.chrome.tabRects[1], to: nil))
    let session = dock.beginDrag(group: group, tab: b, at: NSPoint(x: tab.midX, y: tab.midY))
    session.move(to: NSPoint(x: tab.midX + 2, y: tab.midY))
    XCTAssertIdentical(b.hostingPanel, panel, "Sliding along the strip keeps the tab")

    session.move(to: NSPoint(x: tab.midX + 300, y: tab.midY - 300))
    let torn = try XCTUnwrap(b.hostingPanel)
    XCTAssertFalse(torn === panel)
    XCTAssertTrue(torn.isVisible)
    XCTAssertEqual(panel.chrome.tabTitles, [])
    XCTAssertEqual(dock.members(of: kind("b")), [kind("b")])
    session.end(at: NSPoint(x: tab.midX + 300, y: tab.midY - 300))

    // Now drag the new panel by its title bar onto the old one's bar.
    let tornGroup = try XCTUnwrap(dock.groupID(of: b))
    let grab = NSPoint(x: torn.frame.midX, y: torn.frame.maxY - 8)
    let drop = NSPoint(x: panel.frame.maxX - 10, y: panel.frame.maxY - 8)
    let move = dock.beginDrag(group: tornGroup, tab: nil, at: grab)
    move.move(to: drop)
    XCTAssertTrue(panel.chrome.isDropTarget)
    move.end(at: drop)

    XCTAssertFalse(panel.chrome.isDropTarget)
    XCTAssertIdentical(b.hostingPanel, panel)
    XCTAssertFalse(torn.isVisible)
    XCTAssertEqual(dock.members(of: kind("a")), [kind("a"), kind("b")])
    XCTAssertEqual(panel.chrome.selectedTabIndex, 1, "The dropped palette shows")
  }

  func testAGroupDroppedUnderAnotherDocksAndMovesWithIt() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let top = try XCTUnwrap(a.hostingPanel)
    let bottom = try XCTUnwrap(b.hostingPanel)
    let topGroup = try XCTUnwrap(dock.groupID(of: a))
    let bottomGroup = try XCTUnwrap(dock.groupID(of: b))
    dock.move(topGroup, to: NSRect(origin: NSPoint(x: 200, y: 400), size: top.frame.size))

    // Drop it a few points off the top palette's bottom-left corner.
    let grab = NSPoint(x: bottom.frame.minX + 40, y: bottom.frame.maxY - 8)
    let target = NSPoint(x: top.frame.minX + 3 + 40, y: top.frame.minY - 4 - 8)
    let session = dock.beginDrag(group: bottomGroup, tab: nil, at: grab)
    session.move(to: target)
    session.end(at: target)

    XCTAssertEqual(dock.dockedParent(of: bottomGroup), topGroup)
    XCTAssertEqual(bottom.frame.maxY, top.frame.minY)
    XCTAssertEqual(bottom.frame.minX, top.frame.minX)

    dock.move(topGroup, to: top.frame.offsetBy(dx: 150, dy: -60))

    XCTAssertEqual(bottom.frame.maxY, top.frame.minY)
    XCTAssertEqual(bottom.frame.minX, top.frame.minX)

    // Collapsing the top palette pulls the column up under its title bar.
    dock.toggleCollapsed(topGroup)
    XCTAssertEqual(top.frame.height, PaletteChromeView.titleBarHeight + PaletteChromeView.contentInset)
    XCTAssertEqual(bottom.frame.maxY, top.frame.minY)

    // Pulling the lower one away undocks it.
    let away = dock.beginDrag(group: bottomGroup, tab: nil, at: NSPoint(x: bottom.frame.midX, y: bottom.frame.maxY - 8))
    away.move(to: NSPoint(x: bottom.frame.midX + 200, y: bottom.frame.maxY - 208))
    away.end(at: NSPoint(x: bottom.frame.midX, y: bottom.frame.maxY - 8))
    XCTAssertNil(dock.dockedParent(of: bottomGroup))
  }

  func testDefaultDockingHangsAGroupUnderAnotherOnFirstOpen() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([
      PaletteGroupDefault([kind("a")], placement: .topLeading),
      PaletteGroupDefault([kind("b")], placement: .docked(below: kind("a"))),
    ])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)

    b.showPanel()
    a.showPanel()

    let top = try XCTUnwrap(a.hostingPanel)
    let bottom = try XCTUnwrap(b.hostingPanel)
    XCTAssertEqual(bottom.frame.maxY, top.frame.minY)
    XCTAssertEqual(bottom.frame.minX, top.frame.minX)
  }

  func testHideAllKeepsPalettesOpenAndRestoreBringsThemBack() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let kept = try XCTUnwrap(a.hostingPanel)
    let hidden = try XCTUnwrap(b.hostingPanel)

    dock.hideAll(except: [kind("a")])

    XCTAssertTrue(dock.isHidingPalettes)
    XCTAssertTrue(kept.isVisible)
    XCTAssertFalse(hidden.isVisible)
    XCTAssertTrue(b.isPresented, "Hiding is not closing")

    dock.restoreAll()

    XCTAssertFalse(dock.isHidingPalettes)
    XCTAssertTrue(hidden.isVisible)
  }

  func testRestoreAllSavesTheRescuedLayoutForTheNextDock() throws {
    let store = PaletteLayoutStore.memory()
    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    let group = try XCTUnwrap(dock.groupID(of: a))

    // The panel's display goes away while it hides: the layout still holds
    // the off-screen place.
    dock.move(group, to: NSRect(origin: NSPoint(x: -6000, y: -5000), size: panel.frame.size))
    dock.saveNow()
    let saved = try XCTUnwrap(store.load())

    dock.hideAll(except: [])
    dock.restoreAll()

    XCTAssertTrue(panel.isVisible)
    XCTAssertNotEqual(dock.layout, saved, "restoring should have rescued the panel")

    // A second dock on the same store, made while the first still shows its
    // palettes, gets the rescued layout immediately rather than at quit.
    let relaunched = PaletteDock(store: store, legacyFrame: { _ in nil })
    relaunched.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    XCTAssertEqual(relaunched.layout, dock.layout)
    XCTAssertEqual(relaunched.members(of: kind("a")), [kind("a"), kind("b")])
  }

  func testTheLayoutComesBackInANewSession() throws {
    let store = PaletteLayoutStore.memory()
    let frame: NSRect
    do {
      let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
      dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
      let (a, _) = makePalette("a", title: "Alpha", dock: dock)
      let (b, _) = makePalette("b", title: "Beta", dock: dock)
      a.showPanel()
      b.showPanel()
      drainRunLoop()
      b.bringToFront()
      let group = try XCTUnwrap(dock.groupID(of: a))
      let panel = try XCTUnwrap(a.hostingPanel)
      dock.move(group, to: NSRect(origin: NSPoint(x: 333, y: 222), size: panel.frame.size))
      frame = panel.frame
      dock.saveNow()
      a.close()
      b.close()
    }

    // The application opens its palettes one after the other, as at launch;
    // no defaults now, so the grouping can only come from the saved layout.
    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()

    let panel = try XCTUnwrap(a.hostingPanel)
    XCTAssertIdentical(b.hostingPanel, panel)
    XCTAssertEqual(panel.frame, frame)
    XCTAssertEqual(panel.chrome.selectedTabIndex, 1, "The tab picked last stays picked")
  }

  func testAFrameSavedBeforeGroupsExistedPlacesThePaletteOnce() throws {
    let dock = PaletteDock(
      store: .memory(),
      legacyFrame: { name in
        name == "Rigi.palette.a" ? NSRect(x: 140, y: 260, width: 999, height: 300) : nil
      }
    )
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)

    a.showPanel()

    let panel = try XCTUnwrap(a.hostingPanel)
    // The top-left corner is kept; the size is the palette's own.
    XCTAssertEqual(panel.frame.minX, 140)
    XCTAssertEqual(panel.frame.maxY, 260 + 300)
    XCTAssertEqual(panel.frame.size, PalettePanel.panelSize(forContentSize: Self.contentSize))
  }

  func testAPopoverTearingOffFromAnOpenGroupGetsItsOwnPanelOrGoesBack() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    let groupPanel = try XCTUnwrap(a.hostingPanel)

    let window = b.windowForDetach(selecting: nil)

    XCTAssertFalse(window === groupPanel, "AppKit moves this window to the drop point")
    XCTAssertEqual(dock.members(of: kind("b")), [kind("b")])

    b.cancelDetach()

    XCTAssertFalse(b.isPresented)
    XCTAssertEqual(dock.members(of: kind("a")), [kind("a"), kind("b")])
    XCTAssertTrue(groupPanel.isVisible)

    _ = b.windowForDetach(selecting: nil)
    b.didDetach()

    XCTAssertTrue(b.isFloating)
    XCTAssertTrue(b.isShowingPanel)
    XCTAssertFalse(b.hostingPanel === groupPanel)
  }

  func testAnAbandonedTearOffLeavesTheGroupDockedCollapsedAndSized() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([
      PaletteGroupDefault([kind("a")], placement: .topLeading),
      PaletteGroupDefault([kind("b"), kind("c")], placement: .docked(below: kind("a"))),
    ])
    let resizable = PaletteSizing.resizable(minimumContentSize: NSSize(width: 100, height: 100))
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock, sizing: resizable)
    let (c, _) = makePalette("c", title: "Gamma", dock: dock, sizing: resizable)
    a.showPanel()
    b.showPanel()
    let groupB = try XCTUnwrap(dock.groupID(of: b))
    let index = try XCTUnwrap(dock.layout.index(ofGroup: groupB))
    dock.toggleCollapsed(groupB)
    b.close()

    // Alone in its group: the drag would reuse the group's own panel.
    _ = b.windowForDetach(selecting: nil)
    b.cancelDetach()

    XCTAssertEqual(dock.dockedParent(of: groupB), dock.groupID(of: a))
    XCTAssertTrue(dock.isCollapsed(groupB))

    // Sharing an open group: the drag moves it out, and back on letting go.
    dock.toggleCollapsed(groupB)
    b.showPanel()
    let panel = try XCTUnwrap(b.hostingPanel)
    panel.setFrame(
      NSRect(x: panel.frame.minX, y: panel.frame.maxY - 300, width: panel.frame.width, height: 300),
      display: false
    )
    let height = dock.layout.groups[index].heights["b"]
    XCTAssertNotNil(height)
    b.close()
    c.showPanel()

    _ = b.windowForDetach(selecting: nil)
    b.cancelDetach()

    XCTAssertEqual(dock.members(of: kind("b")), [kind("b"), kind("c")])
    let restored = try XCTUnwrap(dock.layout.index(ofGroup: groupB))
    XCTAssertEqual(dock.layout.groups[restored].heights["b"], height)
  }

  func testASecondDragInOneSessionStillGoesBackToTheFirstGroup() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()

    // AppKit asks for the window again when a popover that snapped back is
    // dragged a second time; only the popover's close settles the session.
    _ = b.windowForDetach(selecting: nil)
    _ = b.windowForDetach(selecting: nil)
    b.cancelDetach()

    XCTAssertEqual(dock.members(of: kind("b")), [kind("a"), kind("b")])
  }

  func testAFloatingPaletteLendsItsPanelWithoutChangingTheLayout() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let shared = try XCTUnwrap(a.hostingPanel)

    // A floating palette's chooser raises it rather than tearing off, so a
    // tear-off request for one is a no-op that cannot disturb the layout.
    let window = b.windowForDetach(selecting: nil)
    b.cancelDetach()

    XCTAssertIdentical(window, shared)
    XCTAssertEqual(dock.members(of: kind("b")), [kind("a"), kind("b")])
    XCTAssertTrue(b.isFloating)
    XCTAssertTrue(shared.isVisible)
    XCTAssertEqual(shared.chrome.tabTitles, ["Alpha", "Beta"])
  }

  func testClosingAPaletteMidTearOffPutsTheLayoutBack() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()

    let torn = b.windowForDetach(selecting: nil)
    b.close()

    XCTAssertEqual(dock.members(of: kind("b")), [kind("a"), kind("b")])
    XCTAssertFalse(torn.isVisible)

    // A later drag records its own origin: abandoning it keeps the group.
    _ = b.windowForDetach(selecting: nil)
    b.cancelDetach()
    XCTAssertEqual(dock.members(of: kind("b")), [kind("a"), kind("b")])
  }

  func testAskingForGroupMembersChangesNothing() {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })

    XCTAssertEqual(dock.members(of: kind("x")), [kind("x")])
    XCTAssertTrue(dock.layout.groups.isEmpty)

    dock.setDefaults([PaletteGroupDefault([kind("x"), kind("y")])])
    XCTAssertEqual(dock.members(of: kind("y")), [kind("x"), kind("y")])
    XCTAssertTrue(dock.layout.groups.isEmpty)
  }

  func testPanelsLeftOffScreenComeBack() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (c, _) = makePalette("c", title: "Gamma", dock: dock)
    a.showPanel()
    c.showPanel()
    let top = try XCTUnwrap(a.hostingPanel)
    let lower = try XCTUnwrap(c.hostingPanel)
    let topGroup = try XCTUnwrap(dock.groupID(of: a))
    let lowerGroup = try XCTUnwrap(dock.groupID(of: c))
    let farAway = NSRect(origin: NSPoint(x: -6000, y: -5000), size: top.frame.size)
    dock.move(topGroup, to: farAway)
    lower.setFrame(
      NSRect(origin: NSPoint(x: farAway.minX, y: farAway.minY - lower.frame.height), size: lower.frame.size),
      display: false
    )
    dock.dock(lowerGroup, below: topGroup)

    // The column's top shows nothing, and the display it was on goes away.
    a.close()
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)

    XCTAssertTrue(Self.titleBarIsOnScreen(lower.frame), "\(lower.frame)")

    // A panel reopened where its frame was left is pulled back too.
    a.showPanel()
    XCTAssertTrue(Self.titleBarIsOnScreen(top.frame), "\(top.frame)")
  }

  func testAColumnRunningOffTheBottomStaysAColumn() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let top = try XCTUnwrap(a.hostingPanel)
    let lower = try XCTUnwrap(b.hostingPanel)
    let topGroup = try XCTUnwrap(dock.groupID(of: a))
    let lowerGroup = try XCTUnwrap(dock.groupID(of: b))
    let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
    // Alpha's title bar just inside the bottom edge; Beta hangs below it.
    dock.move(topGroup, to: NSRect(
      x: screen.midX, y: screen.minY + 20 - top.frame.height,
      width: top.frame.width, height: top.frame.height))
    lower.setFrame(
      NSRect(x: top.frame.minX, y: top.frame.minY - lower.frame.height,
             width: lower.frame.width, height: lower.frame.height),
      display: false)
    dock.dock(lowerGroup, below: topGroup)
    XCTAssertFalse(Self.titleBarIsOnScreen(lower.frame))

    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
    b.bringToFront()

    // Dragging the column up brings Beta back; nothing severs it.
    XCTAssertEqual(dock.dockedParent(of: lowerGroup), topGroup)
    XCTAssertEqual(lower.frame.maxY, top.frame.minY)
  }

  func testAPanelHiddenWhileItsDisplayWentAwayComesBackOnScreen() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    a.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)

    dock.hideAll(except: [])
    panel.setFrame(NSRect(origin: NSPoint(x: -6000, y: -5000), size: panel.frame.size), display: false)
    dock.restoreAll()
    XCTAssertTrue(Self.titleBarIsOnScreen(panel.frame), "\(panel.frame)")

    dock.hideAll(except: [])
    panel.setFrame(NSRect(origin: NSPoint(x: -6000, y: -5000), size: panel.frame.size), display: false)
    a.showPanel()
    XCTAssertTrue(Self.titleBarIsOnScreen(panel.frame), "\(panel.frame)")
    XCTAssertFalse(dock.isHidingPalettes)
  }

  func testATearOffRequestForAHiddenFloatingPaletteRaisesIt() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    a.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    dock.hideAll(except: [])

    let window = a.windowForDetach(selecting: nil)

    XCTAssertIdentical(window, panel)
    XCTAssertTrue(panel.isVisible)
    XCTAssertFalse(dock.isHidingPalettes)
  }

  private static func titleBarIsOnScreen(_ frame: NSRect) -> Bool {
    let bar = NSRect(
      x: frame.minX, y: frame.maxY - PaletteChromeView.titleBarHeight,
      width: frame.width, height: PaletteChromeView.titleBarHeight)
    return NSScreen.screens.contains { $0.visibleFrame.intersects(bar) }
  }

  func testInsertingIntoAColumnKeepsTheLowerPanelsWhereTheyWere() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let (p, _) = makePalette("p", title: "Top", dock: dock)
    let (c, _) = makePalette("c", title: "Lower", dock: dock)
    let (d, _) = makePalette("d", title: "Inserted", dock: dock)
    p.showPanel()
    c.showPanel()
    d.showPanel()
    let top = try XCTUnwrap(p.hostingPanel)
    let lower = try XCTUnwrap(c.hostingPanel)
    let inserted = try XCTUnwrap(d.hostingPanel)
    let topGroup = try XCTUnwrap(dock.groupID(of: p))
    let lowerGroup = try XCTUnwrap(dock.groupID(of: c))
    let insertedGroup = try XCTUnwrap(dock.groupID(of: d))
    dock.move(topGroup, to: NSRect(origin: NSPoint(x: 100, y: 500), size: top.frame.size))
    lower.setFrame(
      NSRect(origin: NSPoint(x: 100, y: top.frame.minY - lower.frame.height), size: lower.frame.size),
      display: false
    )
    dock.dock(lowerGroup, below: topGroup)
    inserted.setFrame(
      NSRect(origin: NSPoint(x: 150, y: top.frame.minY - inserted.frame.height), size: inserted.frame.size),
      display: false
    )

    dock.dock(insertedGroup, below: topGroup)

    XCTAssertEqual(dock.dockedParent(of: lowerGroup), insertedGroup)
    XCTAssertEqual(lower.frame.maxY, inserted.frame.minY)
    XCTAssertEqual(lower.frame.minX, 100, "The lower panel keeps its place across")
  }

  func testTheCloseDotSaysItClosesEveryTab() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    let closeButton = try XCTUnwrap(panel.chrome.subviews.compactMap { $0 as? NSButton }.first)
    XCTAssertEqual(closeButton.accessibilityLabel(), "Close Alpha palette")

    b.showPanel()

    XCTAssertEqual(closeButton.accessibilityLabel(), "Close all tabs: Alpha, Beta")
    XCTAssertEqual(closeButton.toolTip, "Close All Tabs")
  }

  func testResizingRemembersTheWidthAndThePaletteHeight() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    let (a, _) = makePalette(
      "a",
      title: "Alpha",
      dock: dock,
      sizing: .resizable(minimumContentSize: NSSize(width: 100, height: 100))
    )
    a.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    let group = try XCTUnwrap(dock.groupID(of: a))

    // A resize the dock did not make, as the side and bottom bands do.
    let resized = NSRect(
      x: panel.frame.minX,
      y: panel.frame.maxY - 400,
      width: 260,
      height: 400
    )
    panel.setFrame(resized, display: false)

    let index = try XCTUnwrap(dock.layout.index(ofGroup: group))
    let content = PalettePanel.contentSize(forPanelSize: resized.size)
    XCTAssertEqual(dock.layout.groups[index].width, content.width)
    XCTAssertEqual(dock.layout.groups[index].heights["a"], content.height)

    a.close()
    a.showPanel()
    XCTAssertEqual(a.hostingPanel?.frame.size, resized.size)
  }

  // MARK: - A new kind joining its default anchor's group

  func testANewKindWhoseDefaultNamesAPlacedKindTabsIntoThatGroup() throws {
    let saved = PaletteLayout.Group(id: "main", kinds: ["a", "b"])
    let store = PaletteLayoutStore.memory(PaletteLayout(groups: [saved]))
    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b"), kind("c")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    let (c, _) = makePalette("c", title: "Gamma", dock: dock)
    a.showPanel()
    b.showPanel()
    drainRunLoop()
    let panel = try XCTUnwrap(a.hostingPanel)
    let frameBefore = try XCTUnwrap(dock.layout.groups.first?.frame)

    c.showPanel()

    XCTAssertIdentical(c.hostingPanel, panel, "The new kind joins its anchor's panel as a tab")
    XCTAssertEqual(dock.groupID(of: c), "main", "The old group id is kept")
    XCTAssertEqual(dock.layout.groups.count, 1)
    XCTAssertEqual(
      dock.layout.groups[0].kinds, ["a", "c", "b"],
      "Inserted beside the anchor; the old members keep their order")
    XCTAssertEqual(dock.layout.groups[0].frame, frameBefore, "The panel does not move")
    XCTAssertEqual(dock.layout.groups[0].selected, "c", "Showing the new tab brings it forward")
    XCTAssertEqual(panel.chrome.tabTitles, ["Alpha", "Gamma", "Beta"])
    XCTAssertEqual(dock.members(of: kind("c")), [kind("a"), kind("c"), kind("b")])
  }

  func testExtendingTheDefaultGroupAfterItFormedTabsTheNewKindIntoIt() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    let group = try XCTUnwrap(dock.groupID(of: a))

    // A newer default set adds c to the same group.
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b"), kind("c")])])
    let (c, _) = makePalette("c", title: "Gamma", dock: dock)
    c.showPanel()

    XCTAssertIdentical(c.hostingPanel, panel)
    XCTAssertEqual(dock.groupID(of: c), group)
    XCTAssertEqual(dock.layout.groups.count, 1)
    XCTAssertEqual(dock.layout.groups[0].kinds, ["a", "c", "b"])
  }

  func testAskingForMembersPredictsTheJoinWithoutMutatingLayoutOrStore() throws {
    var saved = PaletteLayout.Group(id: "main", kinds: ["a", "b"])
    saved.frame = CGRect(x: 40, y: 500, width: 220, height: 260)
    saved.selected = "b"
    saved.isCollapsed = true
    let savedLayout = PaletteLayout(groups: [saved])
    let store = PaletteLayoutStore.memory(savedLayout)
    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b"), kind("c")])])

    let predicted = dock.members(of: kind("c"))

    XCTAssertEqual(predicted, [kind("a"), kind("c"), kind("b")])
    XCTAssertEqual(dock.layout, savedLayout, "Asking changes nothing")
    XCTAssertEqual(store.load(), savedLayout, "The store is untouched")

    let (c, _) = makePalette("c", title: "Gamma", dock: dock)
    c.showPanel()

    XCTAssertEqual(dock.members(of: kind("c")), predicted, "The eventual group matches the prediction")
    XCTAssertEqual(dock.layout.groups[0].id, "main")
    XCTAssertEqual(dock.layout.groups[0].kinds, ["a", "c", "b"])
    let placed = try XCTUnwrap(dock.layout.groups[0].frame)
    XCTAssertEqual(placed.minX, 40, "The group keeps its saved place")
    XCTAssertEqual(placed.maxY, 500 + 260)
    XCTAssertEqual(dock.layout.groups[0].selected, "b", "The join alone keeps the group's own pick")
    XCTAssertTrue(dock.layout.groups[0].isCollapsed, "The join alone keeps the collapse state")
  }

  func testTheFirstPlacedKindInDefaultTemplateOrderIsTheOnlyAnchor() throws {
    let first = PaletteLayout.Group(id: "first", kinds: ["a"])
    let second = PaletteLayout.Group(id: "second", kinds: ["b"])
    let store = PaletteLayoutStore.memory(PaletteLayout(groups: [first, second]))
    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    // Template order puts b's group before a's.
    dock.setDefaults([PaletteGroupDefault([kind("b"), kind("c"), kind("a")])])

    XCTAssertEqual(dock.members(of: kind("c")), [kind("b"), kind("c")])

    let (c, _) = makePalette("c", title: "Gamma", dock: dock)
    c.showPanel()

    XCTAssertEqual(dock.groupID(of: c), "second")
    XCTAssertEqual(dock.layout.groups.map(\.id), ["first", "second"])
    XCTAssertEqual(dock.layout.groups[0].kinds, ["a"], "The other anchor's group is unchanged")
    XCTAssertEqual(dock.layout.groups[1].kinds, ["b", "c"])
  }

  func testAKindBeforeItsAnchorInTheTemplateJoinsInFrontOfIt() throws {
    let main = PaletteLayout.Group(id: "main", kinds: ["a", "b"])
    let store = PaletteLayoutStore.memory(PaletteLayout(groups: [main]))
    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("c"), kind("a"), kind("b")])])

    XCTAssertEqual(dock.members(of: kind("c")), [kind("c"), kind("a"), kind("b")])

    let (c, _) = makePalette("c", title: "Gamma", dock: dock)
    c.showPanel()

    XCTAssertEqual(dock.layout.groups[0].kinds, ["c", "a", "b"])
    XCTAssertEqual(dock.groupID(of: c), "main")
  }

  func testANewKindWithNoPlacedTemplateKindKeepsTheNormalDefaultGroup() throws {
    let dock = PaletteDock(store: .memory(), legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("c"), kind("b")])])
    let (c, _) = makePalette("c", title: "Gamma", dock: dock)

    c.showPanel()

    XCTAssertEqual(dock.members(of: kind("c")), [kind("a"), kind("c"), kind("b")])
    XCTAssertEqual(dock.layout.groups.count, 1)
    XCTAssertEqual(dock.layout.groups[0].kinds, ["a", "c", "b"])
  }

  func testANewKindWithItsOwnLegacyFrameOpensOnItsOwnPanel() throws {
    let dock = PaletteDock(
      store: .memory(),
      legacyFrame: { name in
        name == "Rigi.palette.c" ? NSRect(x: 140, y: 260, width: 999, height: 300) : nil
      }
    )
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    a.showPanel()
    b.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    // The default set gains c, as an update would declare it.
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b"), kind("c")])])
    let (c, _) = makePalette("c", title: "Gamma", dock: dock)

    XCTAssertEqual(dock.members(of: kind("c")), [kind("c")], "The legacy frame predicts a panel of its own")

    c.showPanel()

    let own = try XCTUnwrap(c.hostingPanel)
    XCTAssertFalse(own === panel)
    XCTAssertEqual(own.frame.minX, 140)
    XCTAssertEqual(own.frame.maxY, 260 + 300)
    XCTAssertEqual(dock.layout.groups.count, 2)
    XCTAssertEqual(dock.members(of: kind("c")), [kind("c")])
  }

  func testAUserSplitGroupKeepsItsMembersFrameAndDockingWhenANewKindJoins() throws {
    var main = PaletteLayout.Group(id: "main", kinds: ["x", "a"])
    main.frame = CGRect(x: 50, y: 500, width: 220, height: 260)
    main.selected = "x"
    var other = PaletteLayout.Group(id: "other", kinds: ["b"])
    other.dockedBelow = "main"
    other.dockOffset = 12
    let store = PaletteLayoutStore.memory(PaletteLayout(groups: [main, other]))
    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b"), kind("c")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (c, _) = makePalette("c", title: "Gamma", dock: dock)
    a.showPanel()
    let mainFrame = try XCTUnwrap(dock.layout.groups[dock.layout.index(ofGroup: "main")!].frame)
    let otherFrame = dock.layout.groups[dock.layout.index(ofGroup: "other")!].frame

    c.showPanel()

    let mainIndex = try XCTUnwrap(dock.layout.index(ofGroup: "main"))
    XCTAssertEqual(dock.layout.groups[mainIndex].kinds, ["x", "a", "c"], "The non-default member stays, in place")
    XCTAssertEqual(dock.layout.groups[mainIndex].id, "main")
    XCTAssertEqual(dock.layout.groups[mainIndex].frame, mainFrame)
    let otherIndex = try XCTUnwrap(dock.layout.index(ofGroup: "other"))
    XCTAssertEqual(dock.layout.groups[otherIndex].kinds, ["b"], "The other group's members are unchanged")
    XCTAssertEqual(dock.layout.groups[otherIndex].dockedBelow, "main")
    XCTAssertEqual(dock.layout.groups[otherIndex].dockOffset, 12)
    XCTAssertEqual(dock.layout.groups[otherIndex].frame, otherFrame)
    XCTAssertEqual(dock.groupID(of: c), "main")
  }

  func testAKindAlreadyInASavedGroupKeepsIt() throws {
    let main = PaletteLayout.Group(id: "main", kinds: ["a", "b"])
    let own = PaletteLayout.Group(id: "own", kinds: ["c"])
    let store = PaletteLayoutStore.memory(PaletteLayout(groups: [main, own]))
    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b"), kind("c")])])
    let (c, _) = makePalette("c", title: "Gamma", dock: dock)

    c.showPanel()

    XCTAssertEqual(dock.groupID(of: c), "own")
    XCTAssertEqual(dock.layout.groups.map(\.kinds), [["a", "b"], ["c"]])
    XCTAssertEqual(dock.members(of: kind("c")), [kind("c")])
  }

  func testTheJoinedKindReopensSelectsAndRestoresInItsGroup() throws {
    let main = PaletteLayout.Group(id: "main", kinds: ["a", "b"])
    let store = PaletteLayoutStore.memory(PaletteLayout(groups: [main]))
    let dock = PaletteDock(store: store, legacyFrame: { _ in nil })
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b"), kind("c")])])
    dock.setDefaults([PaletteGroupDefault([kind("a"), kind("b"), kind("c")])])
    let (a, _) = makePalette("a", title: "Alpha", dock: dock)
    let (b, _) = makePalette("b", title: "Beta", dock: dock)
    let (c, _) = makePalette("c", title: "Gamma", dock: dock)
    dock.register(c)
    a.showPanel()
    b.showPanel()
    drainRunLoop()
    c.showPanel()
    let panel = try XCTUnwrap(a.hostingPanel)
    XCTAssertIdentical(c.hostingPanel, panel)

    // Reopening after a close lands in the same group, without duplicating.
    c.close()
    XCTAssertEqual(dock.members(of: kind("c")), [kind("a"), kind("c"), kind("b")])
    c.showPanel()
    XCTAssertIdentical(c.hostingPanel, panel)
    XCTAssertEqual(dock.layout.groups.count, 1)
    XCTAssertEqual(dock.layout.groups[0].kinds, ["a", "c", "b"])

    // Selecting another tab and bringing the new one forward both work.
    dock.select(b)
    XCTAssertEqual(dock.layout.groups[0].selected, "b")
    c.bringToFront()
    XCTAssertEqual(dock.layout.groups[0].selected, "c")
    XCTAssertEqual(panel.chrome.selectedTabIndex, 1)

    // Hide and restore brings the joined panel back.
    dock.hideAll(except: [])
    XCTAssertFalse(panel.isVisible)
    dock.restoreAll()
    XCTAssertTrue(panel.isVisible)
    XCTAssertIdentical(c.hostingPanel, panel)
  }

  // MARK: - Helpers

  private static let contentSize = NSSize(width: 200, height: 240)

  private func kind(_ identifier: String) -> PaletteKind {
    PaletteKind(identifier)
  }

  private func makePalette(
    _ identifier: String,
    title: String,
    dock: PaletteDock,
    sizing: PaletteSizing = .fixed
  ) -> (Palette, GroupTestContentLog) {
    _ = NSApplication.shared
    let log = GroupTestContentLog()
    let palette = Palette(
      definition: PaletteDefinition(
        kind: kind(identifier),
        title: title,
        contentSize: Self.contentSize,
        sizing: sizing
      ),
      target: { NSObject() },
      makeContent: {
        let content = GroupTestContent()
        log.contents.append(content)
        return content
      },
      dock: dock
    )
    palettes.append(palette)
    return (palette, log)
  }

  private func drainRunLoop() {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
  }
}

@MainActor
private final class GroupTestContentLog {
  var contents: [GroupTestContent] = []
  var first: GroupTestContent? { contents.first }
}

@MainActor
private final class GroupTestContent: NSViewController, PaletteContent {
  typealias Target = NSObject

  override func loadView() {
    view = NSView()
  }

  func retarget(to target: NSObject?) {}
}
