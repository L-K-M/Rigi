# Rigi Interface Guidelines

Rigi is a compact, explicit document-application interface in the spirit of
ClarisWorks and iWork '09. Controls look actionable, related commands sit
together, and the document stays visible while people choose formatting.

Run `swift run RigiGallery` for the executable examples.

## Appearance

- Use the light Aqua appearance for Rigi windows. White document surfaces,
  gray workspace, and gradient chrome form one coordinated palette.
- Use `ClassicChrome` and the shared views instead of copying drawing constants
  into an application. A surface mutes when its document window is inactive.
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

Use tooltips for compact controls, but do not rely on them as the only label.
Each icon needs an accessibility description. A mixed value is distinct from
an empty value; an unavailable action is disabled rather than silently ignored.

## Popover, palette, or dialog?

- **Popover:** a short contextual choice anchored to the invoking control.
- **Floating palette:** repeated work while the document remains usable.
- **Inspector:** a palette body showing the current document selection.
- **Dialog/sheet:** a bounded operation requiring an explicit decision.

Palette headers are handles. Dragging the header moves the palette; the close
dot closes it. A resizable palette exposes side and bottom resize bands.
The top remains the move handle. Declare a minimum useful content size.

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
   established frame autosave names during migrations.

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
