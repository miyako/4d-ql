# Shared form renderer

The public `FourDRender.FormRenderer` API renders one saved form to
self-contained HTML and a versioned JSON document. It uses the same
`FourDFileKit` analysis, `FormPresenter` and `FormPreviewRenderer` as the macOS
extension. There is no separate drawing implementation.

This repository releases the Quick Look app/extension.
The independent image CLI is developed and released in
[4d-form](https://github.com/miyako/4d-form), using these library products.
The preliminary HTML/JSON-only `fourdform` executable and its packaging have
been removed; reusable API, static behavior and calibration tests remain here.

**Runtime:** macOS 12 or later, or Windows 10/11 with the Swift runtime; no
4D installation, hosting app, Quick Look, XPC service, browser automation or
network connection is required to generate output. Viewing the HTML requires
a browser. AppKit, CoreText and ImageIO are the macOS system dependencies;
DirectWrite and Windows Imaging Component are the Windows ones. See the
[Windows handover](WINDOWS-HANDOVER.md) for the Windows platform.

## Build

From the repository root with Swift 5.9 or later and the macOS SDK, or a
Swift toolchain for Windows:

```sh
swift build --target FourDRender
```

External Swift packages can depend on this repository at a pinned release
revision and select the `FourDFileKit` and `FourDRender` products; they do not
need the Quick Look executable targets. Project-dependent forms still need
their project files at input time; generated HTML embeds pictures and styles
and can be moved independently.

Language preferences are ordered, defaulting to macOS preferred languages
and the analyzer's project fallback rules. `FormRenderOptions` selects an
initial appearance and page (including page 0). All permitted appearance
selectors remain in the HTML. A form's explicit `colorScheme` is honored;
a conflicting requested theme is an error. Without explicit selections,
the calibrated viewer defaults remain unchanged.

Each render targets one `FormPlatform`, defaulting to `FormPlatform.current`
(the host OS). `.macOS` produces the Classic and Liquid Glass light/dark
themes; `.windows` produces `windowsClassic`, `fluentLight` and `fluentDark`
using `styleSheets_windows.css`. Pass the platform explicitly for output that
does not depend on the host.

The Quick Look preview on macOS instead analyzes both platforms with
`FormFileAnalyzer(platforms: FormPlatform.previewPlatforms)` and shows them
behind a CSS-only macOS/Windows switch; see
[Windows previews on macOS](WINDOWS-HANDOVER.md#windows-previews-on-macos-quick-look).
`FormRenderer` output and its JSON document remain single-platform.

## Swift API

Import the existing `FourDRender` and `FourDFileKit` libraries:

```swift
import Foundation
import FourDFileKit
import FourDRender

let renderer = FormRenderer()
let result = try renderer.render(
    url: URL(fileURLWithPath: "/path/to/Project/Sources/Forms/Contact/form.4DForm"),
    preferredLanguages: ["en"],
    platform: .macOS,
    options: FormRenderOptions(initialTheme: .glassLight, initialPage: 1)
)
try Data(result.html.utf8).write(to: URL(fileURLWithPath: "/path/to/preview.html"))
let export = try result.document.jsonData()
```

Analysis and presentation are also separate:

```swift
let form: FormFileInfo = try renderer.analyze(url: formURL, preferredLanguages: ["fr"], platform: .windows)
let result = try renderer.render(form: form, options: FormRenderOptions(initialTheme: .fluentDark, initialPage: 2))
```

`FormPlatform` (`macOS`, `windows`) lists its `themes`; every `FormTheme` has a
`platform`, `label` and `dark` flag. An analyzed `FormFileInfo` reports its
`platform` (derived from its appearances), and rendering it keeps that platform. Requesting a theme of the
other platform throws `FormRenderError.unavailableTheme`.

`FormFileAnalyzer.analyzeForm(_:options:)` is the typed analyzer entry point
for callers already holding a `ByteSource`. Existing registry-based analysis
continues to use the same implementation. The shared API throws parse,
dependency-budget and invalid-selection errors; missing or unsupported static
resources that can be approximated remain explicit notices.

Language selection occurs during analysis. Rendering an already analyzed
`FormFileInfo` does not reread project files or change its localization.
Callers are responsible for filesystem access. Only Finder uses the separate
folder-authorization/XPC boundary; library callers do not need it.

## JSON boundary: schema versions 1 and 2

`FormRenderDocument.jsonData()` exports:

| Field | Meaning |
|---|---|
| `schemaVersion` | `1` for macOS, `2` for Windows; consumers must reject unsupported versions |
| `referencePlatform` | `"macOS"` or `"Windows"`: the platform whose appearances, stylesheets and metrics were applied |
| `initialTheme`, `initialPage` | Explicit presentation choices, omitted when not specified |
| `form` | `FormFileInfo`, including original source, resolved properties, appearances, embedded assets, dependency paths and analyzer warnings |
| `notices` | Analyzer warnings plus renderer approximation/omission notices |

Within each appearance, pages and objects are arrays in paint order.
Subform `children` are ordered, container-local objects; `embeddedProperties`
contains their form context. `source` identifies provenance, not a permission
grant or an instruction to execute code. `object.images` maps picture/icon
properties to IDs in `form.images`; image `dataURI`, `width` and `height`
describe bounded embedded artwork.

Keep duplicate object names and source provenance. Do not rebuild paint order
from the object-name maps in original JSON. The effective appearance properties
have already applied the reference platform's CSS media and localization.
Version 2 is the Windows document: appearance `theme` values are
`windowsClassic`, `fluentLight` and `fluentDark`; its structure is otherwise
version 1.
Do not reinterpret one platform's document as the other's.
The export is an interchange/reference boundary, not an import API or a claim
of Swift ABI stability.

## Supported static subset

- Ordered JSON, bounded local/external RFC 6901 pointers and local overrides.
- Project/global/platform (`_mac`/`_windows`)/form stylesheets, supported selector/media rules and
  JSON-versus-`!important` precedence.
- Page-zero layering, numbered pages, saved geometry, static inheritance and
  statically resolvable subforms with nested clipping.
- Local passive pictures, dark variants, bounded raster conversion and
  initial sprite frames.
- Project XLIFF 1.x named, numeric and object-name references, explicit language
  preferences and bounded fallback.
- Calibrated macOS typography and common controls across the four macOS
  appearances, and Windows Classic/Fluent UI light/dark controls measured
  against 4D 21 on Windows 11.

No project methods, expressions, data bindings, components or localization
commands execute. Bound controls show saved expressions, not runtime records.
Dynamic subforms, web areas, plug-ins, Write Pro and View Pro remain
placeholders. Object-valued inline form descriptions are noncanonical saved
schema approximations and emit a notice; native saved-form captures can instead
show a placeholder. Focus, animations, live Liquid Glass materials and full
RTL/rotation fidelity are not promised.

The existing limits remain: 4 MiB JSON, depth 64/100,000 values, 64 dependency
files/16 MiB total, 16 numbered pages, 1,000 objects per appearance, 8,192-point
canvas sides, bounded CSS matching, 32-megapixel pictures/2,048-pixel thumbnails,
24 MiB embedded images, and 4,096 UTF-16 units/100 lines per text label.
Dependency confinement and passive-SVG/entity rejection apply to library
rendering just as they do in Finder.

## Verification

```sh
swift test --filter FormRendererTests
swift test --filter 'FormStatic|FormTextLayout|FormBenchmark'
swift test --filter FormWindowsRendererTests
```

The API tests check CSS/pointers/pictures, inherited/subform order, French
XLIFF, HTML/JSON output, initial selections and thrown errors.
Default API HTML is tested byte-for-byte against the shared preview pipeline.
Image CLI output and isolated-executable checks belong to `4d-form`.
Native-reference tools in the main README are development-only.

See [Windows handover](WINDOWS-HANDOVER.md) for the Windows calibration
methodology and remaining platform work.
