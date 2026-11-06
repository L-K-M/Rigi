import AppKit

/// Owns exactly one palette for each kind across the application, and the
/// arrangement of their floating forms: which share a panel as tabs, which
/// hang below others, where each sits. The arrangement persists in the
/// application's defaults.
@MainActor
public final class PaletteCenter: NSObject {
  public static let shared = PaletteCenter(dock: PaletteDock(store: .userDefaults()))

  private var palettes: [PaletteKind: Palette] = [:]
  private let dock: PaletteDock

  init(dock: PaletteDock) {
    self.dock = dock

    super.init()

    installFrontWindowObservers()
  }

  /// Returns the existing palette when a kind was already registered.
  /// The first registration owns that kind's definition and factories.
  /// `target` is reevaluated, so it should resolve the current front document.
  @discardableResult
  public func palette<Content: PaletteContent>(
    for definition: PaletteDefinition,
    target: @escaping @MainActor () -> Content.Target?,
    makeContent: @escaping @MainActor () -> Content
  ) -> Palette {
    if let palette = palettes[definition.kind] {
      return palette
    }

    let palette = Palette(
      definition: definition,
      target: target,
      makeContent: makeContent,
      dock: dock
    )
    palettes[definition.kind] = palette
    return palette
  }

  public func registeredPalette(for kind: PaletteKind) -> Palette? {
    palettes[kind]
  }

  /// Call after the active document changes outside AppKit's window events.
  public func frontDocumentDidChange() {
    retargetPresentedPalettes()
  }

  public func closeAll() {
    for palette in palettes.values {
      palette.close()
    }
  }

  // MARK: - Groups and layout

  /// Declares which palettes share a panel as tabs, and where each group
  /// first opens, until the person rearranges them. Call before showing
  /// palettes; a layout the person already made wins for the kinds it holds.
  public func setDefaultLayout(_ groups: [PaletteGroupDefault]) {
    dock.setDefaults(groups)
  }

  /// The kinds sharing a panel with `kind`, in tab order, including closed
  /// palettes that reopen there.
  public func groupMembers(of kind: PaletteKind) -> [PaletteKind] {
    dock.members(of: kind)
  }

  /// Takes every floating palette off screen, except panels showing one of
  /// `kinds`, without closing any. Palettes keep their targets and come back
  /// with ``restoreAll()``; showing one brings back its own panel only.
  public func hideAll(except kinds: Set<PaletteKind> = []) {
    dock.hideAll(except: kinds)
  }

  /// Brings back the panels ``hideAll(except:)`` took off screen.
  public func restoreAll() {
    dock.restoreAll()
  }

  /// Whether ``hideAll(except:)`` has panels off screen.
  public var isHidingPalettes: Bool { dock.isHidingPalettes }

  /// Returns to the default groups and placements. Open palettes stay open.
  public func resetLayout() {
    dock.resetLayout()
  }

  private func installFrontWindowObservers() {
    let center = NotificationCenter.default

    center.addObserver(
      self,
      selector: #selector(frontWindowDidChange(_:)),
      name: NSWindow.didBecomeMainNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(frontWindowDidChange(_:)),
      name: NSWindow.didResignMainNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(frontWindowDidChange(_:)),
      name: NSWindow.willCloseNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(frontWindowDidChange(_:)),
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  @objc private func frontWindowDidChange(_: Notification) {
    retargetPresentedPalettes()
  }

  private func retargetPresentedPalettes() {
    for palette in palettes.values where palette.isPresented {
      palette.retarget()
    }
  }
}
