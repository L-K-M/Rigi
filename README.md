# Rigi

> [!IMPORTANT]
> LLM disclosure: This codebase was written with substantial help from large language models: AI coding agents working from the [`AGENTS.md`](AGENTS.md) brief in this repo.

Classic native Mac controls and detachable palettes, extracted from
[Lucerne](https://github.com/L-K-M/Lucerne) and shared with
[Sion](https://github.com/L-K-M/Sion).

**API version:** <!-- version -->0.1.0<!-- /version -->

Rigi provides the polished gradients, compact controls, engraved labels, inset
wells, and floating utility palettes of a classic document application. Its
`RigiUI` Swift package uses AppKit directly. There are no external dependencies.

## Use it

Requires macOS 13+ and Swift 5.9+. Add the package in Xcode, or declare it in
`Package.swift`:

```swift
.package(url: "https://github.com/L-K-M/Rigi.git", branch: "main")
```

Add `.product(name: "RigiUI", package: "rigi")` to your UI target, then:

```swift
import AppKit
import RigiUI

let button = ClassicToolbarButton(title: "Inspector", target: self,
                                  action: #selector(showInspector))
let backing = ClassicBarView(style: .toolbar)
```

Use an immutable revision or release tag for production builds. Keep the
dependency in macOS targets when your application also has a portable core.

## Explore

```sh
swift run RigiGallery
swift test
bash scripts/build.sh
```

The gallery demonstrates controls, a live try-on picker, undo, and tear-off
palettes. `swift run RigiGallery --smoke-test` exercises native layout and
presentation before exiting. CI also captures a gallery PNG as an artifact.

- [Rigi Interface Guidelines](docs/interface-guidelines.md): appearance,
  composition, keyboard behavior, and palette interaction contracts.
- [Integration](docs/integration.md): typed palettes, preview transactions,
  focus, and application ownership.
- [Verification](docs/verification.md): automated checks and native QA.

## Components

| Area | Types |
|---|---|
| Appearance and dimensions | `ClassicChrome`, `ClassicText`, `ClassicMetrics` |
| Native toolbar/inspector controls | `ClassicToolControl`, `ClassicToolbarButton`, `ClassicPopUpButton`, `ClassicColorWell` |
| Formatting controls | `ClassicSegmentedControl`, `ClassicPopUp`, `ClassicChooserControl`, `ClassicSizeField`, `ClassicButton` |
| Surfaces | `ClassicWindow`, `ClassicBarView`, `ClassicPanelView`, `ClassicInsetBox`, `ClassicRuleView`, `EtchedSeparatorView` |
| Status and pickers | `StatusBarView`, `PickerItem`, `PickerListView`, `TryOnPopover` |
| Palettes | `PaletteCenter`, `PaletteDefinition`, `PaletteContent`, `Palette`, `ClassicPaletteWindow`, `PaletteChromeView` |

Applications supply commands, selection values, document targeting, item tables,
and undo transactions. Rigi has no document-model or editor dependency.

The implementation is macOS-only. A Qt implementation can follow the same
guidelines; sharing the Swift/AppKit widgets with a Linux UI is not supported.

## License

[Unlicense](LICENSE). Rigi bundles no third-party code or artwork. Its classic
chrome is drawn with AppKit paths and system fonts.
