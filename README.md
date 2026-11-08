# 4D Quick Look

Quick Look previews for 4D's proprietary files in Finder. Press Space on a
file to see what is inside instead of a generic icon.

| File | What the preview shows |
|---|---|
| `.4DD` data file | tables ranked by records (the largest eight, the rest folded into "Other"), field types, the database UUID the structure must match, sort/search language and wildcard rule, index engine versions, journal file path, storage use, whether it was closed cleanly or needs repair, and for [encrypted data files](https://developer.4d.com/docs/commands/encrypt-data-file) which tables are encrypted |
| `.4DB` binary structure | tables ranked by fields, field types, the number of relations, the database UUID, sort/search settings, journaling |
| `.4DCatalog` XML catalog | a diagram-first view of tables, field types, primary keys, hidden fields, and relations; counts, database UUID, sort/search language, schemas, and encryptable tables tucked into "Catalog details" |
| `.4DSettings` settings file | syntax-highlighted XML source with indentation and line breaks preserved |
| `.4si` import/export settings | ordered field cards with readable types, summary cards, and borderless settings and options |
| `.4DProject` project file | syntax-highlighted JSON source with indentation and line breaks preserved |
| `.4df` saved query | condition cards with table/field numbers, comparison labels, AND/OR/EXCEPT connectors, saved values, and selection destination; original JSON folded below |
| `.4dm` method / class source | syntax-highlighted UTF-8 source with line numbers, line count and file size |
| `.4DForm` form | approximate macOS form layout, page 0 plus selectable numbered pages, and Classic / Liquid Glass light and dark appearances with local stylesheets and JSON pointers |

Even a 220 MB data file previews in about 30 ms, because only header blocks are read.

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
The viewer's appearance is used initially; an explicit form `colorScheme`
is respected. Liquid Glass buttons and dropdowns use the documented
27-point rounded-control threshold and measured native height/font variants;
tall dropdowns retain a rectangular fallback. Classic uses its own automatic
font thresholds, default toggle heights and accented dropdown arrow area.

Stylesheets load in 4D order: `Project/Sources/styleSheets.css`,
`styleSheets_mac.css`, then the form's `css` references (Windows-only
references are ignored). Supported selectors are object types, names,
classes, compounds, universal and attribute selectors; nested
`prefers-color-scheme` / `form-theme` media queries are evaluated for
each appearance. JSON properties beat ordinary CSS, while `!important`
can override them. Common web-property aliases are mapped to 4D names,
including styles on listbox columns, headers and footers. Unsupported
selectors, at-rules and unavailable dependencies produce preview notices.

Recursive `$ref` pointers support local and external JSON documents,
RFC 6901 escapes, array indices, and local-property overrides. Relative
paths retain the referring document's base. Local pictures, button icons
and their `_dark` variants are embedded; picture-button/popup sprite sheets
show their first frame. Raster images are converted to bounded PNGs.
Basic passive SVG artwork is supported; active content, external references
and unsupported SVG constructs are rejected.
Dependencies are confined to the conventional project's package folder,
or the selected form's folder for standalone files, including after symlink
resolution. `/PROJECT`, `/SOURCES`, `/RESOURCES` and `/PACKAGE` are mapped
only when a project is discoverable; runtime `/DATA` and `/LOGS` paths,
network paths and variable pictures are not loaded.
**Finder's Quick Look sandbox may grant access only to the selected file**:
project CSS, external templates and pictures are best-effort, with notices
when inaccessible. The CLI uses the same logic but can normally read them.

Native controls are approximations, not pixel-identical AppKit widgets.
Bound inputs, dropdowns, combos and dynamic tabs display their saved
expressions rather than inventing runtime values. Static tab labels and
listbox headers are shown; listbox bodies show expression placeholders,
not records. Subforms, inherited forms, web areas, Write Pro, View Pro and
plug-ins are placeholders or explicitly unexpanded. Methods, dynamic
styling, translations and application-level appearance settings are not
executed or resolved. Native animation, focus rings and Liquid Glass
materials are not simulated.

The rendering reference combines the canonical
[4D form](https://github.com/miyako/skills/tree/dist/skills/4dform),
[CSS](https://github.com/miyako/skills/tree/dist/skills/4dcss) and
[CLI](https://github.com/miyako/skills/tree/dist/skills/4dcli) skills with
captures from 4D 21 R4 build 100208, 21.2 LTS build 100653 and
21 R5 build 100156 on macOS 26.7. Named-form
[`FORM SCREENSHOT`](https://developer.4d.com/docs/commands/form-screenshot)
captures ignore CSS; a loaded-form screenshot and printed forms can apply
it, but neither substitutes for a live dialog. The measured light
Liquid Glass geometry informs the preview's discrete sizes, one listbox
expression row, page-zero layering and asymmetric single-line input
rounding. LTS tool4d supplied Classic light/dark geometry and palettes;
full R5 `4D.app` supplied Liquid Glass light/dark editor-template captures,
including dark colors and SVG artwork that tool4d did not reproduce reliably.
Those template palettes inform the preview. A minimal R5 live dialog was
also captured in both schemes using a blocking `DIALOG` and an `onTimer`
form method; its transparent canvas and runtime input appearance differ
from named-form output.

Some engines crashed or failed to terminate after writing the captures;
the resulting PNGs were decoded and inspected, but these were not clean
CLI runs. Full LTS applications crashed before startup, and the bounded R4 GUI
[`FORM EDIT`](https://developer.4d.com/docs/commands/form-edit) attempt did
not reach its startup method. All four appearances remain approximations,
not native-match or application-lifecycle guarantees.

Form JSON is limited to 4 MiB, 64 nesting levels and 100,000 values;
duplicate keys are rejected to avoid ambiguous paint order. Dependencies
are limited to 64 regular files, 4 MiB each and 16 MiB total; pointer
expansion is bounded to 100,000 values and depth 64. CSS is limited to
5,000 rules, 20,000 declarations per file, 16 nested media blocks and
1,000,000 object/rule matches. At most 16 numbered pages, 1,000 objects
per appearance, 64 listbox columns, and 200 grid rows are drawn; canvases
are cropped at 8,192 points per side. Images are limited to 32 megapixels
and 2,048-pixel raster thumbnails, with a 24 MiB embedded-image budget.
Original JSON is retained in analysis output and displayed up to 256 Ki
characters in its disclosure. Parsing is not full 4D schema validation.

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

Quick Look has little room, so the preview leads with what matters to a user
or developer, and every block has a fixed size: a file with 500 tables takes
the same summary space as one with 5 (hover a bar for details).

The `.4DB` and `.4DD` field-type charts use the catalog's original inline SVG
icons and matching light/dark colors. The eight family counts stay unchanged;
Text/UUID show distinct icons for the types present; Date/Time use a single
calendar icon, including time-only charts. Unknown types
keep a neutral question-mark icon and the "Other" count.

Catalog previews lead with the diagram, without summary charts or relation
lists. Metadata remains available in a collapsed **Catalog details** disclosure.
Catalog diagrams are self-contained SVG with no scripts or network requests.
They reuse saved structure-editor positions when practical and fall back to a
deterministic layout otherwise. Scroll within the diagram and hover names or
connectors for details. Table headings are centered; relation names appear
only in connector tooltips to keep the diagram uncluttered.
Primary-key field names are underlined, indexed field names are bold, and
hidden names are italic; these styles combine when multiple flags apply.
Cards use compact 21-point field rows and original inline SVG type icons;
the full type and Alpha length remain in hover details. Card widths are
measured from the displayed names, so valid 31-character names are shown in
full, including wide or non-Latin text, without padding every card to the
same width. No proprietary 4D image assets are bundled.
Previews show at most 24 tables, eight fields per table
(prioritizing primary keys and joins), and 64 relations. Per-table field
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
    Text/                XML .4DSettings / JSON .4DProject source text,
                         structured .4si import/export settings
    Query/               JSON .4df saved query conditions and metadata
    Method/              bounded UTF-8 .4dm reader and regex lexer
    Form/                ordered JSON, bounded pointers/dependencies,
                         macOS theme-aware 4D stylesheet cascade
  FourDRender/           rendering layer: model -> Report -> HTML
    Report.swift         generic page model (stats, badges, tables, bars, disclosures)
    *Presenter.swift     one presenter per model kind
    HTMLRenderer.swift   the only place that knows about HTML/CSS
    PreviewPipeline.swift
  FourDQuickLookExtension/  data-based QLPreviewProvider (returns HTML)
  FourDQuickLookHost/    minimal host app (extensions must live inside an app)
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

## Build from source

```bash
scripts/build.sh --register
```

This builds a universal (arm64 + x86_64) release, ad-hoc signs it, and
registers it with Launch Services and Quick Look. To install it for good, copy
`build/4D Quick Look.app` to `/Applications` and open it once. If Finder still
shows the old preview, run `qlmanage -r`.

To sign with a Developer ID locally (hardened runtime and secure timestamp
are added automatically):

```bash
SIGN_IDENTITY="Developer ID Application: …" scripts/build.sh
```

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
```

The test fixtures in `Tests/FourDFileKitTests/Fixtures` (a data file with
encryptable tables, before and after `Encrypt data file`) are built from the
small project in `Tests/Fixtures/encfixture` by `scripts/make-fixtures.sh`.

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
