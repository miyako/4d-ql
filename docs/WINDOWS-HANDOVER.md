# Windows form-renderer handover

## Status and entry point

`FourDFileKit` and `FourDRender` build and test with Swift on Windows. The
shared `FormRenderer` API renders forms for an explicit `FormPlatform`
(`.macOS` or `.windows`); the Windows platform has three calibrated
appearances: Windows Classic, Fluent UI light and Fluent UI dark. The macOS
implementation, its output and its tests are unchanged. The shared interface
is documented in [FORM-RENDERER.md](FORM-RENDERER.md).

The image CLI and its rasterizer live in
[4d-form](https://github.com/miyako/4d-form); on Windows it rasterizes this
HTML with WebView2 (Chromium). This repository provides a standalone, unsigned
Windows x86-64 `fourdql` ZIP through hosted CI and tagged releases, including its
runtime DLLs. See [CLI installation](CLI.md#windows-and-linux-downloads) and
[hosted builds](CLI.md#hosted-builds-and-releases).
There is still **no Explorer preview handler**; the Quick Look app, extension and
project-access/XPC targets are declared only on macOS.

## Platform model

| Platform | Themes (`rawValue`, label) | Project stylesheets | JSON |
|---|---|---|---|
| `.macOS` | `classicLight`, `classicDark`, `glassLight`, `glassDark` (Classic/Liquid Glass light/dark) | `styleSheets.css` + `styleSheets_mac.css`, media `mac` | schema 1, `"macOS"` |
| `.windows` | `windowsClassic` "Windows Classic", `fluentLight` "Fluent UI light", `fluentDark` "Fluent UI dark" | `styleSheets.css` + `styleSheets_windows.css`, media `windows` | schema 2, `"Windows"` |

- `FormPlatform.current` is the host OS and is the default of
  `FormRenderer.analyze/render` and `FormFileAnalyzer`. Pass the platform
  explicitly for reproducible output on any host.
- `FormTheme.platform` places every theme on exactly one platform. Windows
  styles are never relabelled macOS styles, and vice versa.
- Windows Classic is light-only. A form forcing `colorScheme: dark` renders
  only `fluentDark`; forcing `light` renders `windowsClassic` and `fluentLight`.
- CSS `form-theme` media: `win-classic` and `fluent-ui`; `prefers-color-scheme`
  in form CSS follows the analyzed appearance, as on macOS.

### Windows HTML contract

The structure is the macOS one:
`.form-preview > .form-appearance > .form-page > .form-scroll > svg[width][height]`,
theme radios `#theme-<rawValue>`, `.form-themes`, `.form-pages` and
`.form-caption` chrome, embedded pictures as `data:` URIs and no script.

Unlike macOS, Windows selection never depends on the browser's
`prefers-color-scheme`: exactly one theme radio is checked. It is the requested
`initialTheme`, otherwise Fluent UI light when the form sets `fluentUI: true`
(4D's opt-in), otherwise Windows Classic, restricted to the themes a forced
`colorScheme` permits. A rasterizer selects another theme by checking its
radio. `.form-appearance` carries `light win-classic`, `light fluent` or
`dark fluent`. The shared report chrome (page palette, syntax colours) still
follows the browser scheme; it is outside the form preview.

## Platform services

Algorithms (JSON, pointers, inheritance, CSS cascade, localization, wrapping,
clipping, SVG generation) are shared. Only these narrow services differ:

| Service | macOS | Windows |
|---|---|---|
| Random-access reads (`ByteSource`) | `open`/`fstat`/`pread` | `CreateFileW`/`GetFileSizeEx`/`ReadFile` at explicit 64-bit offsets |
| Picture conversion (`FormRasterImage`) | ImageIO | Windows Imaging Component (`CFourDWindows`); same 32-megapixel, 2,048-pixel and 4 MiB limits, EXIF orientation, PNG output |
| Font measurement (`FormFontFace`, `DiagramTypography`) | CoreText/AppKit | DirectWrite (`CFourDWindows`): family lookup, weight/style, ascent/descent/cap height, line gap, advances |
| Form palette/metrics/fonts (`FormPlatformStyle`) | existing calibration | measured Windows Classic and Fluent values; selected by the requested theme's platform, never by the host OS |
| XML (`XMLParserPortability`) | Foundation `XMLParser` | FoundationXML (libxml2) hardened: documents declaring entities are rejected before parsing, strict error checking, no re-entrant abort |

`CFourDWindows` is a small C++17 target that compiles to nothing off Windows
and links `windowscodecs`, `dwrite` and `ole32`. No SF Pro or other Apple
font is used or redistributed on Windows; Windows text is measured with the
installed Segoe UI (falling back through Tahoma and Arial).

Rendering `.windows` on a macOS host, or `.macOS` on a Windows host, uses the
host's font service with the target platform's palette and metrics. Text
positions are then approximate; calibrated output requires a matching host.

### Windows previews on macOS (Quick Look)

On macOS the default analyzer registry uses
`FormFileAnalyzer(platforms: FormPlatform.previewPlatforms)`, i.e.
`[.macOS, .windows]` (on Windows it is `[.windows]`). The form is parsed once
and each platform's appearances are styled with that platform's stylesheets;
`FormFileInfo.platforms` lists them in order. A failure of the second platform
becomes a warning. `FormRenderer` keeps analyzing a single platform.

The HTML wraps one unchanged single-platform preview per platform in
`.form-platforms > .form-platform[data-platform]`, selected without script by
`#platform-<rawValue>` radios and `.form-platform-tabs` labels. Each platform
has its own theme radio group (`form-theme-<rawValue>`); picture definitions
are emitted once. The macOS platform is shown first unless the initial theme
is a Windows theme. Single-platform output is byte-identical to before.

Segoe UI is not installed on macOS and cannot be redistributed. When it is
missing (`FormSubstituteFont.isNeeded`), Windows text uses
[Selawik](https://github.com/microsoft/Selawik) 1.01, Microsoft's SIL OFL
metric-compatible substitute, embedded unmodified (no subsetting, as the OFL
reserved name requires) by `scripts/embed-selawik.py`, which verifies the
release SHA-256:

- Measurement: CoreText loads the embedded TrueType files. Selawik's Latin
  advance widths equal Segoe UI's (compared glyph by glyph with fontTools),
  and its OS/2 `usWinAscent`/`usWinDescent` equal Segoe UI's 2210/514 per
  2048 em. CoreText reads the shorter `hhea` metrics, so line ascent, descent,
  cap height, line height and baseline are set from the Windows metrics,
  mirroring DirectWrite. `FormPlatformPreviewTests` checks widths against
  DirectWrite values (±0.5 pt; Segoe UI Bold kerning differs by up to 0.4 pt).
- Drawing: the Windows CSS adds `@font-face` rules with the WOFF2 files as
  `data:` URIs (the CSP gains `font-src data:` only then) and the font stack
  becomes `Segoe UI, Selawik, Tahoma, Arial, sans-serif`. Process-registered
  fonts would not reach the Quick Look web content process.
- Limits: glyph shapes differ from Segoe UI; Selawik has no italic (CoreText
  keeps upright widths) and no non-Latin glyphs, which fall back to system
  fonts with macOS metrics. The license ships as `Selawik-OFL.txt` in the app
  and extension resources.

## Calibration methodology (Windows)

| Item | Value |
|---|---|
| OS | Windows 11 Enterprise 25H2 (build 26200), ARM64 |
| Display scale | 200 % (captures halved to points) |
| Windows Classic reference | 4D 21.0 |
| Fluent UI reference | 4D 21 R4 (21R4.100208); Fluent light/dark via `fluentUI` forms and `SET APPLICATION COLOR SCHEME` |
| Fonts | Segoe UI: 12 pt Classic, 14 pt Fluent (system font size, `fontTheme: additional` one point smaller) |
| Rasterizer used for comparison | Microsoft Edge/WebView2 (Chromium), `--force-color-profile=srgb`, device scale 2 |

Captures used private copies of `Fixtures/FormBenchmarkProject` (Typography,
Controls, ContactInvoice, References), each opened in a live `DIALOG` window
by an authored startup method, with `Project/Sources/dependencies.json` created
before launch and no upstream code executed. `FORM SCREENSHOT` is unsuitable:
it ignores runtime CSS and returns black images for Fluent forms. Window
captures and comparison images are private development artifacts and are not
committed.

Measured values (see `FormPlatformStyle.swift`):

| | Windows Classic | Fluent light | Fluent dark |
|---|---|---|---|
| Window background | `#F0F0F0` | `#F3F3F3` | `#202020` |
| Text | `#000000` | `#1A1A1A` | `#FFFFFF` |
| Input field | `#FFFFFF` | `#FBFBFB` | `#2D2D2D` |
| Default button | `#0078D4` border | `#0055A1` fill | `#40BDFF` fill |
| Default control height | 22 pt | 25 pt | 25 pt |
| Check box/radio glyph, label gap | 13 pt, 3 pt | 20 pt, 8 pt | 20 pt, 8 pt |
| Control corner radius | 0 | 4 pt | 4 pt |

Known approximations:
Windows Classic tab-control and group-box outlines, Fluent tab sizes, and
popup/combo contents (the preview shows the object name or saved value; 4D
shows an empty runtime list). Fluent UI is calibrated on 4D 21 R4 only.

## Build and test on Windows

Install Swift (see the official [Windows installation](https://www.swift.org/install/windows/)),
Visual Studio 2022 C++ build tools and a Windows 10/11 SDK. In a fresh shell,
`SDKROOT` must be set (the installer stores it in the user environment):

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$env:SDKROOT = [Environment]::GetEnvironmentVariable('SDKROOT','User')
swift build --product FourDRender
swift test
& "$(swift build --show-bin-path)\fourdql.exe" --html Tests\FourDFileKitTests\Fixtures\FormProject\Project\Sources\Forms\Controls\form.4DForm
```

Verified with Swift 6.4.2 (`aarch64-unknown-windows-msvc`). `wchar_t ... broken
by a context change` warnings from the Windows SDK module map are benign.

On Windows, tests whose expected values were measured with macOS system fonts,
and symlink-confinement tests when the account cannot create symbolic links
(Developer Mode off), are skipped with a stated reason. Form tests that assert
macOS reference output pin `platform: .macOS`; `FormWindowsRendererTests`
covers the Windows themes, schema, stylesheet selection and HTML contract.
`.gitattributes` keeps fixtures byte-exact under `core.autocrlf`.

## Fixtures and reference evidence

- `Fixtures/FormProject`: CSS, external JSON pointer and passive SVG.
- `Fixtures/FormStaticProject`: inheritance, subforms, clipping, XLIFF.
- `Fixtures/FormBenchmarkProject`: Typography, Controls, ContactInvoice and
  References; the Windows calibration forms were private copies of these.
- `scripts/form-*.py`: macOS-only native-reference tooling.

External HDI sources are not vendored. All committed form fixtures are
self-authored.

## Remaining Windows work

1. Explorer preview-handler integration and Windows packaging (separate from
   4d-form's CLI). The macOS bookmark/XPC authorization is not a Windows design.
2. Refine the approximations listed above with more native references,
   including per-control pixel scores and printed/offscreen captures.
3. Verify other display scales and Windows 10 font metrics.
4. Path handling for UNC and long (`\\?\`) paths and reparse-point confinement
   are exercised only through Foundation's standard paths so far.
