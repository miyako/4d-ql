# Windows form-renderer handover

## Status and entry point

The calibrated macOS implementation is shared by a public Swift API and the
Quick Look extension. The independent image CLI lives in
[4d-form](https://github.com/miyako/4d-form) and consumes the same libraries;
the preliminary HTML/JSON-only executable is no longer packaged here.
The macOS phase baseline is `16d44b6`; the shared interface is documented in
[FORM-RENDERER.md](FORM-RENDERER.md).

**No Windows executable, Windows native screenshot, Explorer integration or
Windows runtime validation exists in this handover.** The current environment
is macOS. The package declares macOS 12 and imports Apple frameworks; running
`swift build` on Windows is not expected to succeed before adapters/package
changes. Mac Classic/Liquid Glass measurements are not Windows measurements.

The generated HTML and version-1 JSON are self-contained reference artifacts.
A Windows browser may be useful for early inspection, but that is neither a
validated Windows-native renderer nor a substitute for Windows font metrics.

## Reusable implementation and contracts

| Surface | Reuse | Platform work |
|---|---|---|
| `FormValue.swift` | Ordered JSON, duplicate rejection, RFC 6901 value representation | Confirm Foundation Unicode/number behavior on Windows |
| `FormDependencies.swift` | File/byte budgets, project conventions, local pointer rebasing, dependency provenance | Adapt path roots, drive/UNC handling, case sensitivity and reparse-point confinement |
| `FormStaticExpansion.swift` | Ordered inheritance/subforms, cycles/limits, source context | Preserve the same contracts; do not execute methods |
| `FormLocalization.swift` | XLIFF 1.x selection/ambiguity/budgets, entity rejection | Verify FoundationXML availability, locale data and XML behavior |
| `FormStylesheet.swift` | Parsing/selectors/precedence and bounded matching | Separate platform/appearance context; current theme enum/media handling is macOS-specific and ignores Windows-only references |
| `FormFileAnalyzer.analyzeForm` | Typed analysis seam and image-ID mapping | Extract/replace Apple image conversion |
| `FormRenderer`, `FormPresenter` | Throwing API, versioned document, notices, shared report construction | Retain the API contract while selecting an actual Windows backend |
| `FormPreviewRenderer` | Script-free SVG structure, ordering, clipping, sprites and control dispatch | Isolate font/control/palette policy; calibrate it on Windows |
| `4d-form` (separate repository) | Independent image-product packaging around the shared API | Establish its Windows backend and image/output/error contracts separately |

Do not fork the entire SVG renderer or start a second JSON/CSS parser.
Introduce narrow platform services around the existing seams once a Windows
environment can verify them. If another language is selected, use the version-1
JSON as a reference/contract and port the bounded algorithms deliberately,
rather than treating macOS effective styles as Windows output.

## Apple and POSIX dependencies to replace

| Current dependency | Exact code location | Windows work to establish |
|---|---|---|
| `open`, `fstat`, `pread`, POSIX error text | `FourDFileKit/Core/ByteSource.swift` | Bounded random-access file implementation with 64-bit sizes/offsets and explicit short-read errors |
| ImageIO, CoreGraphics, UniformTypeIdentifiers | `FourDFileKit/Form/FormAnalyzer.swift` (`FormImageLoader`) | Passive image decode/thumbnail/PNG encoding with the same pixel/byte limits; Windows Imaging Component is a candidate, not implemented |
| CoreText/AppKit | `FourDRender/FormTextLayout.swift`, font/baseline helpers in `FormPreviewRenderer.swift` | Font lookup, traits, shaping, grapheme-safe wrapping, ascent/descent, line advances and justification; DirectWrite is a candidate, not implemented |
| CoreText for non-form reports | `FourDRender/DiagramTypography.swift` | Split or adapt this dependency too if retaining the whole render target |
| Foundation/macOS locale/XML facilities | `FormLocalization.swift` and related analyzers | Check Windows Swift/Foundation support and import boundaries rather than assuming parity |
| QuickLookUI/AppKit, Security, NSXPC, app groups, scoped bookmarks | Host, extension, `FourDProjectAccess`, `FourDProjectPreviewService` | Exclude these from a Windows standalone target; they are macOS integration, not required rendering algorithms |
| Bash, `codesign`, `lipo`, universal architectures | `scripts/build.sh` | Separate Windows build/package instructions and executable signing |

The shared library products have no dependency on the host, Quick Look or
project-access service. They still depend on Apple rendering/image frameworks.
An `#if os(Windows)` branch returning guessed metrics or skipping pictures is
not an acceptable completed port.

Do not redistribute Apple's SF Pro font files. Current fallback-family CSS and
CoreText positions were calibrated on macOS; a Windows font substitution can
change wrapping, baselines and bounds. Choose and measure Windows fonts in a
real Windows environment.

## Build/run reference

### Verified macOS reference generation

From this checkout:

```sh
.build/debug/fourdql --html \
  Tests/FourDFileKitTests/Fixtures/FormProject/Project/Sources/Forms/Controls/form.4DForm
swift test --filter FormRendererTests
```

Build the development tool first with `swift build --product fourdql`.
For explicit language selection and versioned JSON, use `FormRenderer` as
documented in [FORM-RENDERER.md](FORM-RENDERER.md); `fourdql --json` exports the
analyzer model, not the versioned renderer document.
Explicit languages reduce dependence on the machine's locale. For fixed
macOS reference screenshots, select a permitted theme and numbered page.
Copy HTML/JSON reference outputs, not a macOS executable, to Windows.

### Windows setup and commands after the port

Follow the official [Swift Windows installation](https://www.swift.org/install/windows/)
and [manual dependencies](https://www.swift.org/install/windows/manual/) guidance.
It requires the appropriate Visual Studio C++ build tools and Windows SDK;
install an architecture-matched supported Swift toolchain. Python is needed
for the CLI contract harness, not by the renderer at runtime.

The following is the intended shared-library smoke-test shape **after**
implementing the adapters and excluding macOS-only targets. It is not a claim
these commands work against the current package on Windows:

```powershell
swift --version
swift build -c release --target FourDRender
swift test --filter FormRendererTests
```

Image CLI packaging and commands belong in `4d-form`, not the Quick Look
release workflow. Keep the shared HTML/JSON/error behavior intact. Decide Windows appearance
selection only with Windows evidence; do not silently redefine `glass-light`
or label the existing macOS styles as Windows. Adjust the API tests'
platform/theme assertions explicitly when adding a Windows export version or
appearance schema.

## Fixtures and development reference evidence

- `Fixtures/FormProject`: CSS, external JSON pointer and passive SVG; input
  width 430 and five loaded dependencies provide deterministic checks.
- `Fixtures/FormStaticProject`: multi-level inheritance, duplicate-name paint
  order, repeated subforms, nested clipping, source CSS and English/French XLIFF.
  Inline object-form fixtures deliberately carry noncanonical-schema notices.
- `Fixtures/FormBenchmarkProject`: Typography, Controls, ContactInvoice and
  References, covering authored layouts and all four macOS appearances.
- `FormTests`, `FormStaticTests`, `FormTextLayoutTests`, `FormStaticRenderTests`,
  `FormRendererTests`: ordering, confinement, budgets, source/data preservation,
  wrapping, pictures, localization, clipping and API regression contracts.
- `scripts/form-benchmark.py`, `form-hdi-benchmark.py`,
  `form-padding-probe.py`, `form-static-benchmark.py`,
  `form-subform-clip-probe.py`: macOS-only native-reference tooling. Do not run
  them unchanged on Windows or make the renderer depend on them.

Mac evidence includes Classic LTS and R5 Glass references, pinned public HDI
cases, and authored static-form checks. The explicit subform overflow probe
matched native and actual WebKit paint at `[100,80,220,120]`: 4,800 exact-color
pixels with both outside markers clipped. Omitted-format pictures stayed
16 x 16 at the full-object center. These prove those macOS behaviors, not
Windows geometry. Original native captures and comparison galleries are
private development artifacts, not committed fixture assets.

External HDI sources are not vendored. The benchmark download tooling records
pinned revisions; verify licenses before redistributing any external forms.
All committed form fixtures above are self-authored.

## Windows acceptance sequence

1. Build the shared libraries and the separate image product on Windows without
   4D, the macOS host or an Explorer extension. Run parsing, confinement,
   XML rejection and CLI failures in their owning repositories.
2. Check generated JSON ordering, source provenance, dependency/image IDs,
   localization and limits against the self-authored reference contracts.
3. Generate purpose-built static native forms on Windows using a supported
   full 4D application solely as a development reference. Create
   `Project/Sources/dependencies.json` before launch. Never run upstream project
   methods/components; only authored capture methods belong in private copies.
4. Keep named screenshots, loaded/offscreen, printed and live-dialog captures
   separate. Named captures can ignore CSS; do not use them as CSS runtime proof.
5. Measure actual font glyph bounds, wrapping, baselines, control heights,
   padding, default picture placement, listbox surfaces and nested clipping.
   Report fixed-region RGB error, mask overlap and geometry together; capture
   coverage alone is not a visual score.
6. Preserve static behavior and visible notices, then calibrate Windows
   appearance/palettes with measured references. Test fresh dependency edits
   and permissions on the standalone caller's filesystem.
7. Add and validate Windows preview-shell integration separately. The
   macOS scoped-bookmark/XPC authorization solution is not a Windows design.

The concrete blocker for Windows refinement is a Windows execution/capture
environment with the required SDKs, fonts and native 4D development reference.
This handover prepares the code boundary and tests; it does not resolve that
environmental requirement.
