# 4D label previews

`.4lbp` is XML, not JSON. The native UTI is `com.4d.4d.labelFile`
(OSType `4DET`), shared with legacy binary `.4lb`; binary labels are not
decoded. The Quick Look extension and `fourdql` use the same analyzer and
presenter, with no 4D runtime needed for previews.

## Format evidence

The public [4D Labels source, 21R5](https://github.com/4d/4D-Labels/tree/eab27321376d09be6cfdf96643442357190cd740)
defines the format through `Resources/default.4lbp`, `label_Parse_document`,
`wizard_Save`, `LABELS_INIT`, `Print_Label`, `PRINT_OBJECT` and
`Editor_Put_object`. `wizard_Save` writes the XML DOM, while
`label_Parse_document` reads XML and upgrades pre-version-2 rounded rectangles.
No upstream source or artwork is redistributed here.

Full 4D 21.2 and 21 R5 native print/DOM-export references confirm the matrix
coordinates, point units, artwork and named-table-form behavior. The probe
requires fresh modern projects/data with explicit primary keys and rejects
tool4d. See [native evidence and reproduction](LABEL-NATIVE.md). Native wizard
Save-button automation and editor-canvas capture remain unverified; the
documented capture blocker does not affect the native print references.

The `<label>` root saves `version`, `columns`, `rows`, `start` and
`labels-per-record`. Child settings are `setting` (auto-width, landscape,
vertical), `size`, `margin`, `gap`, `form` and `method`.
`objects/object` is paint order; selections are editor state.
The parsed XML tree retains unknown attributes and elements in JSON output.
The original source is available in a collapsed, syntax-highlighted panel.

Dimensions are **points**, regardless of `size/@unit`, which selects the
editor's display unit. `landscape` selects printer orientation; it does not
rotate the label artwork. Horizontal order counts across then down; vertical
order counts down then across. Positions before the one-based `start` are
shown as skipped.

Saved object bounds are coordinates in 4D's fixed editor matrix, whose
origin is `(237, 55)` and size is `348 x 191`. The label is centered in it.
Thus local x is `left - 237 - (348 - labelWidth) / 2`, and local y is
`top - 55 - (191 - labelHeight) / 2`. Width/height are right-minus-left
and bottom-minus-top. Polyline data contains centered coordinate pairs.

Supported artwork includes rectangles, rounded rectangles, ovals, ascending
and descending lines, polylines, text, saved field/formula expressions, and
embedded raster pictures. Text uses the shared form font/layout services
for wrapping, alignment, bold, italic and underline. Pictures are decoded,
bounded and re-encoded as passive PNGs, never emitted as arbitrary SVG or URLs.
The sheet reuses the bounded label artwork with SVG references.

## Referenced forms and limitations

The saved `form/@name` refers to a table form in the caller's database, not
inline JSON. The label alone does not identify that database/table reliably;
`form/@number` is not treated as a table number. A project-contained label can
resolve a unique matching `Project/Sources/TableForms/*/<name>/form.4DForm`.
Ambiguous, missing, inaccessible and escaping/symlinked targets are reported,
not guessed. Standalone labels still show settings and artwork, but cannot
resolve database forms. The host's existing explicit project authorization
also covers label previews.

Referenced forms use the existing shared `.4DForm` analysis/rendering path,
including stylesheets, passive pictures, localization and static subforms.
They appear separately; the sheet marks the form reference rather than
pretending a repeated form screenshot is the printed result. Saved artwork
is ignored when a form is selected, as in 4D.

This is an approximate design preview, not print emulation. No records,
expressions or methods execute, picture fields show saved expressions,
and font substitution/wrapping may differ from 4D. Printer paper size and
printable area are not inferred from the machine. The sheet extent comes from
saved rows, columns, label dimensions, margins and gaps. Automatic form sizing
depends on the printer and is called out explicitly.

## Bounds

Inputs: 4 MiB XML, 20,000 elements, nesting depth 32, no custom entities or
external entity loading. Versions 1 and 2 are supported. Output: 1,000
objects, 400 sheet positions, 8,192-point sheet sides, 32,768-point saved
coordinates, 4,096 polyline scalars, and 4,096 UTF-16 units/100 lines per
text object. The source panel shows at most 256 Ki characters.
Raster images retain the form decoder's 32-megapixel source/2,048-pixel
thumbnail/4 MiB converted-image limits, with 16 MiB converted pictures per
label. Referenced forms retain all existing form budgets and confinement.

```sh
swift test --filter LabelTests
python3 scripts/test-label-native-probe.py
swift run fourdql --json path/to/label.4lbp
swift run fourdql --html path/to/label.4lbp > preview.html
```
