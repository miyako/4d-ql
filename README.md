# 4D Quick Look

Quick Look previews for 4D's proprietary files in Finder. Press Space on a
file to see what is inside instead of a generic icon.

| File | What the preview shows |
|---|---|
| `.4DD` data file | tables ranked by records (the largest eight, the rest folded into "Other"), field types, the database UUID the structure must match, sort/search language and wildcard rule, index engine versions, journal file path, storage use, whether it was closed cleanly or needs repair, and for [encrypted data files](https://developer.4d.com/docs/commands/encrypt-data-file) which tables are encrypted |
| `.4DB` binary structure | tables ranked by fields, field types, relations (`[Table_1]Field_4 → [Table_2]ID`), resource types (forms, menu bars, picture library, …), the database UUID, sort/search settings, journaling |

Even a 220 MB data file previews in about 30 ms, because only header blocks are read.

### What is shown, and what is not

Quick Look has little room, so the preview leads with what matters to a user
or developer, and every block has a fixed size: a file with 500 tables takes
the same space as one with 5 (hover a bar for details).

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

## Build and install

```bash
scripts/build.sh --register
```

This builds a universal (arm64 + x86_64) release, ad-hoc signs it, and
registers it with Launch Services and Quick Look. To install it for good, copy
`build/4D Quick Look.app` to `/Applications` and open it once. If Finder still
shows the old preview, run `qlmanage -r`.

For distribution, sign with a Developer ID and notarize:

```bash
SIGN_IDENTITY="Developer ID Application: …" scripts/build.sh
```

## Developing

```bash
swift build && .build/debug/fourdql file.4DD            # text summary
.build/debug/fourdql --json file.4DD                    # analyzer output
.build/debug/fourdql --html file.4DD > preview.html     # exactly what Quick Look shows
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

## License

MIT, see [LICENSE](LICENSE).
