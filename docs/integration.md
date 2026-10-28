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
transaction before the ordinary finish callback runs.

`TearOffPalette` is the adapter seam for an existing app-owned palette. It
prepares a window, reports actual visibility, and receives successful-detach
notification. This lets Lucerne retain its style-library and formatting
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
