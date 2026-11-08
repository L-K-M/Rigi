# Integration

## Ownership

Rigi depends only on AppKit/Foundation. An application's UI target depends on
Rigi and on its own editor layer. Its portable model and archive targets have
no UI dependency.

Rigi supplies presentation, controls, and callbacks. The application supplies:

- Document and selection identity, including the no-document state.
- Available picker items and specimen rendering.
- Semantic editing commands and validation.
- Preview baseline, commit/cancel, and undo transactions.
- Persistent document or library data.

Use explicit `import RigiUI` in each source that uses the package. A migrating
UI module can re-export RigiUI to preserve its previous public type names.

## Custom chrome and activation

Rigi redraws only chrome when a `ClassicWindow` changes its main/key state.
An app-owned ruler or custom control drawn with `ClassicChrome` conforms to
`ClassicChromeDrawing` to join that redraw. Do not conform document or canvas
views. The walk covers the window's content tree; native toolbar/titlebar
accessories remain outside it and may need their own activation observers.

```swift
final class EditorRuler: NSView, ClassicChromeDrawing {
    // Draw the ruler using ClassicChrome.active(for: self).
}
```

## Chrome schemes

`ClassicChromeScheme` names the chrome palettes: `classicLight` is the
original light chrome and the default, `neutralGray` and `dark` are opt-in.
The library stores no preference; the application calls the setter on the
main thread when its own preference changes:

```swift
// In the application's preference storage.
func applyAppearancePreference() {
    ClassicChrome.apply(scheme: storedScheme)
}
```

The call repaints every `ClassicChromeDrawing` view — Rigi's own chrome and
app-owned conformers — and gives palette windows, popovers, menus, and chrome
containers the matching `NSAppearance`, so native controls inside them follow.
Chrome built after the call adopts the matching appearance on its window's
next activation. Document views are untouched. Rigi refreshes its own cached colors internally.
App-owned chrome should resolve semantic colors in `draw`. Applications using
baked attributed strings or tinted images must refresh those values when they
apply a scheme or receive the workspace accessibility notification.
Increase Contrast
strengthens text and meaningful outlines in every scheme automatically —
classicLight's standard colors are unchanged while it is off — and chrome
repaints on the workspace accessibility notification, so applications that
never call `apply(scheme:)` still follow the setting.

`ClassicChrome.scheme` reports the applied scheme. `ClassicChrome`'s semantic
accessors (`wellFill()`, `secondaryText()`, `engravedText`, …) resolve it at
draw time, so app-owned chrome only needs the conformance above.

## Register a typed palette

`PaletteCenter` resolves the target each time the front document changes. Each
content factory creates distinct attached and floating view controllers. Keep
shared editing state in the application's editor or adapter.

```swift
@MainActor
final class Inspector: NSViewController, PaletteContent {
    typealias Target = MyEditor
    private weak var editor: MyEditor?

    func retarget(to target: MyEditor?) {
        editor = target
        // Refresh values and enablement from the new selection.
    }
}

let inspector = PaletteCenter.shared.palette(
    for: PaletteDefinition(
        kind: PaletteKind("myapp.inspector"),
        title: "Inspector",
        contentSize: NSSize(width: 300, height: 320),
        sizing: .resizable(minimumContentSize: NSSize(width: 260, height: 240)),
        frameAutosaveName: "MyApp.inspector"
    ),
    target: { myDocumentCoordinator.frontEditor },
    makeContent: Inspector.init
)

inspector.present(from: inspectorButton)
```

Add and remove selection observations when retargeting. Release the previous
target when dismissed. A target closure should not retain a closed document.
Call `frontDocumentDidChange()` for target changes outside AppKit window events.
Observe `Palette.presentationDidChangeNotification` to synchronize chooser state.

## Group palettes

Declare default groups before showing palettes. Each group lists the kinds that
share a panel, in tab order, and where the panel first opens. The person's own
arrangement, saved under `Rigi.paletteLayout` in the application's defaults,
wins for every kind it holds. A kind the defaults add to a group whose other
kinds already have one joins the first of them, in default order, as a tab
beside it, without moving anything already placed.

```swift
PaletteCenter.shared.setDefaultLayout([
    PaletteGroupDefault([toolsKind], placement: .topLeading),
    PaletteGroupDefault([optionsKind], placement: .docked(below: toolsKind)),
    PaletteGroupDefault([layersKind, historyKind], placement: .topTrailing),
])
```

Palettes the application opens together at launch keep the tab the person last
picked. `bringToFront()` and a later `showPanel()` select the palette's tab.
`groupMembers(of:)` lists the kinds sharing a kind's panel.

Give a palette commands of its own by returning a menu from `paletteMenu`.
It is asked when the panel shows that palette, to decide whether to draw
the triangle, and again each time the menu opens; build it fresh or update
its items' enabled state for the current target.

`saveWorkspace(named:)`, `applyWorkspace(named:)`, `deleteWorkspace(named:)`
and `workspaceNames` keep named arrangements in the application's defaults
under `Rigi.paletteWorkspaces`. The application owns the menu items and the
name prompt.

Bind the Tab key, when no text field is editing, to toggle
`hideAll(except:)` and `restoreAll()`; check `isHidingPalettes`. Offer
`resetLayout()` as a Reset Palettes or Reset Workspace command.

A `Palette` is also a `TearOffPalette`. Pass it to `TryOnPopover` to give a
try-on chooser a floating form that groups and docks like any other palette.
Its content resolves the selection from the target when retargeted.

## Live specimen previews

Keep `TryOnPopover` alive for the presentation. Start the editor's transaction
only after confirming that no sibling preview is still active.

```swift
editor.beginPreview()
picker.present(
    from: chooser,
    palette: floatingAdapter,
    items: items,
    currentID: editor.selectedStyleID,
    specimenFont: { item in editor.specimenFont(for: item.id) },
    onPreview: { item in editor.previewStyle(item.id) },
    onDetach: { editor.finishPreview(.commit) },
    onFinish: { outcome in
        editor.finishPreview(outcome)
        editor.restoreKeyboardFocus()
    }
)
```

`MyEditor` and the preview methods above are application examples. They are not
Rigi types. Make `finishPreview` idempotent: successful tear-off banks the
transaction before the ordinary finish callback runs. The picker remembers
and restores the invoking window's editor, not its chooser. It leaves focus
alone if the user has clicked into a different editor, and never activates a
window. An explicit focus choice in `onFinish` takes precedence; applications
can use that callback when the document target changes during a preview.

`TearOffPalette` is the adapter seam for an existing app-owned palette. It
prepares a window, reports actual visibility, and receives successful-detach
notification. `cancelDetach()` reports an abandoned tear-off; its default does
nothing. App-owned palettes do not join palette groups. This lets Lucerne retain its style-library and formatting
commands while sharing the same presentation and chrome as Sion.

## Existing application migrations

- **Lucerne:** `FloatingPalette` owns typeface/style/list item tables and editor
  routing. `ToolbarView` owns formatting commands and preview transactions.
  Rigi owns their visual controls, picker, palette shell, and status bar.
- **Sion:** `SionPalettes` registers inspector/library/history content and
  resolves targets. Rigi owns the shared generic palette machinery and shell.
  Sion keeps native toolbar customization and semantic canvas commands.

Pin reviewed package revisions. Update each application's pinned revision only
after the library's native checks pass. Keep app integration tests with the app
and shared presentation tests with Rigi.
