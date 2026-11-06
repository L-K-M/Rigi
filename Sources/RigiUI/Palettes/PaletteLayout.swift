import AppKit

/// Where a palette group opens the first time, before the person moves it.
public enum PalettePlacement: Equatable, Sendable {
  /// Centered on the main screen.
  case centered
  /// The top-left corner of the main screen's visible area.
  case topLeading
  /// The top-right corner of the main screen's visible area.
  case topTrailing
  /// Docked under the group holding `kind`, moving with it as one column.
  case docked(below: PaletteKind)
}

/// A group of palettes that share one floating panel as tabs until the
/// person rearranges them, and where that panel first opens.
public struct PaletteGroupDefault: Equatable, Sendable {
  public let kinds: [PaletteKind]
  public let placement: PalettePlacement

  public init(_ kinds: [PaletteKind], placement: PalettePlacement = .centered) {
    precondition(!kinds.isEmpty, "A palette group needs at least one kind")
    precondition(Set(kinds).count == kinds.count, "A palette group lists each kind once")

    self.kinds = kinds
    self.placement = placement
  }
}

/// The arrangement of floating palettes: which kinds share a panel, in what
/// tab order, where each panel sits, and which panels hang below others.
///
/// Every kind belongs to at most one group. A group remembers kinds that are
/// closed, so a palette reopens as a tab of the group it left. The layout is
/// persisted as JSON and validated on load, since a defaults domain can hold
/// anything.
struct PaletteLayout: Codable, Equatable {
  static let currentVersion = 1

  struct Group: Codable, Equatable {
    var id: String
    var kinds: [String]
    var selected: String?
    /// The panel's frame in screen coordinates; nil until first placed.
    var frame: CGRect?
    var isCollapsed = false
    /// The group whose bottom edge this group's top edge hangs from.
    var dockedBelow: String?
    /// Horizontal offset from the left edge of the group above.
    var dockOffset: CGFloat = 0
    /// A content width the person chose by resizing; nil follows the tabs.
    var width: CGFloat?
    /// Content heights the person chose for resizable members, by kind.
    var heights: [String: CGFloat] = [:]

    init(id: String, kinds: [String]) {
      self.id = id
      self.kinds = kinds
      selected = kinds.first
    }
  }

  var version = Self.currentVersion
  var groups: [Group] = []

  func index(ofGroupContaining kind: String) -> Int? {
    groups.firstIndex { $0.kinds.contains(kind) }
  }

  func index(ofGroup id: String) -> Int? {
    groups.firstIndex { $0.id == id }
  }

  /// The groups hanging directly below `id`.
  func children(of id: String) -> [String] {
    groups.filter { $0.dockedBelow == id }.map(\.id)
  }

  /// `id` and every group docked below it, directly or through others,
  /// parents before children.
  func column(from id: String) -> [String] {
    var result = [id]
    var index = 0
    while index < result.count {
      result += children(of: result[index]).filter { !result.contains($0) }
      index += 1
    }
    return result
  }

  /// Drops what a corrupt or hand-edited defaults entry could contain: kinds
  /// listed twice, empty groups, duplicate ids, docking to a missing group,
  /// docking cycles, and sizes no panel can have.
  func validated() -> PaletteLayout {
    var seenKinds = Set<String>()
    var seenIDs = Set<String>()
    var groups: [Group] = []

    for var group in self.groups where !group.id.isEmpty && !seenIDs.contains(group.id) {
      group.kinds = group.kinds.filter { !$0.isEmpty && seenKinds.insert($0).inserted }
      guard !group.kinds.isEmpty else { continue }

      seenIDs.insert(group.id)
      if let selected = group.selected, !group.kinds.contains(selected) {
        group.selected = group.kinds.first
      }
      if let frame = group.frame, !Self.isUsable(frame) {
        group.frame = nil
      }
      if let width = group.width, !(width.isFinite && width > 0) {
        group.width = nil
      }
      group.heights = group.heights.filter {
        group.kinds.contains($0.key) && $0.value.isFinite && $0.value > 0
      }
      if !group.dockOffset.isFinite {
        group.dockOffset = 0
      }
      groups.append(group)
    }

    var layout = PaletteLayout(version: Self.currentVersion, groups: groups)
    for index in layout.groups.indices {
      guard let parent = layout.groups[index].dockedBelow else { continue }
      if !seenIDs.contains(parent) || layout.dockCycle(startingAt: layout.groups[index].id) {
        layout.groups[index].dockedBelow = nil
      }
    }
    return layout
  }

  private func dockCycle(startingAt id: String) -> Bool {
    var visited: Set<String> = [id]
    var current = groups.first { $0.id == id }?.dockedBelow
    while let next = current {
      guard visited.insert(next).inserted else { return true }
      current = groups.first { $0.id == next }?.dockedBelow
    }
    return false
  }

  private static func isUsable(_ frame: CGRect) -> Bool {
    // CGRect's width and height read back standardized, so a negative size
    // would pass as positive; the stored size is what a corrupt entry holds.
    let size = frame.size
    let values = [frame.origin.x, frame.origin.y, size.width, size.height]
    return values.allSatisfy(\.isFinite) && size.width > 0 && size.height > 0
  }
}

/// Reads and writes the layout. The application's defaults hold it by
/// default; tests and standalone palettes keep it in memory.
@MainActor
struct PaletteLayoutStore {
  static let defaultsKey = "Rigi.paletteLayout"

  let load: @MainActor () -> PaletteLayout?
  let save: @MainActor (PaletteLayout) -> Void

  static func userDefaults(_ defaults: UserDefaults = .standard) -> PaletteLayoutStore {
    PaletteLayoutStore(
      load: {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        guard let layout = try? JSONDecoder().decode(PaletteLayout.self, from: data) else {
          // A layout this build cannot read starts over rather than half applying.
          return nil
        }
        guard layout.version == PaletteLayout.currentVersion else { return nil }
        return layout.validated()
      },
      save: { layout in
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: defaultsKey)
      }
    )
  }

  static func memory(_ initial: PaletteLayout? = nil) -> PaletteLayoutStore {
    var stored = initial
    return PaletteLayoutStore(
      load: { stored },
      save: { stored = $0 }
    )
  }
}

/// Magnetic edges for palette moves: a dragged panel jumps the last few
/// points onto a screen edge or a neighbouring palette, which is how two
/// palettes come to sit flush, and how one docks under another.
enum PaletteSnapping {
  /// How close an edge has to come before it snaps.
  static let threshold: CGFloat = 8

  /// `frame` moved by at most `threshold` per axis so that its nearest edge
  /// within reach meets a screen edge or an edge of one of `others`.
  ///
  /// Palettes snap side by side only when they overlap vertically, and one
  /// above the other only when they overlap horizontally, so a palette across
  /// the screen does not tug at the one being moved.
  static func snapped(
    _ frame: NSRect,
    to others: [NSRect],
    within visibleFrames: [NSRect],
    threshold: CGFloat = threshold
  ) -> NSRect {
    var xCandidates: [CGFloat] = []
    var yCandidates: [CGFloat] = []

    for visible in visibleFrames where visible.insetBy(dx: -threshold, dy: -threshold).intersects(frame) {
      xCandidates += [visible.minX - frame.minX, visible.maxX - frame.maxX]
      yCandidates += [visible.maxY - frame.maxY, visible.minY - frame.minY]
    }

    for other in others {
      if ranges(frame.minY...frame.maxY, other.minY...other.maxY, within: threshold) {
        xCandidates += [
          other.maxX - frame.minX, other.minX - frame.maxX,
          other.minX - frame.minX, other.maxX - frame.maxX,
        ]
      }
      if ranges(frame.minX...frame.maxX, other.minX...other.maxX, within: threshold) {
        yCandidates += [
          other.minY - frame.maxY, other.maxY - frame.minY,
          other.maxY - frame.maxY, other.minY - frame.minY,
        ]
      }
    }

    return frame.offsetBy(
      dx: nearest(xCandidates, within: threshold),
      dy: nearest(yCandidates, within: threshold)
    )
  }

  /// The index of the frame whose bottom edge `frame`'s top edge rests on,
  /// with the two overlapping horizontally; the widest overlap wins.
  static func dockingParent(of frame: NSRect, among others: [NSRect]) -> Int? {
    var best: (index: Int, overlap: CGFloat)?
    for (index, other) in others.enumerated() where abs(frame.maxY - other.minY) < 0.5 {
      let overlap = min(frame.maxX, other.maxX) - max(frame.minX, other.minX)
      guard overlap > 0, overlap > (best?.overlap ?? 0) else { continue }
      best = (index, overlap)
    }
    return best?.index
  }

  /// Where a group docked below `parent` sits: its top on the parent's
  /// bottom edge, `offset` in from the parent's left.
  static func dockedFrame(_ frame: NSRect, below parentBottomLeft: NSPoint, offset: CGFloat) -> NSRect {
    NSRect(
      x: parentBottomLeft.x + offset,
      y: parentBottomLeft.y - frame.height,
      width: frame.width,
      height: frame.height
    )
  }

  private static func ranges(
    _ a: ClosedRange<CGFloat>,
    _ b: ClosedRange<CGFloat>,
    within threshold: CGFloat
  ) -> Bool {
    a.lowerBound <= b.upperBound + threshold && b.lowerBound <= a.upperBound + threshold
  }

  private static func nearest(_ candidates: [CGFloat], within threshold: CGFloat) -> CGFloat {
    candidates.filter { abs($0) <= threshold }.min { abs($0) < abs($1) } ?? 0
  }
}
