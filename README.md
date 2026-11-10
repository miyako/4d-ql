# 4D Quick Look

English | [日本語](README.ja.md)

Quick Look previews for 4D's proprietary files in Finder. Press Space on a
file to see what is inside instead of a generic icon.

| File | What the preview shows |
|---|---|
| `.4DD` data file | tables ranked by records (the largest eight, the rest folded into "Other"), field types, the database UUID the structure must match, sort/search language and wildcard rule, index engine versions, journal file path, storage use, whether it was closed cleanly or needs repair, and for [encrypted data files](https://developer.4d.com/docs/commands/encrypt-data-file) which tables are encrypted |
| `.4DB` binary structure | tables ranked by fields, field types, the number of relations, the database UUID, sort/search settings, journaling |
| `.4DCatalog` XML catalog | a diagram-first view of tables, field types, primary keys, hidden fields, and relations; counts, database UUID, sort/search language, schemas, and encryptable tables tucked into "Catalog details" |
| `.4DSettings` settings file | syntax-highlighted XML source with indentation and line breaks preserved |
| `.4DLink` database shortcut | syntax-highlighted XML source with indentation and line breaks preserved |
| `.4DPreferences` preferences file | syntax-highlighted XML source with indentation and line breaks preserved |
| `.4si` import/export settings | ordered field cards with readable types, summary cards, and borderless settings and options |
| `.4DProject` project file | syntax-highlighted JSON source with indentation and line breaks preserved |
| `.4df` saved query | condition cards with table/field numbers, comparison labels, AND/OR/EXCEPT connectors, saved values, and selection destination; original JSON folded below |
| `.4st` saved set | selected-record count, address-span coverage and distribution, contiguous record-number ranges, and saved current record; empty/full-page compression decoded |
| `.4qr` Quick Report | list/cross-table design template with saved widths, titles, fonts, colors, borders, header/footer text, sorts, subtotals and grand totals; no database or 4D runtime required |
| `.4lbp` label | native XML label artwork and sheet layout, saved text, shapes, raster pictures, print order, margins, gaps and project table-form references |
| `.4dm` method / class source | syntax-highlighted UTF-8 source with line numbers, line count and file size |
| `.4DForm` form | approximate macOS form layout, page 0 plus selectable numbered pages, Classic / Liquid Glass light and dark appearances, local stylesheets, JSON pointers, static inherited/subforms and XLIFF labels |

Even a 220 MB data file previews in about 30 ms, because only header blocks are read.

Saved-set previews decode the confirmed little-endian `70D4` format, including
32,768-record empty/full pages and bitmaps, without 4D installed. Record numbers
are zero-based storage addresses, not field values or selection positions.
Counts and distribution cover the whole set; the first 200 contiguous ranges
are shown when analysis completes. The decoder streams bitmap data in 256 KiB
chunks, with no arbitrary file-size cutoff. The default 1.5-second analysis
budget produces an explicitly partial preview if exhausted: counts become
lower bounds, unexamined addresses remain unknown, and unfinished ranges are
marked. CLI `--thorough` removes the time budget, not the output bounds.
Historical big-endian sets and unknown page encodings are reported explicitly
rather than guessed. See [binary format evidence and limits](docs/4ST-FORMAT.md).

Quick Report support is experimental and covers the chunk-based Unicode format
observed in 4D 18–21 (stream versions 25–28), in either byte order.
These are design previews, not live/printed reports: field references use table
and field numbers; tokenized formulas, records, total macros, pictures,
pagination and native printer settings are not evaluated. See the
[binary-format evidence and fixture workflow](docs/QUICK-REPORT-FORMAT.md).

Label previews read the native XML `.4lbp` format used by the
[4D Labels component](https://github.com/4d/4D-Labels), not JSON or legacy
binary `.4lb` files. They show a static label design and inferred sheet layout;
fields, formulas, label methods and printer settings are not executed.
Saved table forms reuse the `.4DForm` renderer when a label resides within its
project's `Project/Sources` or `Resources` tree and the form name resolves
unambiguously. Missing forms and unsupported artwork produce preview notices.
See [format semantics and limits](docs/LABEL-FORMAT.md).

### Shared form rendering

This repository ships the macOS Quick Look app and extension. The independent
form-image CLI belongs to [4d-form](https://github.com/miyako/4d-form), which
consumes the public `FourDFileKit` and `FourDRender` libraries instead of
maintaining a second parser or calibrated renderer. The preliminary HTML/JSON-only
`fourdform` executable is not a Quick Look release product.

`FourDRender.FormRenderer` provides in-process HTML and versioned JSON without
4D, Quick Look, the hosting app or its XPC service. See the
[shared API and static-feature contract](docs/FORM-RENDERER.md) and the
[Windows handover](docs/WINDOWS-HANDOVER.md). The libraries also build on
Windows, where forms render with the Windows Classic and Fluent UI light/dark
appearances calibrated against 4D 21; select the platform with
`FormRenderer.render(url:preferredLanguages:platform:options:)`.

On macOS the Quick Look form preview also includes the Windows appearances
behind a macOS/Windows switch. Segoe UI cannot be redistributed, so where it
is not installed Windows text is measured and drawn with the embedded
[Selawik](https://github.com/microsoft/Selawik) font, Microsoft's open-source
substitute with Segoe UI's Latin advance widths; glyph shapes differ and
non-Latin text falls back to other fonts.

Import/export settings previews preserve field order (which can differ from field
numbers), display missing values explicitly, and retain unknown field types and
extra options. Summary cards show the table, selected field count, format, and
encoding above a compact, responsive grid of field cards in saved order (left to
right, then top to bottom), without order labels. Original type symbols have
hover and accessibility labels; unknown types remain visible as text. Names wrap
rather than being truncated, including 31-character names. Secondary
settings and options follow below as borderless key/value pairs.
XML is limited to 4 MiB, 20,000 elements, and 32 nesting levels;
malformed XML and custom entities are rejected without loading external entities.
Leading ASCII whitespace before an XML declaration is tolerated; formatting
warnings remain in JSON output rather than the preview.
The preview shows at most 500 fields and 500 option rows, with explicit omission
counts; JSON output retains the complete parsed configuration.

Method previews use an in-process regex lexer: no 4D installation, tool4d,
LSP server, JavaScript, or network access is required. Highlighting covers
comments, attributes headers, strings, numbers, date/time literals, keywords,
variables, table/field references, tokenized commands (`:C…`) and constants
(`:K…:…`), and call names. Untokenized commands are highlighted heuristically;
this is not semantic analysis or syntax validation. The token categories are
inspired by [miyako/language-4dm-zed](https://github.com/miyako/language-4dm-zed)
and its [tree-sitter grammar](https://github.com/miyako/tree-sitter-fourd).
Previews read at most 256 KiB and show at most 1,000 lines, with a visible
notice when truncated (including in CLI `--thorough` mode). UTF-8 BOMs and
Windows/classic Mac line endings are supported; invalid UTF-8 is reported.

Form previews use a self-contained SVG canvas, not a running 4D instance.
They preserve JSON object declaration order (paint order), include page 0
behind every numbered page, honor saved coordinates and form-size anchors,
and provide scrollable canvases and script-free page/appearance selectors.
Quick Look adds catalog-style, cursor-centered pinch zoom, a logarithmic
slider, +/− buttons, a 100% reset and drag-to-pan over the form canvas.
Zoom ranges from 1% to 800% and persists across platform, appearance and page
switches without scaling the selectors or metadata. Ordinary scrolling remains
available; Control-scroll also zooms inside the canvas. Standalone HTML stays
script-free with 10%–200% zoom presets.
Text uses CoreText shaping and word-boundary line breaks rather than
summing individual character widths. Composed characters, explicit blank
lines and font traits are preserved; text remains clipped to saved bounds.
The text face is selected consistently for measurement and WebKit SVG output.
The viewer's appearance is used initially; an explicit form `colorScheme`
is respected. Liquid Glass buttons and dropdowns use the documented
27-point rounded-control threshold and measured native height/font variants;
tall dropdowns retain a rectangular fallback. Classic uses its own automatic
font thresholds, default toggle heights and accented dropdown arrow area.
Classic and Liquid Glass tabs use compact, centered segments and the native editor
template's initial selection; that is not a computed runtime value.
Automatic group titles use the measured 10-point font; the main font theme
uses 13-point bold, with explicit font size and weight taking precedence.
Group frames reserve the title band, align captions across the whole frame,
and do not invent captions for untitled groups. Saved text/input padding and
explicit top/middle/bottom alignment are applied inside the text viewport;
automatic alignment retains the native-style defaults. These text/input
properties were introduced in 21 R5, so older native references cannot verify
them. Disabling wordwrap preserves explicit line breaks while clipping long
lines horizontally. Listbox headers use separate native-style resize grips;
footers retain the input background rather than the header background.
Rounded text borders expand outside the saved text bounds; single-line input
rounding is capped by the control height. Input text starts at the saved
padding without an extra invented inset. Caption/icon layout honors
`textPlacement` and `imageHugsTitle`, with the measured default icon-above-title
layout. Justified wrapped paragraphs expand word spaces, not their last lines.

Stylesheets load in 4D order: `Project/Sources/styleSheets.css`,
`styleSheets_mac.css`, then the form's `css` references (Windows-only
references are ignored; Windows rendering uses `styleSheets_windows.css`
and Windows-only references instead). Supported selectors are object types, names,
classes, compounds, universal and attribute selectors; nested
`prefers-color-scheme` / `form-theme` media queries are evaluated for
each appearance. JSON properties beat ordinary CSS, while `!important`
can override them. Common web-property aliases are mapped to 4D names,
including styles on listbox columns, headers and footers. Unsupported
selectors, at-rules and unavailable dependencies produce preview notices.
Within one analysis, stylesheets are parsed once per canonical dependency
path and reused across static contexts; repeated references retain cascade order.

Recursive `$ref` pointers support local and external JSON documents,
RFC 6901 escapes, array indices, and local-property overrides. Relative
paths retain the referring document's base. Local pictures, button icons
and their `_dark` variants are embedded; picture-button/popup sprite sheets
show their first frame. Raster images are converted to bounded PNGs.
Basic passive SVG artwork is supported; active content, external references
and unsupported SVG constructs are rejected.
Static pictures with omitted display format retain their intrinsic size and
are centered in the full object rectangle before container clipping; explicit
scaled/proportional formats retain their saved behavior.
Dependencies are confined to the conventional project's package folder,
or the selected form's folder for standalone files, including after symlink
resolution. `/PROJECT`, `/SOURCES`, `/RESOURCES` and `/PACKAGE` are mapped
only when a project is discoverable; runtime `/DATA` and `/LOGS` paths,
network paths and variable pictures are not loaded.
Static inherited forms contribute their background and initial-page objects
behind local objects without replacing the receiving form's properties.
Statically named project subforms show their background and initial page at
container-local coordinates, clipped to the container. Each source retains its
own CSS, pointer, picture and localization context. Cycles, dynamic references
and unavailable forms remain visible as notices or placeholders.
Inline object-valued form references are approximated with an explicit
noncanonical-schema notice: dynamic 4D commands accept object descriptions,
but saved-form schema references are strings and native named captures may
paint a placeholder instead.
Project XLIFF labels resolve named, numeric and object-name references using
preferred-language specificity and documented fallback folders. Ambiguous or
missing translations retain the reference with a notice; no localization
method is executed.

**Finder's Quick Look sandbox grants access only to the selected file** by
default. The CLI uses the same analysis but can normally read project resources.
Unavailable resources and unsupported features produce a visible warning
above the canvas, with individual explanations in Preview notices.

Native controls are approximations, not pixel-identical AppKit widgets.
Bound inputs, dropdowns, combos and dynamic tabs display their saved
expressions rather than inventing runtime values. Static tab labels and
listbox headers are shown; listbox bodies show expression placeholders,
not records. Dynamic or unavailable subforms, web areas, Write Pro, View Pro and
plug-ins remain placeholders. Methods, dynamic styling and application-level
appearance settings are not executed or resolved. Native animation, focus rings and Liquid Glass
materials are not simulated.

### Authorizing project resources in Finder

A team-signed build on macOS 13 or later provides **Choose Desktop...**,
**Choose Documents...**, and **Choose Downloads...** shortcuts in the hosting
app's welcome window. Each opens a folder-selection panel; confirm the folder
to grant read-only access to all projects beneath it. **Choose another folder...**
lets you authorize any other projects folder or an individual package folder
containing `Project` and `Resources`, not the `Project` subfolder.
Only the sandboxed service retains a read-only folder bookmark.
The Quick Look extension does not receive a filesystem exception or run 4D.
Grants persist after the app closes. Launch **4D Quick Look** again to add more
paths; folder authorization is unavailable from the Quick Look preview window.
**Remove folder authorizations...** revokes all saved folder grants.

Authorized previews use the app's private, team-owned shared container.
For each Finder request, an embedded XPC service analyzes the current form and
its bounded dependencies, or the catalog and its sibling editor layout, then
returns self-contained HTML over IPC. The
extension neither writes to the shared container nor launches the hosting app.
Requests and replies are tied
to a fresh nonce, selected-file content hash and renderer build. Forms retain
their 4 MiB source limit; catalogs retain their 32 MiB source limit. A missing helper,
authorization failure, changed source or timeout produces a visible notice and
the selected-file-only preview, never a silently stale project preview.
Role-specific XPC sessions check the signing identity before admission;
only the hosting app can authorize or revoke projects. The preview role is
read-only. Each service reuses two listeners, limits work to 32 operations,
and caps HTML replies at 32 MiB; the client has a four-second deadline,
including its bounded selected-source hash and both XPC calls.

Actual Finder checks verified persistence after closing the hosting app,
automatic service activation, static composition/XLIFF, and revocation.
Changing CSS, an external JSON template and an SVG changed the next Finder
preview while the selected form's checksum remained unchanged.

Do not grant Full Disk Access or broad access to other apps' data for this
feature. Ad-hoc builds leave project sharing disabled; they still preview the
selected file and support the development `fourdql` CLI. Signed macOS builds default to
the signing team's `<Team ID>.<bundle ID>.ProjectContext` app group. A custom
`PROJECT_GROUP` must be authorized by the signing configuration.

The rendering reference combines the canonical
[4D form](https://github.com/miyako/skills/tree/dist/skills/4dform),
[CSS](https://github.com/miyako/skills/tree/dist/skills/4dcss) and
[CLI](https://github.com/miyako/skills/tree/dist/skills/4dcli) skills with
captures from 4D 20.8 build 101985, 21.2 LTS build 100653,
21 R4 build 100208 and 21 R5 build 100156 on macOS 26.7. Named-form
[`FORM SCREENSHOT`](https://developer.4d.com/docs/commands/form-screenshot)
captures ignore CSS; a loaded-form screenshot and printed forms can apply
it, but neither substitutes for a live dialog. The measured light
Liquid Glass geometry informs the preview's discrete sizes, one listbox
expression row, page-zero layering and asymmetric single-line input
rounding. Full LTS applications and LTS tool4d supplied Classic light/dark
geometry and palettes; full R4/R5 `4D.app` supplied Liquid Glass light/dark
editor-template captures. Those template palettes inform the preview.
Live dialogs were also captured in both schemes with all four full
applications, using both the canonical `DIALOG` / `CALL FORM` chain and a
blocking `DIALOG` with an `onTimer` form method. Runtime input appearance
and transparent canvas regions differ from named-form output.

Early crashes and timeouts were inconclusive. After rebooting, serial
retries produced decoded screenshots, nonblank PDFs and clean exits;
[`FORM EDIT`](https://developer.4d.com/docs/commands/form-edit) opened
editor windows in all four full applications, with window screenshots
retained as evidence. The probe setup must create
`Project/Sources/dependencies.json` containing `{"dependencies":{}}`
before launching 4D to prevent the legacy-component import dialog.
Omitting that preflight step blocked the initial 21.2 GUI retries;
adding the file alone allowed the original compatibility-version project
to complete. No engine-capability conclusions are drawn from the
interrupted runs.

In the retried R4/R5 tool4d probes, SVG decoding returned zero dimensions
and dark named-form output remained partly light; full GUI captures
rendered the same SVG and dark controls. These observations are specific
to the tested builds, inputs and capture modes. All four preview
appearances remain approximations, not pixel-identical native rendering.

Form JSON is limited to 4 MiB, 64 nesting levels and 100,000 values;
duplicate keys are rejected to avoid ambiguous paint order. Dependencies
are limited to 64 regular files, 4 MiB each and 16 MiB total; pointer
and static-form expansion are bounded to 100,000 values and depth 64.
Embedded objects share the 1,000-object appearance limit. XLIFF parsing is
limited to 20,000 XML nodes, depth 64 and 1 MiB of text, with external entities
disabled. CSS is limited to
5,000 rules, 20,000 declarations per file, 16 nested media blocks and
1,000,000 object/rule matches. At most 16 numbered pages, 1,000 objects
per appearance, 64 listbox columns, and 200 grid rows are drawn; canvases
are cropped at 8,192 points per side. Images are limited to 32 megapixels
and 2,048-pixel raster thumbnails, with a 24 MiB embedded-image budget.
Text shaping is capped at 4,096 UTF-16 units and 100 lines per label,
without splitting a composed character at the input boundary.
Original JSON is retained in analysis output and displayed up to 256 Ki
characters in its disclosure. Parsing is not full 4D schema validation.

### Form visual benchmark

`Tests/FourDFileKitTests/Fixtures/FormBenchmarkProject` contains four self-authored forms:
Typography, Controls, ContactInvoice and References. Two pages in each
of the four appearances produce 32 cases, with per-object crops for
typography, controls, listbox headers/footers and project references.
No external application's form source is included.

```sh
python3 scripts/form-benchmark.py --validate-only
caffeinate -di python3 scripts/form-benchmark.py --output /absolute/artifacts/form-benchmark
python3 scripts/form-benchmark.py --output /absolute/artifacts/form-benchmark \
  --fourdql build/fourdql --compare-only
```

The macOS harness uses full 4D applications serially, the installed form
schema/validator, a WebKit snapshot helper and Pillow. It creates private
writable projects with the dependency manifest before launching an engine;
only those copies normalize compatibilityVersion to 2100. Committed forms
and project references remain unchanged. `--compare-only` reuses verified
native captures; it never launches 4D. Engine paths, forms and themes can
be selected with the options shown by `--help`.

`gallery.html` and `metrics.json` contain native/preview comparisons,
foreground bounds, mask overlap and RGB error. A complete 32-case run
means capture coverage, not pixel equivalence or a passing visual score.
Named screenshots ignore CSS; known CSS/pointer capture-context gaps
remain visible but are excluded from comparable rankings. Loaded-form
font getters and actual Finder checks are separate evidence, not
interchangeable screenshot modes. Keep the desktop unlocked for GUI checks;
`caffeinate -di` temporarily prevents idle display/system sleep for the command's
lifetime, without changing settings or overriding manual/policy-enforced locks.

Real-HDI calibration additionally covers pinned revisions of
`4d-depot/HDI_Buttons`, `HDI_RoundedCorner` and
`HDI_FormObj_VericalAlignAndPadding`. The external corpus is downloaded only
to the chosen artifact directory, not vendored into this repository. Native
copies exclude upstream methods/components and use only our capture method.
The 24 named cases, one separate safe loaded-CSS companion and six R5 padding
probe cases distinguish saved properties from runtime-only changes. LTS
captures cannot verify R5 text/input alignment, so those regions are excluded
by actual engine version. Loaded-offscreen placement is not treated as live
dialog placement. Arial's measured 15/17-point line advances at 13/15-point
font sizes do not override other fonts' metrics.

```sh
caffeinate -di python3 scripts/form-hdi-benchmark.py --output /absolute/artifacts/hdi
python3 scripts/form-hdi-benchmark.py --output /absolute/artifacts/hdi \
  --fourdql build/fourdql --compare-only
caffeinate -di python3 scripts/form-padding-probe.py \
  --output /absolute/artifacts/padding
python3 scripts/form-padding-probe.py --output /absolute/artifacts/padding \
  --fourdql build/fourdql --compare-only
```

### What is shown, and what is not

Saved-query previews decode version 3 UTF-8 JSON (including BOMs), limited
to 4 MiB. They show at most 200 condition cards; the original JSON and CLI
JSON output retain all lines and properties, including unfamiliar inputs.
Table/field names and types are not present in standalone `.4df` files.
Type-dependent criterion codes therefore show alternatives rather than
guessing a field type; unknown codes remain labeled with their saved number.
Values are displayed as saved, not executed or interpreted as 4D formulas.
Only the version number accompanies the Original JSON disclosure; additional
metadata is available in the JSON rather than explanatory footnotes.
Other versions show a notice and the original JSON; legacy binary queries
and malformed JSON report an error.

Quick Look has little room, so summary charts stay compact: a data file with
500 tables takes the same summary space as one with 5 (hover a bar for details).
Catalog diagrams instead expand their scrollable canvas to include every table.

The `.4DB` and `.4DD` field-type charts use the catalog's original inline SVG
icons and matching light/dark colors. The eight family counts stay unchanged;
Text/UUID show distinct icons for the types present; Date/Time use a single
calendar icon, including time-only charts. Unknown types
keep a neutral question-mark icon and the "Other" count.

Catalog previews lead with the diagram, without summary charts or relation
lists. Metadata remains available in a collapsed **Catalog details** disclosure.
Catalog diagrams are self-contained SVG with no scripts or network requests.
They reuse saved structure-editor positions when practical and fall back to a
deterministic grid that grows with the number of tables otherwise. Positions
may be embedded in `.4DCatalog` XML or stored by table name in the sibling
`catalog_editor.json` tables object. Valid external coordinates take precedence;
missing or invalid entries retain embedded positions. Both numeric coordinates
and 4D's string-valued coordinates are supported. Unreadable, malformed or
oversized editor files produce parser notes rather than hiding the catalog.
The editor file is limited to 4 MiB, depth 64 and 100,000 JSON values, must be a
regular file, and cannot resolve outside the catalog folder through a symlink.
In Finder, authorize the containing project folder in the hosting app so the
preview service can read this sibling file; without access the embedded layout
or automatic grid remains available.
Finder uses a view-based Quick Look extension with an owned `WKWebView`.
Pinch over the diagram for continuous, cursor-centered zoom, use the logarithmic
slider or +/- buttons, and select 100% to reset. Zoom ranges from 1% to 800%;
only the SVG and its scrollable extent scale, not the surrounding preview.
Two-finger scrolling pans the diagram; dragging its canvas also pans.
The controls support keyboard navigation. Magnification outside a diagram
does not zoom the page.

The viewer installs its own interaction code in an isolated WebKit content world.
Document-supplied JavaScript is disabled, external navigation and resource loads
are blocked, and no project-folder base URL or native script bridge is exposed.
The sandboxed preview extension requires the network-client entitlement for
WebKit subprocess communication even though preview content cannot load remote
resources. The host and project service do not receive that entitlement.
CLI HTML remains script-free with 10%-200% zoom presets as a portable fallback.
Scroll within the diagram and hover names or
connectors for details. Table headings are centered; relation names appear
only in connector tooltips to keep the diagram uncluttered.
Primary-key field names are underlined, indexed field names are bold, and
hidden names are italic; these styles combine when multiple flags apply.
Cards use compact 21-point field rows and original inline SVG type icons;
the full type and Alpha length remain in hover details. Card widths are
measured from the displayed names, so valid 31-character names are shown in
full, including wide or non-Latin text, without padding every card to the
same width. No proprietary 4D image assets are bundled.
Previews show every table and every resolved relation on a canvas sized to the
full layout, including saved layouts beyond 12,000 points. Cards show up to
eight fields per table (prioritizing primary keys and joins). Per-table field
omissions are labeled on the cards; omission totals and the legend remain in
the diagram's tooltip/accessibility description, not above the diagram.
The JSON output retains all parsed tables, fields, and relations. XML catalogs
are limited to 32 MiB, 200,000 elements, and 128 nesting levels; malformed XML
and custom entity declarations are rejected. The standard 4D external DOCTYPE
is accepted without loading its DTD.

* **Shown:** contents (tables, records, fields), what decides whether the
  file opens and behaves as expected (database UUID, language, `@` wildcard
  rule, index engine markers, journal, encryption), and a little reference
  information (format version, storage, byte order).
* **Japanese collation options** (ICU, secondary/quaternary strength, hiragana
  first, …) appear only for Japanese without ICU, the only case where they apply.
* **Not shown:** engine internals (block size, flush and header counters,
  LCIDs, sequence counts, per-field lists). They remain in `fourdql --json`.

## Layout

```
Sources/
  FourDFileKit/          analyzer layer: bytes -> typed Codable model (no UI)
    Core/                ByteSource (pread), BinaryReader (bounds-checked),
                         FileAnalyzer protocol, AnalyzerRegistry
    DB4D/                the shared .4DD/.4DB container format
    Catalog/             .4DCatalog XML definitions and relation references
    Text/                XML .4DSettings / .4DLink / .4DPreferences and JSON .4DProject source text,
                         structured .4si import/export settings
    Query/               JSON .4df saved query conditions and metadata
    Set/                 binary .4st membership, compressed pages and bounded ranges
    QuickReport/         bounded, endian-aware binary .4qr report templates
    Method/              bounded UTF-8 .4dm reader and regex lexer
    Form/                ordered JSON, bounded pointers/dependencies,
                         macOS stylesheet cascade, static forms and XLIFF
  FourDRender/           rendering layer: model -> Report -> HTML
    Report.swift         generic page model (stats, badges, tables, bars, disclosures)
    *Presenter.swift     one presenter per model kind
    HTMLRenderer.swift   the only place that knows about HTML/CSS
    PreviewPipeline.swift
  FourDQuickLookExtension/  view-based QLPreviewingController with project authorization
  FourDQuickLookUI/       owned WKWebView and isolated canvas zoom/pan controls
  FourDProjectAccess/    read-only authorization and bounded shared-preview exchange
  FourDQuickLookHost/    hosting app and sandboxed project-preview helper
  fourdql/               CLI using the same pipeline
Support/                 Info.plist templates, entitlements
scripts/build.sh         builds and signs "4D Quick Look.app"
```

The layers only meet at two seams:

* **Analyzer → presenter**: an `AnalysisModel` with a `kind` string (e.g. `db4d.data`).
* **Presenter → renderer**: a `Report`.

So better presentation means editing `HTMLRenderer` (all files benefit) or a
presenter (one file family), and a parser fix never touches either.

## Adding a file type

1. Write a `FileAnalyzer` in `FourDFileKit` that returns your own `AnalysisModel`.
   List the UTIs it handles (4D.app exports many: `com.4d.4d.catalog`,
   `com.4d.4d.method`, `com.4d.4d.form`, `com.4d.4d.journalFile`,
   `com.4d.4d.index-data`, …).
2. Register it in `AnalyzerRegistry.default`.
3. Write a `ReportPresenter` in `FourDRender` and register it in `PresenterRegistry.default`.

`QLSupportedContentTypes` in the extension's Info.plist is generated from the
registry at build time (`fourdql --content-types`), so there is no list to keep in sync.

## Install

Download the `.dmg` from [Releases](https://github.com/miyako/4d-ql/releases),
drag **4D Quick Look** to Applications, and open it once so macOS registers the
preview extension. The app is signed with a Developer ID and notarized. If
Finder still shows the old preview, run `qlmanage -r`.

### Upgrading

Quick Look uses whichever registered copy of the extension it finds, and an
older copy keeps serving previews after the new one is installed. To upgrade:

1. Replace the app in `/Applications`, then delete any other copies (for example
   in Downloads) and eject the mounted DMG.
2. Open the new app once.
3. Restart the old preview processes and reset Quick Look (or log out and back in):

   ```sh
   pkill -f FourDQuickLookExtension; pkill -f FourDProjectPreviewService
   qlmanage -r; qlmanage -r cache
   ```

4. Check that a single, current copy is registered:

   ```sh
   pluginkit -mAvvv -i com.github.miyako.FourDQuickLook.Preview
   ```

   To remove a stale entry, run `pluginkit -r "<path to>/4D Preview.appex"`, then
   delete that copy.

## Build from source

```bash
scripts/build.sh --register
```

This builds a universal (arm64 + x86_64) release, ad-hoc signs it, and
registers it with Launch Services and Quick Look. To install it for good, copy
`build/4D Quick Look.app` to `/Applications` and open it once. If Finder still
shows the old preview, run `qlmanage -r`. The `build/` copy stays registered
after you install a release, and Quick Look may keep using it; unregister it as
described in [Upgrading](#upgrading).

To sign with a Developer ID locally (hardened runtime and secure timestamp
are added automatically):

```bash
SIGN_IDENTITY="Developer ID Application: …" scripts/build.sh
```

Team signing enables project-folder authorization without changing the sandbox
or requiring 4D. The build derives the macOS app-group prefix from the signing
identity; set `PROJECT_GROUP` only when using another authorized group.

## Releasing

Releases are built on GitHub's hosted macOS runners:

* `.github/workflows/ci.yml` runs the tests and an ad-hoc build on every push and pull request.
* `.github/workflows/bump-version.yml` offers **patch** (default), **minor**, and
  **major** in **Actions > Bump version > Run workflow**. It increments the
  highest `vX.Y.Z` tag, resetting lower components for minor/major bumps,
  tags the selected branch's checked-out commit, and starts **Build & Release**.
  No source version fields need editing. From the CLI:

  ```bash
  gh workflow run bump-version.yml -f mode=patch
  ```

  Bumps are serialized to avoid competing version tags. If the tag was pushed
  but starting the release failed, rerun `release.yml` against that tag rather
  than bumping again.
* `.github/workflows/release.yml` runs on a `vX.Y.Z` tag. It tests, builds
  with the tag's version, signs with Developer ID, notarizes and staples the
  app, and publishes `4D-QuickLook-X.Y.Z.dmg` and `.zip`. To release:

  ```bash
  git tag v0.2.0 && git push origin v0.2.0
  ```

  To rebuild an existing tag: `gh workflow run release.yml -f tag=v0.2.0`.

The bump workflow explicitly dispatches the release because tag pushes made
with GitHub's built-in token do not trigger other workflows. It needs
`contents: write` and `actions: write`; no additional token secret is required.

The release workflow needs six repository secrets: `APPLE_DEVELOPER_ID_CERTIFICATE` (base64
.p12), `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`,
`NOTARYTOOL_APPLE_ID`, `NOTARYTOOL_TEAM_ID` and `NOTARYTOOL_PASSWORD`.

## Developing

```bash
swift build && .build/debug/fourdql file.4DD            # text summary
.build/debug/fourdql --json file.4DD                    # analyzer output
.build/debug/fourdql --html file.4DD > preview.html     # exactly what Quick Look shows
.build/debug/fourdql --html catalog.4DCatalog > catalog.html
FOURD_SAMPLES=/path/to/samples swift test               # runs every sample through the pipeline
scripts/make-fixtures.sh                                # regenerate test fixtures (needs tool4d)
bash scripts/make-set-fixtures.sh                       # regenerate controlled saved sets (tool4d 21 R5)
```

The test fixtures in `Tests/FourDFileKitTests/Fixtures` (a data file with
encryptable tables, before and after `Encrypt data file`) are built from the
small project in `Tests/Fixtures/encfixture` by `scripts/make-fixtures.sh`.

To exercise an installed development extension through actual Finder:

```bash
scripts/build.sh --register
swiftc scripts/finder-form-preview.swift -o build/finder-form-preview
caffeinate -di build/finder-form-preview /path/to/form.4DForm /path/to/finder-preview.png
# Require renderer-specific visible content, not just a nonblank screenshot:
caffeinate -di build/finder-form-preview /path/to/catalog.4DCatalog /path/to/catalog.png "STRUCTURE DIAGRAM"
```

The harness selects the specified file, opens Quick Look through Finder's File
menu, verifies that the selection remains unchanged, and captures only its
Finder preview window while it is foregrounded. Reused unnamed preview windows
are supported. The hosting app needs
Automation access to Finder and System Events, Accessibility for UI control,
and Screen Recording for the screenshot. Locked desktops and transparent OS
captures are rejected explicitly.
An optional third argument requires the supplied text to appear in screenshot
OCR and rejects known viewer error messages. Choose text from rendered content,
not the filename, so Finder's generic file fallback cannot pass the check.
Viewer or sandbox changes must also be exercised with a Developer ID-signed,
sandboxed build in Finder across multiple file families; unsandboxed WebKit
tests and signature verification alone do not establish that previews work.
Test both standalone and project-contained forms: Finder can deny neighboring
CSS, pointer targets and pictures even when the CLI renders them successfully.
Final development-build checks rendered both cases in Finder, exercised all four
appearance selectors and changed numbered pages. Missing project resources
produced the visible pre-canvas warning. On the tested macOS 26.7 host,
`qlmanage -p -o` still aborted inside ExtensionFoundation with a nil dictionary
key after unlocking; actual Finder previews and controls worked. The harness
uses Finder rather than treating that export-tool failure as a renderer failure.

## File format notes

The container format comes from
[miyako/DataAnalyzer](https://github.com/miyako/DataAnalyzer) (after JPR's 2015
tech note) and was checked against real files. Offsets are documented in the
source next to the code that reads them (`DB4DHeader.swift`, `DB4DContainer.swift`,
`DB4DCatalog.swift`). Points worth knowing:

* A `.4DB` uses the same container as a `.4DD`. User tables are defined in TDEF
  blocks in both. The `.4DB`'s own storage holds two system tables
  (`Res_DB4D_000000` for resources and `sch_DB4D_000000` for the schema).
* A data file keeps every historical definition of a table. The last one
  written is the current one; this matches `catalog.4DCatalog` in the tests.
* Field type codes are the catalog's `type` attribute. Type 10 is Alpha when a
  limiting length is set, and Text otherwise.
* The header dialect field is a Windows LCID (1041 = Japanese, 1036 = French).
* The database UUID in the header is identical in a structure file and its data files.
* Extra properties (xDAT) are a serialised value bag. The decoder in
  `ValueBag.swift` was reverse-engineered and stops cleanly at anything it does not recognise.
* Encryption (`Encrypt data file`, v17 R5+) applies only to records and blobs of
  tables marked encryptable (byte +202 of the table definition). Their blocks
  keep a clear-text header but change tag, `rec1` → `recx` and `blob` → `blbx`,
  so the preview reads each table's real state from its first record. Table
  definitions, record counts and the header stay unencrypted. An encrypted file
  also gains an `encryptedProofB64` extra property (a key check value). The
  data key is never needed and never asked for.

Relations (`[Table_1]Field_4 → [Table_2]ID`) are decoded and resource types
in a `.4DB` can be counted (`fourdql --json --thorough`), but the preview
shows neither.

Not decoded yet: index definitions beyond counts, record contents, and the
meaning of most resource types.

Catalog XML conventions and diagram presentation were informed by
[miyako/4d-catalog-diagram](https://github.com/miyako/4d-catalog-diagram) and
[miyako/4d-utility-structure-to-svg-converter-v2](https://github.com/miyako/4d-utility-structure-to-svg-converter-v2).
Relation endpoints and primary keys resolve by UUID first, then by unambiguous
name. Unknown field types remain labeled `Type n`; unknown XML elements are
ignored and unresolved references are reported in parser notes. A catalog's
`encryptable` flag describes the structure, not the encryption state of a
particular data file.

## License

MIT, see [LICENSE](LICENSE).

The embedded Selawik font (`Sources/FourDRender/FormSubstituteFontData.swift`,
generated unmodified from the Selawik 1.01 release by
`scripts/embed-selawik.py`) is © Microsoft Corporation and licensed under the
SIL Open Font License 1.1, see [ThirdParty/Selawik/OFL.txt](ThirdParty/Selawik/OFL.txt).
The app bundle and Quick Look extension ship that license as `Selawik-OFL.txt`.
