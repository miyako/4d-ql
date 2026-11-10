# Native XML label evidence

## Reproduction

These are self-authored fixtures, not upstream sample files or artwork:

- `Tests/FourDFileKitTests/Fixtures/LabelProject/Resources/Labels/representative.4lbp`
  contains a rectangle, rounded rectangle, oval, line, Unicode text, field,
  formula, and original embedded 24×24 PNG checker.
- `saved-form-reference.4lbp` contains a host form reference, `ShippingLabel`,
  supplied under `Project/Sources/TableForms/1/ShippingLabel/`. It cannot be
  rendered from the `.4lbp` alone. Its deliberately mismatched `number="999"`
  verifies that native printing uses the form **name**, not this number.
- `Project/Sources/Methods/label_probe.4dm` creates one local test record and
  invokes the real `PRINT LABEL` command with the authored XML and a native
  PDF print destination. It also parses/exports the XML using 4D's XML DOM.

Run on macOS with licensed **full 4D**, not tool4d:

```sh
python3 scripts/label-native-probe.py --generate-only
python3 scripts/label-native-probe.py --output build/label-reference-r5
python3 scripts/label-native-probe.py \
  --engine '/Applications/4D 21.2/4D.app/Contents/MacOS/4D' \
  --output build/label-reference-21-2
```

Use a fresh output directory. The script copies the project, creates a data
file there, retains invocation/log/hash evidence, and bounds the child process
by timeout. Native PDF text must contain the literal text, `Ada Example`
(field), and `Code: 7` (formula); a PDF header alone is not success.
The PNG reference is a macOS PDFKit raster of the actual 4D PDF, not a browser
or Quick Look approximation. No Python packages are needed.
Run full-4D probes serially: concurrent engine startup/version invocations
were not reliable on the test machine.

**No legacy structures or existing data are opened.** Before any engine
invocation, the script requires compatibilityVersion 2100+, the authored XML
catalog with a defined unique/non-null primary key on every table, no binary
structure/data files or symlinks in project inputs, and a new/empty output
directory. `--create-data` creates fresh data there. A missing-key catalog
caused a Primary Key Manager prompt during early investigation; that bounded
child was stopped without clicking through or migrating data, and the catalog
now explicitly defines the primary key. Do not reuse the earlier writable
probe directories. Check the guard without starting 4D:

```sh
python3 scripts/label-native-probe.py --validate-only --output build/new-label-probe
```

`--editor` instead opens 4D's native label wizard using `PRINT LABEL` with a
nonexistent document name. This is an explicitly interactive option, bounded
by the same timeout. The automated reference run does not drive wizard UI or
claim an editor Save-button roundtrip. Its XML roundtrip executes the same
`DOM EXPORT TO FILE` command used by the native component's saver.

## Provenance and semantics

Inspected the public `4d/4D-Labels` **21R5** source using unauthenticated HTTPS:

- [label_Parse_document.4dm](https://github.com/4d/4D-Labels/blob/21R5/Project/Sources/Methods/label_Parse_document.4dm):
  `.4lbp` is parsed as XML, while legacy binary documents take a separate path.
- [wizard_Save.4dm](https://github.com/4d/4D-Labels/blob/21R5/Project/Sources/Methods/wizard_Save.4dm):
  serializes the existing DOM using `DOM EXPORT TO FILE`.
- [LABELS_INIT.4dm](https://github.com/4d/4D-Labels/blob/21R5/Project/Sources/Methods/LABELS_INIT.4dm)
  and [Print_Label.4dm](https://github.com/4d/4D-Labels/blob/21R5/Project/Sources/Methods/Print_Label.4dm):
  establish the editor coordinate matrix and native print translation.
- [Editor_Image_drop.4dm](https://github.com/4d/4D-Labels/blob/21R5/Project/Sources/Methods/Editor_Image_drop.4dm),
  `Editor_Field_drop.4dm`, and `Editor_FORMULA_Stop.4dm` establish persisted
  image/field/formula attribute names.

No upstream source or assets are copied into this repository.

Important: object bounds are **editor-matrix coordinates**, not label-local
coordinates. The native matrix is left **237**, top **55**, width **348**,
height **191**. Normalize each object coordinate by subtracting:

```text
x-origin = 237 + (348 - labelWidth) / 2
y-origin =  55 + (191 - labelHeight) / 2
```

Our 252×179-point label therefore starts at editor coordinate **(285,61)**.
An initial local-coordinate-only probe produced a blank page even though
`PRINT LABEL` returned `OK=1`. Correctly translated bounds produced all
expected text and original graphics. Native printing reads many positions
into integer variables; do not treat subpoint rounding as verified here.

The root `label` has sheet columns/rows, labels-per-record and start index.
Children `setting`, `size`, `margin`, `gap`, `form`, `method`, `selects` and
`objects` use matching `id` attributes. Objects are ordered `object` elements
with `type`, `left/top/right/bottom`, font/style/alignment, fill/stroke
colors/opacities, and other type-specific attributes. The ellipse type is
`oval`; rounded rectangles are `round-rect` with `rx`/`ry`.

Literal text is the `value` attribute, not element text. Both fields and
formulas use `type="variable"` and `value`; field metadata can additionally
include `table`, `field`, `pairs`, `tableList`, and `fieldList`. The embedded
PNG uses base64 `image-data` plus `image-codec=".png"` and
`preserve-aspect-ratio="true"`. A nonempty `form/@name` selects a host form
instead of standalone objects. Static previews do not evaluate fields/formulas
or ask a running database to resolve forms. This preview can resolve an
unambiguous project table-form file through the shared `.4DForm` analyzer.

`size/@unit` controls the editor's displayed measurement unit, not the numeric
coordinate scale. The probe changes only this attribute from `pt` to `mm`,
prints both documents, and requires their PDFKit PNGs to be byte-identical.
Both tested engines pass. Measurements, margins, gaps and saved bounds remain
points.

The host form probe prints `HOST FORM REFERENCE` and `ShippingLabel — table 1`
from the supplied table form, instead of the standalone label's objects.
`form/@number="999"` does not prevent rendering the named `ShippingLabel` form
on table 1. This agrees with the native component's `FORM LOAD(table; name)`
path. `host-form.png` is a real native `FORM SCREENSHOT` of that table form;
`saved-form.pdf` is the independently printed label referencing it.

### Label wizard UI limitation

A separate bounded full-4D R5 run reached `stage="entering-wizard"` and the
WindowServer reported a visible **Label Wizard**, 750×612 points. However,
targeted `screencapture -l <windowID>` failed with **"could not create image
from window"**; Accessibility exposed no window for that specific process
(`System Events` error -1719). Screen-recording preflight reported authorized.
The child was stopped, and no unrelated windows/screens were captured.
Consequently, no actual label-editor canvas screenshot or toolbar Save-button
automation is claimed. Native print rendering, XML DOM export, native host-form
screenshot, and host-form-reference printing are verified independently.

## Retained native references

`LabelProject/References/21-r5/` and `LabelProject/References/21-2/` retain
the native PDFs and PDFKit PNGs for representative/unit-mm/form-reference
cases, native host-form screenshot, native DOM-exported XML, context,
extracted PDF content, and invocation/hash evidence. Verified engine versions:

- **21 R5 build 21R5.100156**
- **21.2 build 21.100653**

One record prints one label on an A4 sheet; the 2-column/3-row layout is
configured but no claim is made here about multi-record pagination.
The original XML's element order and every
attribute survive native DOM export unchanged (serialization whitespace and
XML declaration formatting can differ).
