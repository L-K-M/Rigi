# Rigi Interface Guidelines

Rigi is a compact, explicit document-application interface in the spirit of
ClarisWorks and iWork '09. Controls look actionable, related commands sit
together, and the document stays visible while people choose formatting.

Run `swift run RigiGallery` for the executable examples.

## Appearance

- The default chrome is the light Aqua appearance: white document surfaces,
  gray workspace, and gradient chrome form one coordinated palette.
  `ClassicChromeScheme` offers opt-in `classicLight`, `neutralGray`, and
  `dark` chrome palettes. The application owns the choice and calls
  `ClassicChrome.apply(scheme:)` on the main thread when its preference
  changes; Rigi keeps no persistence of its own. A scheme recolors chrome
  only — document and canvas content keeps the window's appearance.
  Increase Contrast strengthens chrome text and meaningful outlines in
  every scheme, classicLight included.
- Use `ClassicChrome` and the shared views instead of copying drawing constants
  into an application. A surface mutes when its document window is inactive.
  App-owned chrome drawn with these primitives, such as a ruler, conforms to
  `ClassicChromeDrawing` to opt into activation and scheme redraw. Document/canvas views
  do not conform, so changing windows or schemes does not invalidate their
  content.
- Raised bezels mean actionable controls. Sunken bezels mean a selection,
  active color well, or chooser whose palette is already floating.
- Use engraved text for chrome labels and status, ordinary text for editable
  content and form values. Preserve useful contrast and native focus cues.
- Use system fonts and vector glyphs. Align hairlines to whole-point boundaries.
- `ClassicWindow` retains Lucerne's classic silhouette through AppKit's private
  `_cornerMask` hook. It falls back to system corners if that hook stops being
  used. Layout and interaction must never depend on that cosmetic hook.

## Dimensions and grouping

| Token | Points | Purpose |
|---|---:|---|
| `ClassicChrome.controlHeight` | 20 | Compact toolbar and formatting controls |
| `ClassicMetrics.toolbarHeight` | 34 | Custom format bar |
| `ClassicMetrics.statusBarHeight` | 22 | Document status and zoom |
| `ClassicMetrics.controlSpacing` | 9 | Adjacent toolbar controls |
| `ClassicMetrics.horizontalInset` | 10 | Toolbar leading/trailing inset |
| `ClassicMetrics.formSpacing` | 8 | Inspector form rows |
| `PaletteChromeView.titleBarHeight` | 16 | Floating palette header |

- Group controls by intent: tool choice, formatting, appearance, alignment,
  and document utilities. Use an etched separator between groups.
- Use a shared baseline. Prefer a compact labeled row over a tall stack of
  unexplained icons. Inspector labels precede their controls.
- Size a toolbar so all essential controls remain reachable at the minimum
  window size. Preserve native toolbar customization where the app provides it.
- Use white inset wells for collections; use panel backing for surrounding
  controls. Let long palette bodies scroll rather than collapse or clip.
- Status is concise contextual information on the left, zoom on the right.
  Hover help temporarily replaces the normal message and clears on exit.
  Between them, `StatusBarView` can show accessory views (an information
  pop-up, say) and a progress bar with a cancel button for long operations.
  An application with many zoom levels can make the percentage editable
  (`isZoomEditable`); it then decides the zoom and reports it back with
  `setZoom(percent:)`.

## Pick the control by its behavior

- `ClassicToolControl` retains native `NSSegmentedControl` behavior, including
  accessibility, keyboard handling, per-segment tooltips, and toolbar integration.
- `ClassicToolbarButton` and `ClassicPopUpButton` preserve AppKit target/action,
  menu tags, represented objects, and native accessibility. Prefer these for new
  toolbar and inspector content.
- `ClassicSegmentedControl` supports drawn typography/alignment specimens and
  single-choice, multi-choice, or momentary groups. Give it a descriptive label.
- `ClassicChooserControl` opens rich custom content. Set `representsOpenPalette`
  when that content is floating so clicking the control raises the existing
  palette instead of creating a second one.
- `ClassicSizeField` combines a text value and presets. The application parses
  and validates entered values before changing its model.
- Use native checkboxes and text fields for inspector forms, particularly mixed
  selection states. Use `ClassicColorWell` for color selection.
- `ClassicToolGrid` is a tool palette: 24 pt cells in columns, one selected
  tool, radio-group accessibility. A cell holding several tools is a group,
  marked by a corner triangle. Click picks the cell's current tool;
  press-and-hold or drag opens a flyout of the group; Option-click cycles it.
  Give every tool a name, and a shortcut hint when a key picks it. The action
  fires once per pick; `selectTool(id:)` reflects keyboard picks without one.
- `ClassicColorPair` shows a foreground and a background color with a swap
  arrow and a reset to black and white. It reports clicks on each part and
  never changes its colors itself: the application sets both, including
  after a swap or reset. Name the shortcuts the application handles, such as
  X and D, through `swapShortcut` and `resetShortcut`.
- `ClassicValueSlider` is a labelled slider with a number field and unit for
  a bounded value such as a size, an opacity or a color component. Record
  undo on `.committed`, so a drag is one step; `.tracking` is for live
  preview. Typed values are clamped to the range; text that is not a number
  puts the shown value back.
- `ClassicPaletteButtonBar` is the strip of small icon buttons at a palette's
  foot: create and duplicate at the left, delete at the right. Every item
  needs a title, which is its tool tip and its VoiceOver name. Disable items
  that do not apply to the selection rather than hiding them.

Use tooltips for compact controls, but do not rely on them as the only label.
Each icon needs an accessibility description. A mixed value is distinct from
an empty value; an unavailable action is disabled rather than silently ignored.

## Popover, palette, or dialog?

- **Popover:** a short contextual choice anchored to the invoking control.
- **Floating palette:** repeated work while the document remains usable.
- **Inspector:** a palette body showing the current document selection.
- **Dialog/sheet:** a bounded operation requiring an explicit decision.

Palette headers are handles. Dragging the header moves the palette; the close
dot closes it. A resizable palette exposes side and bottom resize bands, and
assistive apps can set its size the same way. The top remains the move
handle, and the title bar's menu triangle wins over the bands. Declare a
minimum useful content size.

## Palette groups and docking

Several palettes can share one panel as tabs drawn in its title bar. A panel
showing one palette shows its plain centered title instead.

- Click a tab to show it. Drag a tab along the bar to reorder it, or out of the
  bar to tear it into a panel of its own.
- Drag the bar of a panel onto another panel's bar to add its palettes there as
  tabs. The target bar shows a focus-colored ring while a drop would join it.
- Panels snap to screen edges and to each other's edges within 8 points. A
  panel dropped with its top on another panel's bottom docks there: the column
  moves together, closes up around closed or collapsed members, and a panel
  dragged out of it undocks.
- Double-click a bar to collapse its panel to the bar, and again to expand it.
  Picking a different tab of a collapsed panel expands it.
- The close dot, Escape and Command-W close every palette in the panel. The
  bar's contextual menu closes or separates one tab and offers collapse.
- A palette with commands of its own (new, duplicate, delete, options)
  offers them through `paletteMenu`: a small triangle at the right end of
  the bar opens it, and the bar's contextual menu repeats it. Keep it to
  commands about the palette's content; window commands stay in the app's
  menus.
- Tabs share the panel's width so the strip never moves under the pointer when
  switching; the height is the shown palette's own. The panel is resizable
  while a resizable palette shows.
- A palette remembers its group while closed and reopens as a tab there.
- A kind the defaults place in a group whose kinds already have one joins the
  first of them, in default order, as a tab beside it; the group's own
  members, order, place and docking stay as the person left them. A kind with
  a frame saved before groups existed still opens where that frame puts it.
- `PaletteCenter.hideAll(except:)` takes panels off screen without closing any
  palette, for an application's Tab key; `restoreAll()` brings them back.
- The arrangement persists in the application's defaults.
  `PaletteCenter.resetLayout()` returns to the application's default groups.
- Workspaces are named arrangements the person saves: groups, tab order,
  places, collapse and docking, and which palettes float. Applying one
  closes the floating palettes and reopens the workspace's in its places;
  panels whose saved place is on no screen come back onto the main one.
  Offer them in the Window menu: the saved names, Save Workspace…, and a
  way to delete one.

## Tear-off contract

1. Clicking a chooser opens its attached popover.
2. Dragging the popover away requests a floating panel. Preparing that panel
   does not itself mark the palette open or commit an edit.
3. Successful detachment transfers presentation to the panel. An abandoned
   drag leaves no phantom open palette or retained document target.
4. There is one generic palette per registered kind across the application.
   Invoking its chooser again raises that palette.
5. Floating palettes follow the front document and its selection. They never
   become the main document window. With no document, their content clears or
   becomes inert according to the application's adapter.
6. Ordinary palette clicks preserve document focus. A text/search field can
   become key when typing requires it. Palettes hide when the app deactivates.
7. Closing a floating palette restores ordinary chooser presentation. Preserve
   established frame autosave names during migrations: a frame saved under one
   places the palette's group the first time, before a layout exists.

The application resolves document identity. Do not cache the window that
originally opened a palette as its permanent edit target.

## Try-on and undo

`TryOnPopover` adds live preview to a specimen list. Its host must implement
this complete editing contract:

| Event | Result |
|---|---|
| Open | Capture one preview baseline |
| Browse with arrows or clicks | Show the candidate without adding undo steps |
| Return or double-click | Commit and dismiss |
| Escape | Restore the baseline and dismiss |
| Click away | Keep the current preview and dismiss |
| Successful tear-off | Commit the attached preview once, then enter palette mode |
| Pick in the floating palette | Commit each pick as an ordinary edit |

One attached session creates at most one undo transaction. A canceled or
unchanged session creates none. The library reports `Outcome.commit` or
`Outcome.cancel`; the editor owns the snapshot, restore, and undo machinery.

Finish a running preview before beginning another. Resolve document closure or
target changes explicitly so a preview cannot commit to the wrong document.
Escape in a palette with already-committed edits must not masquerade as undo.

## Keyboard and accessibility

- Keep native text editing, checkbox mixed states, menu semantics, and focus
  rings. Test with Full Keyboard Access and VoiceOver.
- In a picker, the filter keeps typing focus; Up/Down browse selectable rows,
  Return commits, and Escape cancels. Section captions are never selectable.
- Programmatic selection synchronization must not fire an editing action.
- Closing or committing an attached picker returns focus to the invoking editor.
- Verify named controls, selected states, keyboard activation, and focus order
  in the actual application, not only the gallery.

See [verification](verification.md) for the native acceptance checks.
