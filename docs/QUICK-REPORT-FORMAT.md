# Quick Report binary format

This is an experimental, read-only description of the chunk-based `.4qr`
format, derived from self-authored reports, not a published 4D specification.
The preview needs no 4D runtime. Fixture generation and native readback use
**full 4D**, not tool4d.

## Evidence and coverage

`Tests/Fixtures/qrfixture` contains the project used for controlled experiments.
`probe.4dm` changes one property at a time; `advanced.4dm` generates a three-column
list, two sort levels, subtotals/grand totals, and a cross-table.
`readback.4dm` reloads the binary and obtains column definitions, header/footer,
styles, bottom borders, totals, row visibility and sorts through `QR Get*`.
The checked-in `sales-native.json` is this independent native oracle.

| Native producer | `Vers` | `StVr` | Observed relevant layout |
|---|---:|---:|---|
| 4D 18.6, macOS Intel | `0x00010000` | 25 | Same Unicode strings, columns, styles and cells |
| 4D 19.8, macOS | `0x00010000` | 26 | Same |
| 4D 20.8, macOS | `0x00010000` | 27 | Same |
| 4D 21.2, macOS | `0x00010000` | 28 | Same |

The big-endian fixture is **constructed**, not an original PowerPC/Windows
sample. All understood integers and UTF-16 units were transcoded; full 4D 21.2
then loaded it successfully and returned an identical getter snapshot, including
colors, aggregate flags and borders. This caught two important distinctions:
colors are native-order 32-bit COLORREF values, and aggregate flags are 16-bit,
not 32-bit. Historical pre-Unicode reports and other stream versions are not
claimed as supported. No Windows-produced sample has been inspected.

Regenerate with:

```sh
python3 scripts/make-quick-report-fixtures.py \
  --four-d '/Applications/4D 21.2/4D.app/Contents/MacOS/4D' \
  --compat-four-d '/Applications/4D 18.6/4D.app/Contents/MacOS/4D' \
  --compat-four-d '/Applications/4D v19.8/4D.app/Contents/MacOS/4D' \
  --compat-four-d '/Applications/4D 20.8/4D.app/Contents/MacOS/4D'
```

Compatibility applications are optional. The generator runs isolated copies of
the project and removes machine-specific printer chunks from committed fixtures.
Native LE/BE readback is compared before sanitizing. The generator fails on
timeouts, missing outputs or disagreeing getter snapshots.

## Container and byte order

The four-byte document prefix is `80 1A 00 02`, including in the accepted
constructed BE file. This is followed by an IFF-like, nested chunk stream.

| Offset | Little-endian example | Meaning |
|---:|---|---|
| 0 | `80 1A 00 02` | Document signature/version |
| 4 | `4D 52 4F 46` (`MROF`) | `FORM`, reversed as a native-order FourCC |
| 8 | LE uint32 | Root payload length, excluding its 8-byte chunk header |
| 12 | `54 50 45 52` (`TPER`) | Root form type `REPT` |
| 16 | `73 72 65 56` (`sreV`) | First child `Vers` |

For BE the FourCCs are readable `FORM`, `REPT`, `Vers`, and lengths/numeric
payloads are big-endian. Detect order from the container, not the extension,
host architecture or printer data.

Each chunk is `(FourCC, uint32 payloadBytes, payload, optional pad byte)`.
An odd payload length is padded to the next even byte; the padding is **not**
part of its declared length. `FORM` payloads begin with a native-order FourCC
form type followed by children. Padding also applies to nested forms. Fields
inside payloads are packed: do not impose native C struct alignment.

Root forms observed:

```text
FORM REPT
  Vers, StVr, Mrgn
  FORM Head: Heit, Strs, Font
  FORM Futr: Heit, Strs, Font
  Info, [Sort]
  FORM Col  (repeated, in column order)
    Tfon, Lfon, Info
    FORM Brek (repeated, in row order): Font, Info, Brdr
    Fild OR Frml
    TBrd, Brdr
  Outp, PRPS, PRPF, PRNT
```

Unknown chunks are bounded by their lengths and reported, not scanned for text.
`Mrgn` and `Outp` are not needed for the design preview and remain uninterpreted.

## Strings, fonts and borders

A serialized string consists of a native-order uint32 **byte length**, uint32
encoding (`2` in every observed fixture), followed by that many UTF-16 bytes in
the report's byte order. No terminator or internal alignment. An empty string
still consumes eight bytes. Japanese, accented characters and a surrogate pair
were generated independently to confirm byte counts.

`Font`, `Tfon` (column title) and `Lfon` (detail) share this layout:

| Offset | Type | Meaning |
|---:|---|---|
| 0 | uint32 | Foreground COLORREF |
| 4 | uint16 | Uninterpreted font metadata; observed 1 |
| 6 | uint16 | Font size, points |
| 8 | uint16 | Justification: 0 default, 9 right, 10 left, 11 center |
| 10 | uint16 | Face bits: 1 bold, 2 italic, 4 underline |
| 12 | serialized string | Font name |
| variable | uint32 | Background COLORREF |
| variable + 4 | uint32 | Alternate background COLORREF; `FFFFFFFF` means unset |

COLORREF uses red in the low byte, then green, then blue. For `#123456`,
the integer is `0x00563412`: LE bytes `12 34 56 00`, BE bytes `00 56 34 12`.
This is not a host-independent byte triplet.

`TBrd` (title) and `Brdr` (detail/cell) contain six packed five-byte records:
one thickness byte and one native-order uint32 COLORREF. The order is
**left, inside vertical, right, top, inside horizontal, bottom**, not bit order.
Separate probes confirmed all six. Thickness codes 0–4 mean none, 1/4 pt,
1/2 pt, 1 pt, 2 pt.

## Report, columns and rows

Root `Info` is 13 bytes:

| Offset | Type | Meaning |
|---:|---|---|
| 0 | uint32 | 0 list, 1 cross-table (API values are 1 and 2) |
| 4 | uint32 | Main table number |
| 8 | uint32 | Cell row count per column, **not column count** |
| 12 | byte | Uninterpreted flag, observed 1 |

List reports have one `Brek` row per sort level, then a grand-total row.
Even an empty list declares one cell row. Cross-tables have three columns
and three cell rows. Count actual `Col ` forms to determine column count.
`Sort` is an array of native-order signed int16 column numbers: positive is
ascending, negative descending, one-based. `[1, -3]` is `01 00 FD FF` in LE.

Column `Info`:

| Offset | Type | Meaning |
|---:|---|---|
| 0 | int16 | Width (pixels); `-1` for API-set automatic width |
| 2 | uint16 | Automatic-width flag |
| 4 | byte | Repeat identical values |
| 5 | byte | Hidden column |
| 6 | serialized string | Explicit title |
| variable | serialized string | Display format |
| variable | byte | Hidden title row |
| variable + 1 | byte | Hidden detail row |

A newly inserted column can have an empty explicit title and width 0 with
automatic-width flag 1. Do not equate this with the API's effective/default
title, which may come from its source expression.

`Fild` contains three uint32 values: table number, field number, and an
uninterpreted value observed as zero. Field names are **not** included here.
The preview uses saved titles and table/field numbers; it does not invent names
or open an adjacent database. `Frml` contains a tokenized 4D expression, with
additional internal headers and byte-order rules. It is not plain text.
The initial analyzer only records its size; the renderer explicitly marks
formula cells instead of heuristically extracting printable strings.

Each `Brek/Info` consists of a serialized text string, uint16 operator bitmask,
uint16 hidden flag, and one uninterpreted byte. Operator bits match the API:
1 sum, 2 average, 4 minimum, 8 maximum, 16 count, 32 standard deviation.
Text such as `Subtotal #`, `##S`, and `##xx` is retained literally, not evaluated.

In cross-table mode, `Col /Brek` entries are the fixed 3 by 3 design grid.
The three `Fild` sources specify the column dimension, row dimension, and
measure, respectively. A design preview shows symbolic source references
instead of expanding the matrix with live records.

Header/footer `Heit` is uint16; `Strs` is three consecutive serialized strings
(left, center, right). Native height values are preserved. `Font` applies to
the band. A separate SVG-picture probe produced a `PICT` child in the header;
this opaque picture payload is skipped and marked unsupported by the preview.
Changing the document display unit did not change the serialized report in
these probes, so no unit conversion is inferred.

## Printer data and preview boundary

Observed macOS chunks are `PRPS` (an Apple print-settings ticket as XML plist),
`PRPF` (an Apple page-format ticket as XML plist), and `PRNT` (120 bytes of legacy
print data). The first two contain the kinds of payload represented by Apple's
print-manager serialization APIs, including paper geometry, resolution,
orientation, settings and a formatting-printer name. They are **not report
strings or chunk streams**.

The analyzer bounds and skips their payloads, retaining only the combined byte
count. It neither instantiates native print settings nor loads their XML, paths
or printer identifiers. Windows DEVMODE/DEVNAMES layouts and chunk identifiers
have not been established; unknown chunks are skipped with a parser note.
Do not treat these native structures as universally byte-swappable.

The renderer shows a **design template**, not print-ready output: saved column
widths/visibility, fonts/faces/colors, alternate detail backgrounds, outer
borders, text bands, sort order, subtotal/grand-total labels and operators.
It does not execute formulas, query records, expand total macros, reproduce
pagination/margins, render embedded pictures, or apply printer settings.
Unknown versions produce an explicit error rather than a guessed preview.

Bounds: 32 MiB/file, 512 columns, 513 rows/column, 20,000 total chunks,
eight nested-form levels, 128 KiB/string. Invalid lengths, padding, required
chunks, UTF-16, sort references and inconsistent row counts fail explicitly.

## Command references

- [QR REPORT TO BLOB](https://developer.4d.com/docs/commands/qr-report-to-blob)
- [QR BLOB TO REPORT](https://developer.4d.com/docs/commands/qr-blob-to-report)
- [QR SET INFO COLUMN](https://developer.4d.com/docs/commands/qr-set-info-column)
- [QR SET TEXT PROPERTY](https://developer.4d.com/docs/commands/qr-set-text-property)
- [QR SET SORTS](https://developer.4d.com/docs/commands/qr-set-sorts)
- [QR SET TOTALS DATA](https://developer.4d.com/docs/commands/qr-set-totals-data)
- [QR SET BORDERS](https://developer.4d.com/docs/commands/qr-set-borders)
- [QR SET HEADER AND FOOTER](https://developer.4d.com/docs/commands/qr-set-header-and-footer)
