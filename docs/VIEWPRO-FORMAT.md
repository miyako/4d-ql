# Native 4D View Pro (`.4vp`) format

## Evidence and reproduction

These are observations from **full 4D 21 R4**, the dependency-manager-installed
**4D ViewPro 21R4.2**, and its **SpreadJS 18.2.0** engine, not a proposed format.
The blank project supplied for experiments was
`/Users/miyako/Desktop/view-pro-test`. Its `dependencies.json` and resolved
component established the environment; no files in that project were modified.
The independent, minimal probe project lives in `Tests/Fixtures/vpfixture`.

Run on macOS with a graphical login and licensed full 4D:

```sh
bash scripts/make-viewpro-fixtures.sh
# Or select another installed full 4D:
FOURD="/Applications/4D 21.2/4D.app/Contents/MacOS/4D" \
  bash scripts/make-viewpro-fixtures.sh
```

`dependencies.json` requests `4d/4D-ViewPro`, version `4d`, so 4D resolves the
component appropriate to the selected application. Cached dependencies can be
reused. Other application/component versions have not been verified here.
`tool4d` is unsuitable: the commands need a Web Area.

The script launches its own 4D process with `--dataless --skip-onstartup
--startup-method=vp_probe`. `VP Run offscreen area` creates a named area with
`autoQuit=False`, a 60-second timeout, and an event formula. Commands start only
on `On VP Ready`. Every export/import supplies a callback formula, including the
synchronous native format and asynchronous Excel operations. Callbacks log
status and advance the pipeline; failure cancels it. A native error handler,
URL-loading error branch, completion JSON, and a 120-second subprocess timeout
make failures explicit. Only the launched process is terminated on timeout.
Both normal output and the native error handler use `Folder("/PACKAGE/Output")`;
no HFS path from `Get 4D folder` is passed to the POSIX/virtual-path Folder API.

The script verifies all outputs before copying them into
`Tests/FourDFileKitTests/Fixtures/ViewPro`. Generated logs, dependency locks,
4D preferences, and intermediate outputs remain ignored in the probe project.
Timestamps, Excel ZIP metadata, and engine normalization mean regeneration is
semantically reproducible, not byte-identical.

### Checked-in native samples

| File | Construction / purpose |
|---|---|
| `typed.4vp` | Strings (including Unicode and empty text), numbers, booleans, dates, numeric/text/error formula results, display formatting |
| `layout.4vp` | Four ordered sheets, workbook/sheet named styles, cell/row/column/default styles, fonts, colors, alignment, wrapping, border, merged cells, dimensions, hidden rows/columns, hyperlink |
| `values-only.4vp` | `layout` exported with `valuesOnly=True` |
| `no-format-info.4vp` | `layout` exported with `includeFormatInfo=False` |
| `roundtrip.4vp` | Native `VP IMPORT DOCUMENT(layout.4vp)` then native export |
| `layout.xlsx` | Native `.4vp` import followed by asynchronous Excel export reference |
| `xlsx-roundtrip.4vp` | Native import of `layout.xlsx`, then `.4vp` export |
| `enriched.4vp` | Documented object-import API adds rich text and sheet visibility to the Excel-roundtripped document, then native export |
| `enriched.xlsx` | Excel reference for enriched rich text and hidden/very-hidden sheets |
| `enriched-xlsx-roundtrip.4vp` | Native import of enriched Excel reference, then native export |

All ten exports and four imports completed with `success:true`; the generator's
Python assertions check all eight `.4vp` documents and both Excel ZIPs. Rich text
is additionally confirmed by actual `<r>` runs in `xl/sharedStrings.xml`; hidden
states are confirmed in `xl/workbook.xml`.

## Container

`.4vp` is **plain compact UTF-8 JSON**, not ZIP, XML, SQLite, or an opaque binary
container. The first bytes of the typed export are
`{"spreadJS":{"version":"18.2.0"`. No BOM was emitted.

```json
{
  "spreadJS": {
    "version": "18.2.0",
    "sheetCount": 1,
    "sheets": {
      "Sheet1": {
        "name": "Sheet1",
        "rowCount": 1000,
        "columnCount": 100,
        "visible": 1,
        "data": {"dataTable": {}},
        "index": 0,
        "order": 0
      }
    }
  },
  "version": 1,
  "dateCreation": "2026-11-10T16:09:25Z",
  "dateModified": "2026-11-10T16:09:25Z"
}
```

The example omits many native defaults. The outer numeric `version` and inner
SpreadJS version string are distinct. Creation/modification dates are UTC ISO
strings and are not spreadsheet cell dates.

## Sparse cells and typed values

`spreadJS.sheets` is an object keyed by sheet name, not an array. A sheet's cells
are a sparse object at `data.dataTable`; the first key is the **zero-based row**,
the second the **zero-based column**. Keys are decimal strings.
`dataTable["0"]["1"]` means B1, not A2. Empty missing coordinates do not need
nodes, and an explicitly assigned empty string survives separately.

Actual cell objects from `typed.4vp`:

```json
{"value":"Hello View Pro"}
{"value":"日本語 / café / 😀"}
{"value":""}
{"value":1234.5}
{"value":true}
{"value":false}
{"value":-0.125,"style":{"formatter":"0.0%","formatInfo":{"text":"-12.5%"}}}
{"value":"/OADate(45351)/","style":{"formatter":"M/d/yyyy","formatInfo":{"text":"2/29/2024"}}}
{"value":"/OADate(0)/","style":{"formatter":"yyyy-mm-dd","formatInfo":{"text":"1899-12-30"}}}
{"value":2469,"formula":"B1*2"}
{"value":"Result: Hello View Pro","formula":"\"Result: \"&A1"}
{"value":{"_calcError":"#DIV/0!","_code":7},"formula":"1/0"}
```

Dates therefore use the SpreadJS/OLE Automation date marker, not a plain ISO
string or automatically a JSON number. The observed zero is 1899-12-30 and
45351 is 2024-02-29. Fractional dates, negative dates, Excel's historical leap
year edge cases, time zones, and durations were not exercised.

Formula source is stored **without the leading `=`**, alongside its cached
typed result. A reader need not evaluate formulas to display these documents.
Cached errors are objects, not strings. Cross-sheet `Data!B1` also retains its
cached numeric result.

`valuesOnly=True` removes formula source and retains the cached values.
`includeFormatInfo=False` removes generated `formatInfo`/wrapping display
information while retaining actual styles and number format patterns.
Do not assume `formatInfo` exists for every cell: unformatted cells often have
only `value`, and formula caches are not necessarily formatted strings.

## Sheets, order, and visibility

`layout.4vp` has `sheetCount=4` and sheets `First`, `Data`,
`Hidden candidate`, `Very hidden candidate`, with `index` and `order` 0–3.
`First` was inserted before an existing `Data` sheet using `VP ADD SHEET`;
the engine updated the moved sheet indexes. Do not rely on JSON object
enumeration for sheet order.

The active sheet key is `spreadJS.activeSheetIndex` (1 in every multi-sheet
fixture), not `sheetTabCount` or `startSheetIndex`. The single-sheet typed
fixture omits `activeSheetIndex`. Each sheet also emits boolean `isSelected`
(`Data` true, the others false). Native `roundtrip` adds
`spreadJS.startSheetIndex=-1`, which is not an active-sheet index.

Observed sheet visibility is numeric:

| `visible` | Confirmed Excel state |
|---|---|
| `1` | visible |
| `0` | hidden |
| `2` | veryHidden |

The wrapper does not expose a documented sheet-visibility setter in the
installed API. The latter two states were deliberately assigned in the object
returned by `VP Export to object`, accepted by `VP IMPORT FROM OBJECT`, then
exported natively. Excel export/import preserves both states. These are native
accepted/exported samples, but not a claim that the wrapper has a visibility
command.

## Styles and displayed values

Direct cell styles appear under `cell.style`:

```json
{
  "backColor":"#e8f0fe",
  "foreColor":"#123456",
  "font":"bold 14pt Arial",
  "formatter":"#,##0.00",
  "fontWeight":"bold",
  "fontSize":"14pt",
  "fontFamily":"Arial",
  "formatInfo":{"text":"1,234.50"}
}
```

The engine emits both CSS font shorthand and expanded font fields. Other
observed properties include numeric `hAlign`, numeric `vAlign`, `wordWrap`,
`textDecoration`, and `borderBottom:{"color":"#ff0000","style":2}`.
The probe uses horizontal 0/1/2 for left/center/right and vertical 0/1/2 for
top/center/bottom according to the installed constants; Excel normalization
can also emit horizontal 3 (general).
Wrapped text can carry `wordWrapInfo.lines[]` with `text` and `width`, plus
`lineHeight` and `boxWidth`.

Styles are **not all inline**:

| Storage | Meaning / actual example |
|---|---|
| `spreadJS.namedStyles[]` | Workbook styles, e.g. `name:"SharedHeading"` |
| `sheet.namedStyles[]` | Sheet-local styles, e.g. `name:"LocalMoney"` |
| `cell.style.parentName` | Named style reference, e.g. `"SharedHeading"` |
| `sheet.data.rowDataArray[7].style` | Row style (`backColor`, italic font) |
| `sheet.data.columnDataArray[1].style` | Column style (`foreColor`, `hAlign`) |
| `sheet.data.defaultDataNode.style` | Sheet defaults (font, colors, alignment) |

**A `style` value can also be a string naming a style**, not only an object.
In `no-format-info.4vp`, Data A5 is
`{"value":"Merged heading","style":"SharedHeading"}` and B8 is
`{"value":42.5,"style":"LocalMoney"}`. With format information enabled these
become objects containing `parentName`, optionally with `formatInfo`.
In all three Excel-derived fixtures (`xlsx-roundtrip`, `enriched`,
`enriched-xlsx-roundtrip`), `Data.data.rowDataArray[7].style` is the string
`"__builtInStyle7"`, while `Data.data.columnDataArray[1].style` is
`"__builtInStyle11"`. Their definitions are workbook `namedStyles` entries
at array indexes 10 and 14 respectively: indexes do not match name suffixes.
Normalize a string style reference to the equivalent `{"parentName":name}`
before resolving styles, using sheet-local definitions ahead of workbook
definitions. No numeric cell/axis style references were observed; a numeric
`borderBottom.style` is a border-line enum, not a named-style reference.

Those indexed arrays contain JSON `null` placeholders for omitted rows or
columns. Header defaults also appear in `rowHeaderData.defaultDataNode` and
`colHeaderData.defaultDataNode`; they are not ordinary grid cells.
The merged heading has only `style:{"parentName":"SharedHeading"}`, and B8
has `parentName:"LocalMoney"` plus `formatInfo.text:"$42.50"`. Readers that
only inspect the inline font/formatter will miss their styling.

Excel import can substantially normalize styles: add workbook `Normal` and
`__builtInStyleN` entries, move formerly inline styling into `parentName`
references, turn pt fonts into px fonts, and add explicit null/default
properties. Color strings may be theme tokens such as `"Text 1 0"`, not only
hex RGB. Do not equate style-array positions with named-style names.

### Theme representation

No outer-root or workbook-level theme property was emitted. Theme data lives
at `spreadJS.sheets[name].theme`. Direct native fixtures use the string
`"Office"`. Excel-derived fixtures instead use an object with keys `name`,
`themeColor`, `headingFont`, `bodyFont`, and `font`. Its `name` is `"Office Theme"`,
`headingFont` is `"'Calibri Light'"` (including single quotes), and `bodyFont`
is `"Calibri"`. The nested font object includes script-specific typeface maps.
`themeColor` has `name:"Office"` and color objects `{r,g,b,a}` with integer
channels 0–255 (alpha is 255, not 1). Observed RGB values are:

| Key | RGB |
|---|---|
| background1 | 255,255,255 |
| background2 | 231,230,230 |
| text1 | 0,0,0 |
| text2 | 68,84,106 |
| accent1 | 91,155,213 |
| accent2 | 237,125,49 |
| accent3 | 165,165,165 |
| accent4 | 255,192,0 |
| accent5 | 68,114,196 |
| accent6 | 112,173,71 |
| hyperlink | 5,99,193 |
| followedHyperlink | 149,79,114 |

Thus the observed style token `"Text 1 0"` selects black `themeColor.text1`
with a zero suffix; `"Body"` is a theme-font token, not a font-family name.
Nonzero color-token suffix transformations were not tested.

## Geometry, hidden rows/columns, and merges

The Data sheet is deliberately reduced to `rowCount=24`, `columnCount=12`.
Actual serialized geometry:

```json
{
  "rows":[null,null,null,null,{"size":32},null,null,null,null,{"size":27,"visible":false}],
  "columns":[{"size":180},null,{"size":90,"visible":false}],
  "spans":[{"row":4,"col":0,"rowCount":2,"colCount":4}]
}
```

Row/column `size` values are pixel dimensions, not Excel's character width
units. Their visibility is **boolean**, unlike numeric sheet visibility.
The merge is A5:D6; content/style are attached to the top-left anchor.
Sheet `rowCount`/`columnCount` express grid capacity, not populated extent.
Default 1000×100 sheets should not force rendering every empty cell.

No sheet-level default row-height/column-width property is emitted in these
fixtures. `defaultData` is `{}`, and `data.defaultDataNode` holds a style, not
geometry. The native layout's `rowHeaderColInfos[0].size=60` is a row-header
column width, not the default data-column width. Excel roundtrip materializes
20-pixel rows at populated coordinates and a 62-pixel B column; these are
observations of that roundtrip, not a proven universal default-size schema.

## Hyperlinks and rich text

Native formula `HYPERLINK("https://example.com/fixture","Fixture link")`
produced:

```json
{
  "value":"Fixture link",
  "hyperlink":{
    "url":"https://example.com/fixture",
    "tooltip":"",
    "target":0,
    "drawUnderline":true,
    "command":""
  },
  "formula":"HYPERLINK(\"https://example.com/fixture\",\"Fixture link\")"
}
```

Formula arguments use commas. A deliberately tested semicolon-separated
formula was rejected as formula syntax and became text; that failed trial is
not retained in the final fixtures. Native and Excel roundtrips preserve the
valid hyperlink URL and cached label.

Rich text was injected through documented object import (the installed wrapper
has no dedicated rich-text setter), then natively exported:

```json
{
  "value":{
    "richText":[
      {"text":"Bold","style":{"font":"bold 12pt Arial","foreColor":"#ff0000"}},
      {"text":" plain","style":{"font":"12pt Arial"}}
    ]
  }
}
```

Excel export writes actual rich-string runs, including the red bold first
run; it does not merely preserve an unknown JSON object. Importing that Excel
file normalizes the `.4vp` cell to:

```json
{
  "value":{
    "value":"Bold plain",
    "richText":[
      {"style":{"foreColor":"#ff0000","font":"normal bold 16px Arial"},"text":"Bold"},
      {"style":{"foreColor":null,"font":"normal normal 16px Arial"},"text":" plain"}
    ],
    "text":"Bold plain"
  }
}
```

Support both the richText-only and richText-plus-value/text forms; never
describe arbitrary object-valued cells as rich text solely because they are
objects (formula error objects are another observed kind).

## Roundtrip results and limits

The native layout import/export retained cells, cached formulas, named styles,
geometry, and merges. The sole inner-workbook structural difference in the
observed native roundtrip was an added `startSheetIndex`; byte equality is not
a valid roundtrip requirement. Excel roundtrip preserved checked typed values,
formula caches, links, merges, and geometry but substantially expanded and
normalized style representation. Rich text and both hidden-sheet states were
separately confirmed through Excel.

This probe does not establish every SpreadJS version's schema or validate
charts, pictures, shapes, tables, pivots, external references, custom 4D
functions, password protection, print rendering, arbitrary malformed input,
or a complete style cascade. Unknown fields should be handled conservatively.
No screenshots or UI rendering comparisons were made.

## Implemented decoder and static-preview limits

The integrated reader accepts UTF-8 JSON files up to **16 MiB**, using the
existing bounded JSON parser with a maximum of **64 nesting levels** and
**100,000 JSON values**. Additional decoding limits are:

* **256 sheets**.
* **20,000 saved cells**.
* **2,000 nonoverlapping merged ranges per sheet**.
* Maximum axis/sheet dimensions of **10,000,000**.

The static renderer includes at most **16 visible sheets**, retaining the active
sheet, with at most **200 visible rows and 40 visible columns per sheet**.
It shows notices for excluded cells and raw values whose formats are unsupported.
Grid capacities are not treated as populated extents.

Supported data includes typed strings/numbers/booleans, distinguished OADate
values, cached formula results and errors, and rich-text runs. Supported styling
includes string named-style references, `parentName` references, and the
default + column + row + cell cascade, together with axis geometry/visibility
and merged ranges.

The preview is static: it embeds no 4D/SpreadJS runtime and evaluates neither
formulas nor links. Charts, pictures, conditional formatting, and print layout
are unsupported. **Theme color references are currently unresolved**; an
unsupported-feature warning should be retained rather than interpreting tokens
such as `"Text 1 0"` as literal CSS colors. The observed theme representation is
documented above for future support, but nonzero tint suffixes remain untested.

There is **no XLSX reader in this repository**. The checked-in XLSX files are
native export/roundtrip references only, not additional supported input formats.
Integration validation reported successful decode/render tests for all eight
native fixtures plus native WebKit checks for sheet selection, dimensions,
styles, merges, and zoom.

## Reference approaches

Only the public command/event approach was consulted; no third-party
implementation was copied into the probe:

* https://github.com/miyako/4d-tips-offscreen-view-pro-example
* https://github.com/miyako/4d-example-import-xlsx-with-view-pro
* https://github.com/miyako/4d-example-synchronous-view-pro-export
* https://github.com/miyako/4d-tips-vp-multiple-exports
* Installed component `Contents/Documentation/Methods` command documentation
