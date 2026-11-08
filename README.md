# 4D Quick Look

Quick Look previews for 4D's proprietary files in Finder. Press Space on a
file to see what is inside instead of a generic icon.

| File | What the preview shows |
|---|---|
| `.4DD` data file | tables ranked by records (the largest eight, the rest folded into "Other"), field types, the database UUID the structure must match, sort/search language and wildcard rule, index engine versions, journal file path, storage use, whether it was closed cleanly or needs repair, and for [encrypted data files](https://developer.4d.com/docs/commands/encrypt-data-file) which tables are encrypted |
| `.4DB` binary structure | tables ranked by fields, field types, relations (`[Table_1]Field_4 → [Table_2]ID`), resource types (forms, menu bars, picture library, …), the database UUID, sort/search settings, journaling |
| `.4DCatalog` XML catalog | a diagram-first view of tables, field types, primary keys, hidden fields, and relations; counts, database UUID, sort/search language, schemas, and encryptable tables tucked into "Catalog details" |
| `.4DSettings` settings file | syntax-highlighted XML source with indentation and line breaks preserved |
| `.4DProject` project file | syntax-highlighted JSON source with indentation and line breaks preserved |
| `.4dm` method / class source | syntax-highlighted UTF-8 source with line numbers, line count and file size |

Even a 220 MB data file previews in about 30 ms, because only header blocks are read.

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

### What is shown, and what is not

Quick Look has little room, so the preview leads with what matters to a user
or developer, and every block has a fixed size: a file with 500 tables takes
the same summary space as one with 5 (hover a bar for details).

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
    Text/                XML .4DSettings and JSON .4DProject source text
    Method/              bounded UTF-8 .4dm reader and regex lexer
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
* `.github/workflows/release.yml` runs on a `vX.Y.Z` tag. It tests, builds
  with the tag's version, signs with Developer ID, notarizes and staples the
  app, and publishes `4D-QuickLook-X.Y.Z.dmg` and `.zip`. To release:

  ```bash
  git tag v0.2.0 && git push origin v0.2.0
  ```

  To rebuild an existing tag: `gh workflow run release.yml -f tag=v0.2.0`.

It needs six repository secrets: `APPLE_DEVELOPER_ID_CERTIFICATE` (base64
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

Not decoded yet: index definitions beyond counts, record contents, and the
meaning of most resource types (they are shown by their four-character code).

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
