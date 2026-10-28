# Verification

Rigi is an AppKit library. Build and behavioral verification require macOS.
Linux can validate the package manifest and Swift syntax, but cannot prove
native rendering, focus, or event behavior.

## Automated native checks

```sh
swift test
swift run RigiGallery --smoke-test
swift run RigiGallery --screenshot /tmp/rigi-gallery.png
swift build -c release
```

The shared tests cover palette content sizing, frame restoration, resize bands,
typed retargeting, presentation lifecycle, picker selection, and preview finish
callbacks. The gallery smoke check exercises the public API from another target.
CI retains a gallery screenshot for visual inspection.

App CI must also build and test Lucerne and Sion against the pinned revision.
Passing Rigi tests alone does not prove an application's editing adapters.

## Interactive acceptance

In the gallery, then both applications:

1. Open a chooser, browse with arrows, commit with Return, and cancel another
   session with Escape. Check the actual document and undo stack.
2. Click away during preview. Check that it commits once.
3. Tear off a picker, abandon a second drag, close the palette, and reopen it.
   Check for duplicate windows, stale chooser indicators, or extra undo steps.
4. Switch between two documents while a palette floats. Close one, then the
   last. Check that edits target only the intended document and no target lingers.
5. Type in palette fields, then continue editing the document. Deactivate the
   app and return. Verify focus and palette visibility.
6. Resize a palette down to its minimum, restore a saved frame, and move between
   displays. Keep its header and useful content reachable.
7. Inspect normal, pressed, disabled, selected, inactive, and mixed-value states.
   Check at 1x/2x scale and with macOS Dark Mode enabled (Rigi stays Aqua).
8. Use VoiceOver and Full Keyboard Access. Check names, states, focus order,
   native toolbar customization, and keyboard equivalents.

A screenshot checks appearance only. A smoke run checks bounded presentation
and layout only. Neither replaces the editing and accessibility checks above.
