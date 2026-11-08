# Standalone form renderer

`fourdform` renders one saved form to self-contained HTML or a versioned JSON
document. It uses the same `FourDFileKit` analysis, `FormPresenter` and
`FormPreviewRenderer` as the macOS extension. There is no separate drawing
implementation.

**Runtime:** macOS 12 or later; no 4D installation, hosting app, Quick Look,
XPC service, browser automation or network connection is required to generate
output. Viewing the HTML requires a browser. AppKit, CoreText, ImageIO and
Foundation are system dependencies. This is not yet a native Windows binary.

## Build and run

From the repository root with Swift 5.9 or later and the macOS SDK:

```sh
swift build --product fourdform
.build/debug/fourdform --help
.build/debug/fourdform --language en --output preview.html \
  Tests/FourDFileKitTests/Fixtures/FormProject/Project/Sources/Forms/Controls/form.4DForm
```

Build the universal release executable without building or registering the
Quick Look app:

```sh
scripts/build-form-renderer.sh
build/standalone/fourdform --language fr --theme classic-dark --page 2 \
  --output preview.html \
  Tests/FourDFileKitTests/Fixtures/FormStaticProject/Project/Sources/Forms/Root/form.4DForm
```

This script ad-hoc signs a local development artifact; it does not notarize a
downloadable distribution.

The executable can be copied away from the app/repository. Project-dependent
forms still need their project files at input time; the generated HTML embeds
its pictures and styles and can be moved independently.

The CLI emits one document per invocation. HTML is the default. `--json`
selects the versioned analysis export; `--html` selects HTML. `--output`/`-o`
writes atomically to an existing parent directory; without it, output goes to
stdout. Output cannot replace the input form. Warnings go to stderr as well
as the HTML notices or JSON `notices`. Exit status is 0 for a rendered
approximation, 1 for analysis/render/output failure, and 2 for invalid command
syntax. Failures do not produce success-shaped error HTML.

`--language` may be repeated in preference order. Without it, the macOS
preferred languages are used, with the analyzer's project fallback rules.
`--theme` accepts `classic-light`, `classic-dark`, `glass-light` or `glass-dark`.
It chooses the initial appearance; all permitted appearance selectors remain
in the HTML. A form's explicit `colorScheme` is honored, so a conflicting
requested theme is an error. `--page N` chooses an existing initial page,
including page 0. With no explicit selection, the calibrated viewer defaults
remain unchanged. Use `--` before a path beginning with `-`.

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
    options: FormRenderOptions(initialTheme: .glassLight, initialPage: 1)
)
try Data(result.html.utf8).write(to: URL(fileURLWithPath: "/path/to/preview.html"))
let export = try result.document.jsonData()
```

Analysis and presentation are also separate:

```swift
let form: FormFileInfo = try renderer.analyze(url: formURL, preferredLanguages: ["fr"])
let result = try renderer.render(form: form, options: FormRenderOptions(initialPage: 2))
```

`FormFileAnalyzer.analyzeForm(_:options:)` is the typed analyzer entry point
for callers already holding a `ByteSource`. Existing registry-based analysis
continues to use the same implementation. The standalone API throws parse,
dependency-budget and invalid-selection errors; missing or unsupported static
resources that can be approximated remain explicit notices.

Language selection occurs during analysis. Rendering an already analyzed
`FormFileInfo` does not reread project files or change its localization.
Callers are responsible for filesystem access. Only Finder uses the separate
folder-authorization/XPC boundary; standalone callers do not need it.

## JSON boundary: schema version 1

`FormRenderDocument.jsonData()` exports:

| Field | Meaning |
|---|---|
| `schemaVersion` | `1`; consumers must reject unsupported versions |
| `referencePlatform` | `"macOS"`; the appearance data is not Windows calibration |
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
have already applied macOS CSS media and localization; Windows must not
interpret them as native Windows metrics or a Windows stylesheet cascade.
The export is an interchange/reference boundary, not an import API or a claim
of Swift ABI stability.

## Supported static subset

- Ordered JSON, bounded local/external RFC 6901 pointers and local overrides.
- Project/global/mac/form stylesheets, supported selector/media rules and
  JSON-versus-`!important` precedence.
- Page-zero layering, numbered pages, saved geometry, static inheritance and
  statically resolvable subforms with nested clipping.
- Local passive pictures, dark variants, bounded raster conversion and
  initial sprite frames.
- Project XLIFF 1.x named, numeric and object-name references, explicit language
  preferences and bounded fallback.
- Calibrated macOS typography and common controls across the four appearances.

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
Dependency confinement and passive-SVG/entity rejection apply to standalone
rendering just as they do in Finder.

## Verification

```sh
swift test --filter FormRendererTests
python3 scripts/test-form-renderer.py --renderer .build/debug/fourdform
scripts/build-form-renderer.sh
python3 scripts/test-form-renderer.py --renderer build/standalone/fourdform
```

The CLI check copies only the executable to a temporary directory, runs with
an empty `PATH`, and checks CSS/pointers/pictures, inherited/subform order,
French XLIFF, HTML/JSON output, initial selections and error exit statuses.
Default standalone HTML is tested byte-for-byte against the shared preview
pipeline. Native-reference tools in the main README are development-only.

See [Windows handover](WINDOWS-HANDOVER.md) for the remaining platform work.
