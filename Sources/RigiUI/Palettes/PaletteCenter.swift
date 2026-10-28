import AppKit

/// Owns exactly one palette for each kind across the application.
@MainActor
public final class PaletteCenter: NSObject {
  public static let shared = PaletteCenter()

  private var palettes: [PaletteKind: Palette] = [:]

  private override init() {
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
      makeContent: makeContent
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
