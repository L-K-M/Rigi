import AppKit

/// Arranges floating palettes: which share a panel as tabs, where each panel
/// sits, which hang below others as a column, and which are hidden together.
///
/// The layout (``PaletteLayout``) is the record of that arrangement and
/// survives relaunch; the dock keeps one panel per group with palettes
/// showing and derives everything on screen from the layout and from which
/// palettes are presented. Palettes stay the owners of their own
/// presentation state; the dock only ever hosts them.
@MainActor
final class PaletteDock: NSObject {
  /// The gap default placements keep from the screen edges.
  static let placementMargin: CGFloat = 8

  /// How far a dragged tab may stray from its title bar before it tears off
  /// into a panel of its own.
  static let tearOffDistance: CGFloat = 12

  /// What a popover tear-off changed in the layout, so an abandoned drag
  /// can put it back.
  private struct DetachOrigin {
    let group: String
    /// Where the kind sat in its group when the drag moved it out; nil when
    /// the drag reused the group's own panel.
    let position: Int?
    let height: CGFloat?
    let selected: String?
    let isCollapsed: Bool
    let dockedBelow: String?
    let dockOffset: CGFloat
  }

  private let store: PaletteLayoutStore
  private let legacyFrame: @MainActor (String) -> NSRect?

  private(set) var layout: PaletteLayout
  private var defaults: [PaletteGroupDefault] = []
  /// Frames saved under window autosave names seed placements only until a
  /// layout of our own exists, and never after a reset.
  private var consultsLegacyFrames: Bool

  private var palettes: [String: WeakPalette] = [:]
  private var panels: [String: PaletteGroupPanel] = [:]
  private var hiddenGroups: Set<String> = []
  /// Groups whose panels came up during the current run-loop turn. Palettes
  /// an application opens together at launch arrive one by one; the tab the
  /// person last picked stays selected among them.
  private var openingGroups: Set<String> = []
  private var openingResetPending = false
  /// Where a palette tearing off from its popover came from, until the drag
  /// lands or is abandoned.
  private var detachOrigins: [String: DetachOrigin] = [:]
  private var creatingGroups: Set<String> = []
  private var savePending = false

  init(
    store: PaletteLayoutStore,
    legacyFrame: @escaping @MainActor (String) -> NSRect? = { PalettePanel.legacySavedFrame(named: $0) }
  ) {
    self.store = store
    self.legacyFrame = legacyFrame

    let saved = store.load()
    layout = saved ?? PaletteLayout()
    consultsLegacyFrames = saved == nil

    super.init()

    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(screensDidChange(_:)),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(applicationWillTerminate(_:)),
      name: NSApplication.willTerminateNotification,
      object: nil
    )
  }

  // MARK: - Registration and defaults

  func register(_ palette: Palette) {
    palettes[palette.kind.identifier] = WeakPalette(palette)
  }

  func setDefaults(_ groups: [PaletteGroupDefault]) {
    let kinds = groups.flatMap(\.kinds)
    precondition(Set(kinds).count == kinds.count, "A palette kind belongs to one default group")

    defaults = groups
  }

  /// The kinds sharing a panel with `kind`, in tab order, closed ones
  /// included. A kind with no group yet reports the one it would join;
  /// asking creates nothing.
  func members(of kind: PaletteKind) -> [PaletteKind] {
    let identifier = kind.identifier
    let kinds = layout.index(ofGroupContaining: identifier).map { layout.groups[$0].kinds }
      ?? prospectiveKinds(for: identifier)
    return kinds.map(PaletteKind.init)
  }

  /// The kinds a new group for `kind` starts with: its default group, less
  /// the kinds that already live in another group.
  private func prospectiveKinds(for kind: String) -> [String] {
    let template = defaults.first { $0.kinds.contains { $0.identifier == kind } }
    return (template?.kinds.map(\.identifier) ?? [kind]).filter {
      $0 == kind || layout.index(ofGroupContaining: $0) == nil
    }
  }

  // MARK: - Showing and closing

  /// Hosts `palette` in its group's panel and brings that panel forward.
  /// The palette must already be presented as a panel.
  func show(_ palette: Palette) {
    let kind = palette.kind.identifier
    let index = ensureGroupIndex(for: kind)
    let id = layout.groups[index].id

    if !isOccupied(id) {
      noteOpening(id)
    } else if !openingGroups.contains(id) {
      // Asked for while its group is already up: bring this tab forward.
      layout.groups[index].selected = kind
      layout.groups[index].isCollapsed = false
    }

    // Coming back on screen, from closed or from hidden, is when a frame
    // left on a display that has since gone shows up.
    let wasOffScreen = !isOccupied(id) || hiddenGroups.contains(id)
    detachOrigins[kind] = nil
    hiddenGroups.remove(id)
    sync(id)
    if wasOffScreen {
      rescueIfStranded(id)
    }
    orderFront(id)
    scheduleSave()
  }

  /// Raises the panel showing `palette` with its tab selected and expanded.
  func bringToFront(_ palette: Palette) {
    guard let index = layout.index(ofGroupContaining: palette.kind.identifier) else { return }

    let id = layout.groups[index].id
    layout.groups[index].selected = palette.kind.identifier
    layout.groups[index].isCollapsed = false
    hiddenGroups.remove(id)
    sync(id)
    rescueIfStranded(id)
    orderFront(id)
    scheduleSave()
  }

  /// `palette` stopped being presented as a panel.
  func didClose(_ palette: Palette) {
    guard let index = layout.index(ofGroupContaining: palette.kind.identifier) else { return }

    sync(layout.groups[index].id)
    scheduleSave()
  }

  func isShowingPanel(_ palette: Palette) -> Bool {
    guard let id = groupID(of: palette), let groupPanel = panels[id] else { return false }

    return groupPanel.panel.isVisible && groupPanel.tabs.contains { $0 === palette }
  }

  /// The panel `palette` is shown in, if any. Module-internal; tests read it.
  func panel(showing palette: Palette) -> PalettePanel? {
    guard let id = groupID(of: palette), let groupPanel = panels[id],
      groupPanel.tabs.contains(where: { $0 === palette })
    else { return nil }

    return groupPanel.panel
  }

  /// Closes every palette showing in group `id`.
  func closeGroup(_ id: String) {
    for palette in panels[id]?.tabs ?? [] {
      palette.close()
    }
  }

  // MARK: - Tearing off a popover

  /// The panel a palette's popover tears off into. The palette has marked
  /// its detachment prepared, so it counts as one of the panel's tabs.
  ///
  /// AppKit moves the returned window to where the drag ends, so it must
  /// not be one already showing other palettes: a palette whose group is up
  /// moves to a group of its own, and moves back if the drag is abandoned.
  func prepareDetachment(_ palette: Palette) -> PalettePanel {
    let kind = palette.kind.identifier
    let index = ensureGroupIndex(for: kind)
    var id = layout.groups[index].id

    let record = layout.groups[index]
    let others = occupyingPalettes(in: record).filter { $0 !== palette }
    let position = others.isEmpty ? nil : record.kinds.firstIndex(of: kind)
    // A popover that snapped back can be dragged again in the same session;
    // the layout from before the first drag is the one to go back to.
    if detachOrigins[kind] == nil {
      detachOrigins[kind] = DetachOrigin(
        group: id,
        position: position,
        height: record.heights[kind],
        selected: record.selected,
        isCollapsed: record.isCollapsed,
        dockedBelow: record.dockedBelow,
        dockOffset: record.dockOffset
      )
    }

    if position != nil {
      id = moveToNewGroup(kind, fromGroupAt: index)
      // A palette already floating there leaves its old panel's tabs.
      sync(record.id)
    } else {
      layout.groups[index].selected = kind
      layout.groups[index].isCollapsed = false
      layout.groups[index].dockedBelow = nil
    }

    hiddenGroups.remove(id)
    sync(id)
    // sync hosts every occupying palette, so the panel exists.
    return panels[id]!.panel
  }

  /// The tear-off `prepareDetachment` set up did not happen: the layout
  /// goes back to how it was before the drag.
  func cancelDetachment(_ palette: Palette) {
    let kind = palette.kind.identifier
    guard let current = layout.index(ofGroupContaining: kind) else { return }

    let currentID = layout.groups[current].id
    guard let origin = detachOrigins.removeValue(forKey: kind),
      layout.index(ofGroup: origin.group) != nil
    else {
      sync(currentID)
      return
    }

    if let position = origin.position, origin.group != currentID {
      let height = layout.groups[current].heights[kind] ?? origin.height
      removeKind(kind, fromGroupAt: current)
      if let target = layout.index(ofGroup: origin.group) {
        layout.groups[target].kinds.insert(kind, at: min(position, layout.groups[target].kinds.count))
        layout.groups[target].heights[kind] = height
      }
      removeGroupIfEmpty(currentID)
    }

    if let target = layout.index(ofGroup: origin.group) {
      layout.groups[target].selected = origin.selected
      layout.groups[target].isCollapsed = origin.isCollapsed
      if let parent = origin.dockedBelow, layout.index(ofGroup: parent) != nil,
        !layout.column(from: origin.group).contains(parent)
      {
        layout.groups[target].dockedBelow = parent
        layout.groups[target].dockOffset = origin.dockOffset
      }
    }

    sync(origin.group)
    scheduleSave()
  }

  // MARK: - Tabs and collapse

  /// Shows `palette`'s tab in its group. Picking another tab of a collapsed
  /// group opens it; the shown one leaves it be.
  func select(_ palette: Palette) {
    guard let index = layout.index(ofGroupContaining: palette.kind.identifier) else { return }

    let id = layout.groups[index].id
    if layout.groups[index].isCollapsed, displayedPalette(of: id) !== palette {
      layout.groups[index].isCollapsed = false
    }
    layout.groups[index].selected = palette.kind.identifier
    sync(id)
    scheduleSave()
  }

  func toggleCollapsed(_ id: String) {
    guard let index = layout.index(ofGroup: id) else { return }

    layout.groups[index].isCollapsed.toggle()
    sync(id)
    scheduleSave()
  }

  func isCollapsed(_ id: String) -> Bool {
    layout.index(ofGroup: id).map { layout.groups[$0].isCollapsed } ?? false
  }

  /// Moves `palette` out of its group into a new panel beside it.
  func separate(_ palette: Palette) {
    guard let id = groupID(of: palette), let groupPanel = panels[id], groupPanel.tabs.count > 1,
      let index = layout.index(ofGroup: id)
    else { return }

    let origin = groupPanel.panel.frame
    let newID = moveToNewGroup(palette.kind.identifier, fromGroupAt: index)
    sync(id)
    sync(newID, placingAt: NSPoint(x: origin.minX + 24, y: origin.maxY - 24))
    orderFront(newID)
    scheduleSave()
  }

  // MARK: - Hide all

  var isHidingPalettes: Bool { !hiddenGroups.isEmpty }

  /// Takes every showing panel off screen, except those showing one of
  /// `kinds`; ``restoreAll()`` brings them back as they were.
  func hideAll(except kinds: Set<PaletteKind>) {
    let kept = Set(kinds.map(\.identifier))
    for (id, groupPanel) in panels where !groupPanel.tabs.isEmpty && !hiddenGroups.contains(id) {
      guard !groupPanel.tabs.contains(where: { kept.contains($0.kind.identifier) }) else { continue }

      hiddenGroups.insert(id)
      groupPanel.panel.orderOut(nil)
    }
  }

  func restoreAll() {
    let hidden = hiddenGroups
    hiddenGroups = []
    for id in hidden where isOccupied(id) {
      rescueIfStranded(id)
      orderFront(id)
    }
  }

  // MARK: - Reset

  /// Back to the default groups and placements, keeping open palettes open.
  func resetLayout() {
    let shown = panels.values.flatMap(\.tabs)
    for id in Array(panels.keys) {
      dissolvePanel(id)
    }

    hiddenGroups = []
    openingGroups = []
    detachOrigins = [:]
    layout = PaletteLayout()
    consultsLegacyFrames = false

    for palette in shown {
      show(palette)
    }
    saveNow()
  }

  // MARK: - Workspaces

  private lazy var workspaces: [String: PaletteWorkspace] = store.loadWorkspaces()

  var workspaceNames: [String] {
    workspaces.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  /// Saves the arrangement, and which palettes float, under `name`,
  /// replacing a workspace of that name.
  func saveWorkspace(named name: String) {
    let name = Self.workspaceName(name)
    precondition(!name.isEmpty, "A workspace needs a name")

    let open = layout.groups.flatMap(\.kinds).filter {
      palettes[$0]?.palette?.presentation == .panel
    }
    workspaces[name] = PaletteWorkspace(layout: layout, openKinds: open)
    store.saveWorkspaces(workspaces)
  }

  /// Arranges the palettes as workspace `name` saved them: floating
  /// palettes close, then the workspace's open palettes come up in its
  /// groups and places. Returns false for an unknown name.
  @discardableResult
  func applyWorkspace(named name: String) -> Bool {
    guard let workspace = workspaces[Self.workspaceName(name)] else { return false }

    for palette in palettes.values.compactMap(\.palette) where palette.isFloating {
      palette.close()
    }
    for id in Array(panels.keys) {
      dissolvePanel(id)
    }

    hiddenGroups = []
    openingGroups = []
    detachOrigins = [:]
    layout = workspace.layout
    consultsLegacyFrames = false

    for kind in workspace.openKinds {
      palettes[kind]?.palette?.showPanel()
    }
    saveNow()
    return true
  }

  func deleteWorkspace(named name: String) {
    guard workspaces.removeValue(forKey: Self.workspaceName(name)) != nil else { return }
    store.saveWorkspaces(workspaces)
  }

  private static func workspaceName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Moving, snapping and docking

  func beginDrag(group id: String, tab: Palette?, at point: NSPoint) -> PaletteDragSession {
    PaletteDragSession(dock: self, groupID: id, tabKind: tab?.kind.identifier, at: point)
  }

  func frame(of id: String) -> NSRect? {
    panels[id]?.panel.frame ?? layout.index(ofGroup: id).flatMap { layout.groups[$0].frame }
  }

  /// Moves group `id` toward `proposed`, snapping to screen edges and to the
  /// other panels, and carries the groups docked below it along.
  func move(_ id: String, to proposed: NSRect) {
    let column = Set(layout.column(from: id))
    let others = shownGroupIDs().filter { !column.contains($0) }.compactMap { frame(of: $0) }
    let snapped = PaletteSnapping.snapped(
      proposed,
      to: others,
      within: NSScreen.screens.map(\.visibleFrame)
    )

    setFrame(id, snapped)
    layoutColumn(below: id)
    scheduleSave()
  }

  func undock(_ id: String) {
    guard let index = layout.index(ofGroup: id), layout.groups[index].dockedBelow != nil else {
      return
    }

    layout.groups[index].dockedBelow = nil
    layout.groups[index].dockOffset = 0
    scheduleSave()
  }

  /// Docks group `id` below the shown group whose bottom edge its top edge
  /// rests on, if there is one.
  func dockIfTouching(_ id: String) {
    guard let groupFrame = frame(of: id) else { return }

    let column = Set(layout.column(from: id))
    let candidates = shownGroupIDs().filter { !column.contains($0) }
    let frames = candidates.compactMap { self.frame(of: $0) }
    guard frames.count == candidates.count,
      let parent = PaletteSnapping.dockingParent(of: groupFrame, among: frames)
    else { return }

    dock(id, below: candidates[parent])
  }

  /// Hangs group `id`'s column below `parent`. Groups already hanging there
  /// move down to hang below the new column instead.
  func dock(_ id: String, below parent: String) {
    guard id != parent, !layout.column(from: id).contains(parent),
      let index = layout.index(ofGroup: id),
      let groupFrame = frame(of: id), let parentFrame = frame(of: parent)
    else { return }

    // Where the groups already hanging there sit across, to keep them there.
    let displaced = layout.children(of: parent).filter { $0 != id }.compactMap { child in
      layout.index(ofGroup: child).map { (index: $0, x: parentFrame.minX + layout.groups[$0].dockOffset) }
    }

    layout.groups[index].dockedBelow = parent
    layout.groups[index].dockOffset = groupFrame.minX - parentFrame.minX
    layoutColumn(below: parent)

    let tail = columnTail(id)
    let tailX = hangPoint(below: tail)?.x ?? parentFrame.minX
    for child in displaced {
      layout.groups[child.index].dockedBelow = tail
      layout.groups[child.index].dockOffset = child.x - tailX
    }
    layoutColumn(below: tail)
    scheduleSave()
  }

  func dockedParent(of id: String) -> String? {
    layout.index(ofGroup: id).flatMap { layout.groups[$0].dockedBelow }
  }

  /// The shown group whose title bar is under `point`, frontmost first,
  /// leaving out group `id` and the groups docked below it.
  func mergeTarget(at point: NSPoint, dragging id: String) -> String? {
    let column = Set(layout.column(from: id))
    let candidates = shownGroupIDs()
      .filter { !column.contains($0) }
      .compactMap { candidate in panels[candidate].map { (candidate, $0.panel) } }
      .sorted { $0.1.orderedIndex < $1.1.orderedIndex }

    return candidates.first { Self.titleBar(of: $0.1.frame).contains(point) }?.0
  }

  func setDropTarget(_ id: String?, highlighted: Bool) {
    guard let id else { return }
    panels[id]?.panel.chrome.isDropTarget = highlighted
  }

  /// Moves every palette of group `source` into group `target` as tabs,
  /// inserted where `point` falls along the target's tab strip.
  func merge(_ source: String, into target: String, at point: NSPoint) {
    guard source != target, let sourceIndex = layout.index(ofGroup: source),
      layout.index(ofGroup: target) != nil
    else { return }

    let moving = layout.groups[sourceIndex]
    let shownKind = displayedPalette(of: source)?.kind.identifier ?? moving.selected
    let position = insertionIndex(in: target, at: point)

    for child in layout.children(of: source) {
      if let childIndex = layout.index(ofGroup: child) {
        layout.groups[childIndex].dockedBelow = nil
      }
    }
    layout.groups.remove(at: sourceIndex)
    dissolvePanel(source)

    guard let targetIndex = layout.index(ofGroup: target) else { return }
    layout.groups[targetIndex].kinds.insert(contentsOf: moving.kinds, at: position)
    layout.groups[targetIndex].heights.merge(moving.heights) { current, _ in current }
    layout.groups[targetIndex].selected = shownKind
    layout.groups[targetIndex].isCollapsed = false

    hiddenGroups.remove(target)
    sync(target)
    orderFront(target)
    scheduleSave()
  }

  /// Whether `point` is still on group `id`'s title bar, give or take the
  /// tear-off distance.
  func tabStripContains(_ point: NSPoint, group id: String) -> Bool {
    guard let frame = frame(of: id) else { return false }

    return Self.titleBar(of: frame)
      .insetBy(dx: -Self.tearOffDistance, dy: -Self.tearOffDistance)
      .contains(point)
  }

  /// Moves `kind`'s tab along its strip to where `x` has crossed the middle
  /// of the tabs beside it.
  func reorder(_ kind: String, in id: String, toward x: CGFloat) {
    guard let groupPanel = panels[id], let index = layout.index(ofGroup: id),
      let current = groupPanel.tabs.firstIndex(where: { $0.kind.identifier == kind })
    else { return }

    let rects = tabScreenRects(id)
    guard rects.count == groupPanel.tabs.count else { return }

    let destination = rects.enumerated().filter { $0.offset != current && $0.element.midX < x }.count
    guard destination != current else { return }

    var order = groupPanel.tabs.map(\.kind.identifier)
    order.remove(at: current)
    order.insert(kind, at: destination)

    // The open tabs take the new order; closed kinds keep their places.
    var queue = order[...]
    let open = Set(order)
    layout.groups[index].kinds = layout.groups[index].kinds.map {
      open.contains($0) ? (queue.popFirst() ?? $0) : $0
    }

    sync(id)
    scheduleSave()
  }

  /// Pulls `kind`'s tab out of group `id` into a new panel under `point`.
  func tearOff(_ kind: String, from id: String, at point: NSPoint) -> String? {
    guard let groupPanel = panels[id], groupPanel.tabs.count > 1,
      let index = layout.index(ofGroup: id)
    else { return nil }

    let newID = moveToNewGroup(kind, fromGroupAt: index)
    sync(id)
    sync(
      newID,
      placingAt: NSPoint(x: point.x - 24, y: point.y + PaletteChromeView.titleBarHeight / 2)
    )
    orderFront(newID)
    scheduleSave()
    return newID
  }

  // MARK: - Panel callbacks

  /// The panel of group `id` moved or resized other than by the dock.
  func panelFrameDidChange(_ id: String, resized: Bool) {
    guard let index = layout.index(ofGroup: id), let groupPanel = panels[id] else { return }

    let frame = groupPanel.panel.frame
    guard frame != layout.groups[index].frame else { return }

    layout.groups[index].frame = frame

    if resized, !layout.groups[index].isCollapsed, let shown = displayedPalette(of: id),
      case .resizable = shown.definition.sizing
    {
      let content = PalettePanel.contentSize(forPanelSize: frame.size)
      layout.groups[index].width = content.width
      layout.groups[index].heights[shown.kind.identifier] = content.height
    }

    // Moved from outside, as AppKit places a torn-off popover: a group no
    // longer resting on the one above stops hanging from it.
    if let parent = layout.groups[index].dockedBelow {
      if let hang = hangPoint(below: parent), abs(frame.maxY - hang.y) < 0.5 {
        layout.groups[index].dockOffset = frame.minX - hang.x
      } else {
        layout.groups[index].dockedBelow = nil
      }
    }

    layoutColumn(below: id)
    scheduleSave()
  }

  /// Opens the shown palette's own menu under its title bar's triangle.
  func popUpPaletteMenu(forGroup id: String) {
    guard let panel = panels[id]?.panel, let menu = displayedPalette(of: id)?.panelMenu else {
      return
    }

    let anchor = panel.chrome.menuButtonRect
    menu.popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.minY), in: panel.chrome)
  }

  func menu(forGroup id: String, tab index: Int?) -> NSMenu? {
    guard let groupPanel = panels[id], !groupPanel.tabs.isEmpty else { return nil }

    let menu = NSMenu()
    let tabs = groupPanel.tabs
    let palette = index.flatMap { tabs.indices.contains($0) ? tabs[$0] : nil }
      ?? (tabs.count == 1 ? tabs[0] : nil)

    // The palette's own commands come first, as in its triangle's menu.
    if let palette, let own = palette.panelMenu, !own.items.isEmpty {
      let item = NSMenuItem(title: palette.definition.title, action: nil, keyEquivalent: "")
      // A copy: the content may hand out one menu it keeps, and a menu can
      // hang under one item only.
      item.submenu = own.copy() as? NSMenu
      menu.addItem(item)
      menu.addItem(.separator())
    }

    if let palette {
      let title = palette.definition.title
      menu.addItem(PaletteMenuAction.item("Close \(title)") { palette.close() })
      if tabs.count > 1 {
        menu.addItem(
          PaletteMenuAction.item("Move \(title) to a New Panel") { [weak self] in
            self?.separate(palette)
          }
        )
      }
      menu.addItem(.separator())
    }

    let collapseTitle = isCollapsed(id) ? "Expand" : "Collapse"
    menu.addItem(PaletteMenuAction.item(collapseTitle) { [weak self] in self?.toggleCollapsed(id) })
    if tabs.count > 1 {
      menu.addItem(PaletteMenuAction.item("Close All Tabs") { [weak self] in self?.closeGroup(id) })
    }
    return menu
  }

  // MARK: - Layout bookkeeping

  func groupID(of palette: Palette) -> String? {
    layout.index(ofGroupContaining: palette.kind.identifier).map { layout.groups[$0].id }
  }

  /// The palette whose body group `id` shows.
  func displayedPalette(of id: String) -> Palette? {
    guard let index = layout.index(ofGroup: id) else { return nil }

    let tabs = panels[id]?.tabs ?? []
    return tabs.first { $0.kind.identifier == layout.groups[index].selected } ?? tabs.first
  }

  /// The group record for `kind`, created from its default group the first
  /// time it is needed.
  private func ensureGroupIndex(for kind: String) -> Int {
    if let index = layout.index(ofGroupContaining: kind) {
      return index
    }

    let template = defaults.first { $0.kinds.contains { $0.identifier == kind } }
    let kinds = prospectiveKinds(for: kind)

    var group = PaletteLayout.Group(id: UUID().uuidString, kinds: kinds)
    group.selected = kinds.first

    // A default dock relation names a kind; its group may not exist yet.
    // `creatingGroups` stops defaults that dock in a circle.
    creatingGroups.insert(kind)
    defer { creatingGroups.remove(kind) }
    if case .docked(let below) = template?.placement, !kinds.contains(below.identifier),
      !creatingGroups.contains(below.identifier)
    {
      let parentIndex = ensureGroupIndex(for: below.identifier)
      group.dockedBelow = layout.groups[parentIndex].id
    }

    // The recursion above may have created this kind's group already.
    if let index = layout.index(ofGroupContaining: kind) {
      return index
    }

    layout.groups.append(group)
    scheduleSave()
    return layout.groups.count - 1
  }

  /// Moves `kind` from the group at `index` into a new group of its own,
  /// keeping the height the person gave it. Returns the new group's id.
  private func moveToNewGroup(_ kind: String, fromGroupAt index: Int) -> String {
    let height = layout.groups[index].heights[kind]
    removeKind(kind, fromGroupAt: index)

    var group = PaletteLayout.Group(id: UUID().uuidString, kinds: [kind])
    group.heights[kind] = height
    layout.groups.append(group)
    return group.id
  }

  private func removeKind(_ kind: String, fromGroupAt index: Int) {
    layout.groups[index].kinds.removeAll { $0 == kind }
    layout.groups[index].heights[kind] = nil

    guard layout.groups[index].selected == kind else { return }

    // The neighbouring open tab takes over, as closing a tab would show.
    let open = occupyingPalettes(in: layout.groups[index]).map(\.kind.identifier)
    layout.groups[index].selected = open.first ?? layout.groups[index].kinds.first
  }

  /// Removes group `id` once it has no kinds left. Groups hanging below it
  /// hang from its parent instead, so a column closes up.
  private func removeGroupIfEmpty(_ id: String) {
    guard let index = layout.index(ofGroup: id), layout.groups[index].kinds.isEmpty else { return }

    let removed = layout.groups.remove(at: index)
    for child in layout.children(of: id) {
      guard let childIndex = layout.index(ofGroup: child) else { continue }
      layout.groups[childIndex].dockedBelow = removed.dockedBelow
      layout.groups[childIndex].dockOffset += removed.dockOffset
    }
    dissolvePanel(id)
  }

  private func dissolvePanel(_ id: String) {
    guard let groupPanel = panels.removeValue(forKey: id) else { return }

    hiddenGroups.remove(id)
    groupPanel.tabs = []
    groupPanel.panel.chrome.isDropTarget = false
    groupPanel.panel.removeEmbeddedContent()
    groupPanel.panel.orderOut(nil)
    groupPanel.detach()
  }

  private func occupyingPalettes(in group: PaletteLayout.Group) -> [Palette] {
    group.kinds.compactMap { palettes[$0]?.palette }.filter(\.occupiesPanel)
  }

  private func isOccupied(_ id: String) -> Bool {
    !(panels[id]?.tabs.isEmpty ?? true)
  }

  private func shownGroupIDs() -> [String] {
    layout.groups.map(\.id).filter { isOccupied($0) && !hiddenGroups.contains($0) }
  }

  private func noteOpening(_ id: String) {
    openingGroups.insert(id)
    guard !openingResetPending else { return }

    openingResetPending = true
    DispatchQueue.main.async { [weak self] in
      self?.openingGroups.removeAll()
      self?.openingResetPending = false
    }
  }

  private func orderFront(_ id: String) {
    guard let panel = panels[id]?.panel else { return }

    panel.orderFront(nil)
    panel.invalidateShadow()
  }

  // MARK: - Syncing a panel with its group

  /// Brings group `id`'s panel in line with the layout: its tabs, the body
  /// it shows, its size limits and frame. A group with no palettes showing
  /// leaves the screen. Visibility is otherwise left to the caller.
  private func sync(_ id: String, placingAt requestedTopLeft: NSPoint? = nil) {
    guard let index = layout.index(ofGroup: id) else { return }

    let tabs = occupyingPalettes(in: layout.groups[index])
    let selected = tabs.first { $0.kind.identifier == layout.groups[index].selected } ?? tabs.first
    guard let selected else {
      if let groupPanel = panels[id] {
        groupPanel.tabs = []
        groupPanel.panel.chrome.tabTitles = []
        groupPanel.panel.removeEmbeddedContent()
        groupPanel.panel.orderOut(nil)
      }
      hiddenGroups.remove(id)
      layoutColumn(below: id)
      return
    }

    let record = layout.groups[index]
    let contentSize = Self.contentSize(of: record, tabs: tabs, selected: selected)
    let isNew = panels[id] == nil
    let groupPanel = panels[id] ?? makePanel(id, title: selected.definition.title, contentSize: contentSize)
    let panel = groupPanel.panel

    groupPanel.tabs = tabs
    panel.chrome.tabTitles = tabs.count > 1 ? tabs.map(\.definition.title) : []
    panel.chrome.selectedTabIndex = tabs.firstIndex { $0 === selected } ?? 0
    panel.chrome.title = selected.definition.title
    panel.title = selected.definition.title
    panel.chrome.showsMenuButton = selected.panelMenu != nil

    if let controller = selected.panelContentViewController {
      panel.embed(controller, contentSize: contentSize)
    }

    let sizing = Self.sizing(of: record, tabs: tabs, selected: selected, contentSize: contentSize)
    panel.apply(sizing)

    let panelSize =
      record.isCollapsed
      ? PalettePanel.panelSize(forContentSize: NSSize(width: contentSize.width, height: 0))
      : PalettePanel.panelSize(forContentSize: contentSize)

    let topLeft: NSPoint
    if let requestedTopLeft {
      topLeft = requestedTopLeft
    } else if isNew {
      topLeft = initialTopLeft(forGroupAt: index, panelSize: panelSize)
    } else {
      topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    setFrame(
      id,
      NSRect(
        x: topLeft.x,
        y: topLeft.y - panelSize.height,
        width: panelSize.width,
        height: panelSize.height
      )
    )

    positionDocked(id)
    layoutColumn(below: id)
  }

  private func makePanel(_ id: String, title: String, contentSize: NSSize) -> PaletteGroupPanel {
    let groupPanel = PaletteGroupPanel(id: id, dock: self, title: title, contentSize: contentSize)
    panels[id] = groupPanel
    return groupPanel
  }

  /// The body size group `id` shows `selected` at. The width is shared by
  /// the tabs, so switching tabs never moves the strip: the widest open
  /// palette's, or the width the person chose, never under any tab's
  /// minimum. The height is the selected palette's own.
  static func contentSize(
    of group: PaletteLayout.Group,
    tabs: [Palette],
    selected: Palette
  ) -> NSSize {
    let minimumWidth = tabs.map { minimumContentSize(of: $0).width }.max() ?? 0
    let naturalWidth = tabs.map(\.definition.contentSize.width).max() ?? 0
    let width = max(group.width ?? naturalWidth, minimumWidth)

    let definition = selected.definition
    switch definition.sizing {
    case .fixed:
      return NSSize(width: width, height: definition.contentSize.height)

    case .resizable(let minimum):
      let height = group.heights[selected.kind.identifier] ?? definition.contentSize.height
      return NSSize(width: width, height: max(height, minimum.height))
    }
  }

  private static func sizing(
    of group: PaletteLayout.Group,
    tabs: [Palette],
    selected: Palette,
    contentSize: NSSize
  ) -> PalettePanelSizing {
    if group.isCollapsed {
      return .collapsed(width: contentSize.width)
    }

    switch selected.definition.sizing {
    case .fixed:
      return .fixed(contentSize)

    case .resizable(let minimum):
      let minimumWidth = tabs.map { minimumContentSize(of: $0).width }.max() ?? minimum.width
      return .resizable(minimumContentSize: NSSize(width: minimumWidth, height: minimum.height))
    }
  }

  private static func minimumContentSize(of palette: Palette) -> NSSize {
    switch palette.definition.sizing {
    case .fixed:
      return palette.definition.contentSize
    case .resizable(let minimum):
      return minimum
    }
  }

  private func setFrame(_ id: String, _ frame: NSRect) {
    guard let groupPanel = panels[id], let index = layout.index(ofGroup: id) else { return }

    layout.groups[index].frame = frame
    guard groupPanel.panel.frame != frame else { return }

    groupPanel.isApplyingFrame = true
    groupPanel.panel.setFrame(frame, display: true)
    groupPanel.isApplyingFrame = false
  }

  // MARK: - Placement

  private static func titleBar(of frame: NSRect) -> NSRect {
    NSRect(
      x: frame.minX,
      y: frame.maxY - PaletteChromeView.titleBarHeight,
      width: frame.width,
      height: PaletteChromeView.titleBarHeight
    )
  }

  private static var mainVisibleFrame: NSRect {
    (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
  }

  /// Where a group's panel first opens: its saved frame, else a frame an
  /// earlier version saved under a member's autosave name, else its default
  /// placement. A title bar left on no screen comes back onto the main one.
  private func initialTopLeft(forGroupAt index: Int, panelSize: NSSize) -> NSPoint {
    let group = layout.groups[index]

    if let saved = group.frame ?? legacyFrame(of: group) {
      let frame = NSRect(
        x: saved.minX,
        y: saved.maxY - panelSize.height,
        width: panelSize.width,
        height: panelSize.height
      )
      let bar = Self.titleBar(of: frame)
      let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(bar) }
      let placed = onScreen ? frame : PalettePanel.constrained(frame, to: Self.mainVisibleFrame)
      return NSPoint(x: placed.minX, y: placed.maxY)
    }

    let visible = Self.mainVisibleFrame
    let margin = Self.placementMargin
    switch placement(of: group) {
    case .topLeading:
      return NSPoint(x: visible.minX + margin, y: visible.maxY - margin)
    case .topTrailing:
      return NSPoint(x: visible.maxX - margin - panelSize.width, y: visible.maxY - margin)
    case .centered, .docked:
      // Docked groups are moved under their parent once placed.
      return NSPoint(
        x: (visible.midX - panelSize.width / 2).rounded(),
        y: (visible.midY + panelSize.height / 2).rounded()
      )
    }
  }

  private func legacyFrame(of group: PaletteLayout.Group) -> NSRect? {
    guard consultsLegacyFrames else { return nil }

    for kind in group.kinds {
      guard let definition = palettes[kind]?.palette?.definition else { continue }
      let name = definition.frameAutosaveName ?? PalettePanel.defaultFrameAutosavePrefix + kind
      if let frame = legacyFrame(name) {
        return frame
      }
    }
    return nil
  }

  private func placement(of group: PaletteLayout.Group) -> PalettePlacement {
    defaults.first { template in
      template.kinds.contains { group.kinds.contains($0.identifier) }
    }?.placement ?? .centered
  }

  // MARK: - Columns

  /// The point the group docked below `id` hangs from: the bottom-left of
  /// `id`'s panel, or, while `id` shows nothing, the top-left it would have,
  /// so the column closes up around it.
  private func hangPoint(below id: String, visited: Set<String> = []) -> NSPoint? {
    guard !visited.contains(id), let index = layout.index(ofGroup: id) else { return nil }

    let group = layout.groups[index]
    if isOccupied(id), let frame = frame(of: id) {
      return NSPoint(x: frame.minX, y: frame.minY)
    }
    if let parent = group.dockedBelow,
      let hang = hangPoint(below: parent, visited: visited.union([id]))
    {
      return NSPoint(x: hang.x + group.dockOffset, y: hang.y)
    }
    if let frame = group.frame {
      return NSPoint(x: frame.minX, y: frame.maxY)
    }
    return virtualTopLeft(of: index)
  }

  /// Where a group that has never been shown would open, so groups docked
  /// below it by default have something to hang from.
  private func virtualTopLeft(of index: Int) -> NSPoint? {
    let group = layout.groups[index]
    guard let palette = group.kinds.lazy.compactMap({ self.palettes[$0]?.palette }).first else {
      return nil
    }

    let size = PalettePanel.panelSize(
      forContentSize: Self.contentSize(of: group, tabs: [palette], selected: palette)
    )
    let topLeft = initialTopLeft(forGroupAt: index, panelSize: size)
    layout.groups[index].frame = NSRect(
      x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
    return topLeft
  }

  /// Puts docked group `id` back under its parent.
  private func positionDocked(_ id: String) {
    guard let index = layout.index(ofGroup: id), let parent = layout.groups[index].dockedBelow,
      isOccupied(id), let current = frame(of: id), let hang = hangPoint(below: parent)
    else { return }

    setFrame(
      id,
      PaletteSnapping.dockedFrame(current, below: hang, offset: layout.groups[index].dockOffset)
    )
  }

  /// Lays the groups hanging below `id` out under it, all the way down.
  private func layoutColumn(below id: String, visited: Set<String> = []) {
    guard !visited.contains(id) else { return }

    for child in layout.children(of: id) {
      positionDocked(child)
      layoutColumn(below: child, visited: visited.union([id]))
    }
  }

  private func columnTail(_ id: String) -> String {
    var tail = id
    var visited: Set<String> = [id]
    while let next = layout.children(of: tail).first, visited.insert(next).inserted {
      tail = next
    }
    return tail
  }

  /// The tabs' rectangles on screen; a group showing one palette offers its
  /// whole title bar as that palette's tab.
  private func tabScreenRects(_ id: String) -> [NSRect] {
    guard let panel = panels[id]?.panel else { return [] }

    let chrome = panel.chrome
    let rects = chrome.tabRects
    guard !rects.isEmpty else { return [Self.titleBar(of: panel.frame)] }

    return rects.map { panel.convertToScreen(chrome.convert($0, to: nil)) }
  }

  /// The position in `target`'s kinds that `point` along its strip stands for.
  private func insertionIndex(in target: String, at point: NSPoint) -> Int {
    guard let index = layout.index(ofGroup: target) else { return 0 }

    let kinds = layout.groups[index].kinds
    let tabs = panels[target]?.tabs ?? []
    let position = tabScreenRects(target).filter { $0.midX < point.x }.count
    guard position < tabs.count else { return kinds.count }

    return kinds.firstIndex(of: tabs[position].kind.identifier) ?? kinds.count
  }

  // MARK: - Displays and persistence

  /// Free panels first, so the columns hanging from them come back with
  /// them; then docked panels whose column has nothing showing above them.
  @objc private func screensDidChange(_: Notification) {
    let shown = shownGroupIDs()
    for id in shown where dockedParent(of: id) == nil {
      rescueIfStranded(id)
    }
    for id in shown where dockedParent(of: id) != nil {
      rescueIfStranded(id)
    }
    scheduleSave()
  }

  /// Moves group `id` onto the main screen when its title bar, the only
  /// handle it has, is on none: a display went away, or the panel reopened
  /// where an earlier session left it.
  ///
  /// A docked group with a showing group above it is left alone: its
  /// column may simply run off the bottom of a screen, and moving the
  /// column's top brings it back. Only a docked group with nothing showing
  /// above it, which no drag could reach, leaves its column to be rescued.
  @discardableResult
  private func rescueIfStranded(_ id: String) -> Bool {
    let visibleFrames = NSScreen.screens.map(\.visibleFrame)
    guard !visibleFrames.isEmpty, !hasShowingGroupAbove(id), let frame = frame(of: id) else {
      return false
    }

    let bar = Self.titleBar(of: frame)
    guard !visibleFrames.contains(where: { $0.intersects(bar) }) else { return false }

    undock(id)
    setFrame(id, PalettePanel.constrained(frame, to: Self.mainVisibleFrame))
    layoutColumn(below: id)
    return true
  }

  private func hasShowingGroupAbove(_ id: String) -> Bool {
    var visited: Set<String> = [id]
    var current = dockedParent(of: id)
    while let parent = current, visited.insert(parent).inserted {
      if isOccupied(parent), !hiddenGroups.contains(parent) {
        return true
      }
      current = dockedParent(of: parent)
    }
    return false
  }

  @objc private func applicationWillTerminate(_: Notification) {
    saveNow()
  }

  /// Coalesces writes. The delayed perform runs in the default run-loop
  /// mode only, so a drag saves once it ends rather than on every event.
  private func scheduleSave() {
    guard !savePending else { return }

    savePending = true
    perform(#selector(saveNow), with: nil, afterDelay: Self.saveDelay)
  }

  private static let saveDelay: TimeInterval = 0.5

  @objc func saveNow() {
    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(saveNow), object: nil)
    savePending = false
    store.save(layout)
  }
}

/// A palette group's panel and the palettes showing in it as tabs.
@MainActor
final class PaletteGroupPanel: NSObject, NSWindowDelegate, PaletteTitleBarDelegate {
  let id: String
  let panel: PalettePanel
  var tabs: [Palette] = []
  /// Set while the dock moves the panel, so its own moves are not mistaken
  /// for the person's.
  var isApplyingFrame = false

  private weak var dock: PaletteDock?

  init(id: String, dock: PaletteDock, title: String, contentSize: NSSize) {
    self.id = id
    self.dock = dock
    panel = PalettePanel(title: title, contentSize: contentSize)

    super.init()

    panel.delegate = self
    panel.chrome.titleBarDelegate = self
    panel.onCloseRequest = { [weak self] in
      guard let self else { return }
      self.dock?.closeGroup(self.id)
    }
  }

  /// Cuts the panel loose once its group is gone.
  func detach() {
    panel.delegate = nil
    panel.chrome.titleBarDelegate = nil
    panel.onCloseRequest = nil
    dock = nil
  }

  func windowDidMove(_ notification: Notification) {
    guard !isApplyingFrame else { return }
    dock?.panelFrameDidChange(id, resized: false)
  }

  func windowDidResize(_ notification: Notification) {
    guard !isApplyingFrame else { return }
    dock?.panelFrameDidChange(id, resized: true)
  }

  /// Something closed the window outright rather than through the close dot.
  func windowWillClose(_ notification: Notification) {
    dock?.closeGroup(id)
  }

  // MARK: PaletteTitleBarDelegate

  func titleBar(_ chrome: PaletteChromeView, mouseDown event: NSEvent, onTab tab: Int?) {
    guard let dock else { return }

    if event.clickCount == 2 {
      dock.toggleCollapsed(id)
      return
    }

    let palette = tab.flatMap { tabs.count > 1 && tabs.indices.contains($0) ? tabs[$0] : nil }
    if let palette {
      dock.select(palette)
    }

    // A tracking loop rather than mouseDragged: a tab torn off mid-drag
    // leaves this window, and the drag carries on in another.
    let session = dock.beginDrag(group: id, tab: palette, at: NSEvent.mouseLocation)
    var point = NSEvent.mouseLocation
    while let next = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      point = NSEvent.mouseLocation
      if next.type == .leftMouseUp { break }
      session.move(to: point)
    }
    session.end(at: point)
  }

  func titleBar(_ chrome: PaletteChromeView, selectTabAt index: Int) {
    guard tabs.indices.contains(index) else { return }
    dock?.select(tabs[index])
  }

  func titleBar(_ chrome: PaletteChromeView, menuForTabAt tab: Int?) -> NSMenu? {
    dock?.menu(forGroup: id, tab: tab)
  }

  func titleBarMenuButtonPressed(_ chrome: PaletteChromeView) {
    dock?.popUpPaletteMenu(forGroup: id)
  }
}

/// One press-drag-release on a palette title bar: a tab sliding along its
/// strip, torn off into a panel of its own, or a whole group moving, with
/// snapping, docking, and dropping onto another group's title bar to join it.
@MainActor
final class PaletteDragSession {
  private unowned let dock: PaletteDock
  private(set) var groupID: String
  private var tabKind: String?
  private var startPoint: NSPoint
  private var startFrame: NSRect
  private var isMoving = false
  private(set) var mergeTarget: String?

  init(dock: PaletteDock, groupID: String, tabKind: String?, at point: NSPoint) {
    self.dock = dock
    self.groupID = groupID
    self.tabKind = tabKind
    startPoint = point
    startFrame = dock.frame(of: groupID) ?? .zero
  }

  func move(to point: NSPoint) {
    if let kind = tabKind {
      if dock.tabStripContains(point, group: groupID) {
        dock.reorder(kind, in: groupID, toward: point.x)
        return
      }

      guard let newID = dock.tearOff(kind, from: groupID, at: point) else { return }
      tabKind = nil
      groupID = newID
      startPoint = point
      startFrame = dock.frame(of: newID) ?? .zero
    }

    if !isMoving {
      isMoving = true
      dock.undock(groupID)
    }

    dock.move(
      groupID,
      to: startFrame.offsetBy(dx: point.x - startPoint.x, dy: point.y - startPoint.y)
    )
    setMergeTarget(dock.mergeTarget(at: point, dragging: groupID))
  }

  func end(at point: NSPoint) {
    let target = mergeTarget
    setMergeTarget(nil)
    guard isMoving else { return }

    if let target {
      dock.merge(groupID, into: target, at: point)
    } else {
      dock.dockIfTouching(groupID)
    }
  }

  private func setMergeTarget(_ target: String?) {
    guard target != mergeTarget else { return }

    dock.setDropTarget(mergeTarget, highlighted: false)
    mergeTarget = target
    dock.setDropTarget(target, highlighted: true)
  }
}

@MainActor
private struct WeakPalette {
  weak var palette: Palette?

  init(_ palette: Palette) {
    self.palette = palette
  }
}

/// A menu item running a closure; the item keeps its target alive.
@MainActor
private final class PaletteMenuAction: NSObject {
  private let handler: @MainActor () -> Void

  private init(_ handler: @escaping @MainActor () -> Void) {
    self.handler = handler
  }

  static func item(_ title: String, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
    let action = PaletteMenuAction(handler)
    // Not `perform(_:)`: that name is NSObject's performSelector:, which
    // #selector resolves to, and AppKit would hand it the menu item as the
    // selector to perform.
    let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    return item
  }

  @objc private func run(_ sender: Any?) {
    handler()
  }
}
