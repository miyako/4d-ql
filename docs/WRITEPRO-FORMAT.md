# 4D Write Pro `.4wp` format notes

Evidence for the Quick Look preview. Observations come from documents built with
the WP commands in 4D 21.2 (`-d4-version:2.20`) by the probe project in
`Tests/Fixtures/wpfixture`, compared with 4D's own PDF export of the same
documents. Regenerate with `bash scripts/make-writepro-fixtures.sh` (needs the
full 4D application; tool4d does not include 4D Write Pro). The official
attribute reference is
[4D Write Pro documents](https://developer.4d.com/docs/WritePro/4d-write-pro-documents).

## Container

- A `.4wp` file is a ZIP archive holding one XHTML entry named after the document
  title (`Title.html`, UTF-8 with BOM). 4D 21 stores pictures inline as `data:`
  URIs; older documents keep them as archive entries referenced by relative
  `src`, which the analyzer resolves. Compiled formula streams (`*.4dfo`,
  referenced by `-d4-ref-url`) are listed but not decoded.
- Native 4D pictures appear as `data:application/4DPicture;base64,…`: a `TCP4`
  container wrapping a standard codec stream. The preview shows the first PNG,
  JPEG, GIF or TIFF stream found inside.
- Remote pictures keep their URL in `src` (with the MIME type in `alt`); the
  preview never fetches them.

## XHTML and CSS

- `<html xmlns="http://www.w3.org/1999/xhtml" xmlns:d4="http://www.4D.com">`.
  `<head>` holds `<title>`, `<meta name>` entries (`author`, `company`,
  `notes`, `description`, `datetimeCreation`, `datetimeModified`, and
  `bookmarks` as JSON `{"name":[start,end]}`) and one `<style>` element.
- Markup has no whitespace between tags and `p,li { white-space:pre-wrap }`, so
  text is kept exactly; empty paragraphs contain U+200B.
- `body` carries `-d4-version`, the page colour and `-d4-custom` (base64 JSON
  of user attributes).
- Paragraph style sheets become `p.Name,li.Name` rules (spaces become `_`),
  character style sheets `span.Name`. Direct formatting uses generated classes
  (`_p1`, `_img1`, `_div1`, `_table1`, `_tr1`, `_td1`) or inline `style`.
  Elements combine classes, e.g. `class="Normal _p5"`.
- Character attributes nest on `span`: `-d4-font` (full face name) next to
  `font-family/weight/style`; `text-decoration` with
  `-d4-text-underline-style|color` and `-d4-text-line-through-style|color`
  (styles `solid dotted dashed double word semi-transparent`); an inner
  `text-decoration:none` cancels an outer one; `-d4-text-transform:small-uppercase`;
  `text-shadow`; `-d4-text-background-color` in character style sheets.
  Superscript and subscript are written as `vertical-align:super|sub` around a
  `font-size:60%` span.
- Right-to-left paragraphs are written with `direction:rtl;unicode-bidi:bidi-override`,
  yet 4D lays them out with normal bidi, so the override is dropped.
- Tab stops: `-d4-tab-stop-offset`, `-d4-tab-stop-type` (`left right center decimal`)
  and `-d4-tab-stop-leading`; the last value is the default interval.

## Lists

`ul`/`ol` (`start`) contain `li` items. The item's own `list-style-type`
(overridden by `-d4-list-style-type`: `hollow-square`, `diamond`, `club`,
`decimal-greek`, `custom`, …) chooses the marker, so a single list can mix
types; numbering counts the item's position in the list. `-d4-list-string-format-ltr`
(e.g. `'(#)'`) formats the number and `-d4-list-font` the marker font.
Markers hang right-aligned before the text start; `margin-left` indents both.

## Bookmark offsets (full 4D F0012102)

`wp_range_check` / `wp_range_probe` establish these observations in the full
4D 21.2 application, not tool4d. Run the web editor's
[`check-web-editor-native.sh`](../scripts/check-web-editor-native.sh) gate to
retain the native reports, original archives and reexports.

- Serialized `head meta[name="bookmarks"]` pairs are **zero-based, end-exclusive
  UTF-16** offsets. Native `WP Text range` / `WP Bookmark range` objects are
  **one-based**, also end-exclusive. For example, native `[1,8]` exports as
  `[0,7]` for `A😀日éB` (seven UTF-16 units, six Unicode scalars).
- Inline style/link wrappers add no slots. A paragraph separator, `<br/>` and
  an inline picture each occupy one slot. Flat-list item boundaries count like
  paragraph boundaries; list markers do not add slots. The body has no counted
  leading or trailing paragraph delimiter.
- The HTML importer removes U+200B, including within nonempty text. Empty
  paragraphs export with a U+200B placeholder but contribute only their
  separator slots, not a character for that placeholder.
- Insertion at a nonempty bookmark's start shifts both endpoints; insertion
  strictly inside extends its end; insertion at its end leaves it unchanged.
  At a collapsed bookmark's own position, the bookmark remains before insertion.
- Deletion shifts following ranges and clamps overlapping endpoints. An entirely
  deleted nonempty bookmark disappears. A collapsed bookmark strictly inside
  deleted text disappears, but one exactly at either deletion boundary survives.

Native atomic `WP SET TEXT(...; replacement; wk replace)` is **not** generally
equivalent to deletion followed by insertion, even when text lengths match.
The web editor explicitly uses the latter, separately probed policy for every
selection replacement; it does not guess atomic replacement semantics. The
committed native oracle contains 165 such primitive combinations; each gate run
independently repeats them and compares native bookmark positions and selected
text with editor exports after import/export/reopen.

### Table boundaries and native list indentation

`wp_structure_probe` adds independently executed native operations and a
partial-cross-boundary bookmark matrix to the same full-4D gate.

- Within a table, each cell has **one counted terminator**, and each row has
  **one additional terminator**. Paragraphs within a cell retain ordinary
  paragraph separators. `BEFORE`, a 2-by-2 table of `AB/CD/EF/GH`, and `AFTER`
  have 26 slots: `BEFORE\rAB\rCD\r\rEF\rGH\r\rAFTER`. The internal editor tape
  uses `\r` for structural terminators; native `WP Get text` renders intervening
  cells as tabs in a whole-table selection but as paragraph breaks in individual
  cell selections. It is not a plain-text offset oracle.
- Native row insertion between rows splices at the next row's start; appending
  rows splices **before the preceding final row terminator**. Row deletion
  removes all cells and that row's final terminator. Column deletion is a set
  of separate cell-and-terminator deletions, replayed from the last row upward.
- `WP Bookmark range` may return a normalized full-cell or rectangular selection
  even when the serialized bookmark has different endpoints. Native mutations
  can also normalize partially cross-cell ranges in command-dependent ways.
  Keep raw serialized offsets authoritative. The editor supports same-cell and
  row-separator bookmarks, collapsed ranges, bookmarks outside tables and ranges
  enclosing a whole table. The broader-range increment below adds scoped interior
  cross-cell and column support, not arbitrary native-command equivalence.
- Native `wk list style type` plus `wk margin left` produces flat `li` siblings
  with indentation/marker CSS, sometimes in adjacent `ul`/`ol` groups. Indented
  levels add **no slots** beyond ordinary paragraph separators. Native
  indentation, marker changes, typing, paste and paragraph split/join are
  covered. In contrast, arbitrary nested HTML `li > ul/ol` is flattened by the
  21.2 importer: `AB<ul><li>CD</li></ul>` becomes `ABCD ` in the parent item.
  The editor does not silently convert such bookmarked structures or paste.

Supported bookmarked tables are native-shaped direct `tr`/`td`/`th` grids
with paragraph/list cell content and body paragraphs before and after.
Other table forms, arbitrary nested HTML lists, newer
multi-level style sheets, unsupported formula forms, floating-object, header/footer,
section-break or generic `ranges` semantics are not established. Unsupported
structures/pictures and invalid/surrogate-splitting endpoints remain protected.

### Broader table/range evidence (full 4D F0012102)

`wp_complex_probe` independently repeats every collapsed point and ordered
endpoint pair for six table shapes and 18 commands (108 cases). It exports
both archives before/after each command and records native getter ranges,
selected text and text ranges over native cells. The gate checks raw archive
pairs separately from normalized getters; `WP Table get cells`/table elements
must be converted with `WP Text range` before reading text `start`/`end`.

- Inserting one empty column after a chosen column is a descending insertion
  of one cell terminator per row. A collapsed bookmark exactly at an inserted
  cell's start has **right affinity**, unlike ordinary text insertion.
  Nonempty cell-contained ranges retain the original cell, not the new cell.
  Cell anchors, outside-table ranges and enclosures with following text match
  this model for ordinary, uneven-length and empty-cell grids.
- Row-separator anchors are not ordinary insertions: native insertion can
  remove a nonempty separator bookmark or relocate collapsed points. An
  enclosing range ending exactly at the table end can exclude the reconstructed
  final terminator. These anchors block column insertion in the editor.
- Bookmarks spanning parts of cells **within one table** keep raw pairs through
  import/export, name management and formatting. Insertions outside the spanning
  range or at its endpoints match registered splices. Insertion strictly inside
  can normalize a partial range to a rectangular cell selection; deletion,
  row/column edits and other structural commands have additional, distinct
  normalization/deletion behavior. The editor protects those commands instead
  of generalizing a linear-offset rule. A range entering/leaving only part of
  a table remains read-only, since even text edits can normalize it.
- Native horizontal, vertical and rectangular merges serialize positive
  `colspan`/`rowspan` grids. Merged content is paragraphs inside the surviving
  physical cell: paragraph separators replace the former cell separators.
  The tape counts physical cell terminators and one extra terminator for each
  serialized row, with ordinary paragraph separators inside each cell.
  Grid coverage must be complete, nonoverlapping and within the serialized
  rows (at most 1,000 columns). Text/formatting and allowed additions are
  supported without changing span geometry. Row/column editing of merged
  grids, nested tables and malformed/irregular spans remain protected.

These are operation-specific capabilities, not a claim that native selections
are plain text. The combined 997-case gate includes 84 complex model exports and 44
browser/recovered-redo downloads; supported bookmark names, raw positions,
native-selected text and original resource bytes are checked. The compact
`web-editor/tests/fixtures/native-complex.json` oracle derives from this matrix.

### Bookmark names and management (full 4D F0012102)

`wp_bookmark_probe`, run by the same full-4D gate, independently checks
160 name inputs and 13 operations. Native `WP NEW BOOKMARK` removes ASCII
spaces, controls and punctuation except `-` and `_`; an empty result raises
error 110. A NUL truncates the native input. Names are case-sensitive:
`ABC` and `abc` coexist. Japanese, non-BMP characters, combining marks,
Unicode spacing/punctuation, `__proto__`, `constructor` and a 1,024-character
name are preserved in native exports. Native creation with an existing
name overwrites the old range.

There is no native rename command in this version. Native rename can be
implemented by obtaining the old bookmark range, deleting the name and
creating the new one; its duplicate target also overwrites. Since the getter
can normalize table ranges, the editor instead changes only the serialized
name and retains the original raw pair. Native import/export/reopen verifies
the resulting metadata. Rename/delete do not change document text.

The editor rejects new names that native 4D would filter/truncate, invalid
Unicode/XML and exact duplicates. It never silently normalizes, trims or
overwrites. Compatible Unicode is retained as entered; JSON string encoding
and XML attribute escaping are performed by the serializers, not by inserting
raw HTML. Existing malformed/duplicate metadata remains protected.

Collapsed creation works natively and serializes equal endpoints. Native
cell-text, cell-terminator, row-separator, whole-table and indented-list
creation is separately probed. Navigation uses the raw pair and the original
XML-to-native map. It must not pretend that a zero-width/structural slot is a
visible character, nor replace it with a cell-normalized getter selection.

## Breaks and sections

| Markup on a paragraph | Meaning |
|---|---|
| `page-break-after:always` | page break |
| `page-break-after:always;-d4-section-break-after:always` | section break, new page |
| `-d4-section-break-after:continuous` | section break on the same page |
| `break-after:column` | column break |

The body is a flat sequence; sections are counted from section breaks.
`div.section0` holds document defaults and `div.sectionN` section settings:
`-d4-page-width/height` (A4 595×842 pt by default), `-d4-page-orientation`,
`-d4-page-margin` (CSS shorthand; 2.5 cm by default), `-d4-page-first-right`,
`-d4-section-name`, `-d4-page-first-number`, `column-count`, `column-gap`,
`column-rule-*`. Subsections (`div.sectionNFirst`, `…Left`, `…Right`) mark a
different first page or left/right pages.

Headers and footers follow the body as
`<div class="section1Header|section3FirstHeader|section1LeftHeader|…Footer" style="visibility: hidden; height: 0">`.
Their rules hold `margin` (distance from the paper edge, sides, gap to the
body). Every section gets its own copy. A page uses the header and footer of
the section it starts in: with a continuous break, the new section's header
appears only from its next page. With `-d4-page-first-right:false`, page 1 is
a left page.

## Formulas

`<span style="-d4-ref:'…'"> </span>` holds tokenized source: commands
`Name:C123`, constants `Name:K7:1`, fields `[Table:1]Field:2`, project methods
by name, `This:C1470.pageNumber`. `-d4-ref-name` names a formula. Tables bind a
data source with `-d4-ref` on `table` and template cells with formulas on
`This.item`; anchored pictures use `-d4-ref` with an empty `src`. The preview
detokenizes the source and computes only `This.pageNumber`, `This.pageCount`,
`This.pageIndex`, `This.sectionName` and `This.sectionIndex`.

### Web editor formula evidence (full 4D F0012102)

The web editor does **not** use the preview's detokenization or sample
computations. `wp_formula_probe`, executed before relaxing its range guards,
independently creates fourteen formula/source/cache variants and performs
twenty surrounding operations on each of twelve supported text variants.

- A text formula occupies **one native UTF-16 slot**, regardless of source
  or cached textual length. `AB<formula>CD` has native range `[1,6]`.
  The editor represents the atom with U+FFFC, never the projected card's
  `textContent` or cached-value length.
- Native `WP COMPUTE FORMULAS` followed by `.4wp` export still writes NBSP for
  text, empty, NBSP, zero and Unicode results. Explicit `visibleReferences:false`
  and `recomputeFormulas:false` export options do not supply a distinguishable
  cache. Do not label NBSP as a computed/saved value, and never infer results
  from source tokens. Empty and whitespace-only caches cannot be distinguished
  safely from placeholders.
- Native import of a text reference containing supplied nested-span `SAVED`
  or `0` preserves that text in subsequent `.4wp` exports (the styling spans
  can be normalized onto the reference). Supplied empty/NBSP content remains
  indistinguishable from the native placeholder. These fixtures demonstrate
  retained saved content, **not** native computation producing a saved cache.
- Insertion before, at either formula boundary and after; adjacent deletion
  and delete-then-insert replacement; paragraph split/join on either side and
  exactly at both formula boundaries;
  line breaks, paste and text formatting preserve the formula and follow the
  established native bookmark affinities. Formula-enclosing, formula-slot,
  crossing-start/end and collapsed bookmarks are included.
- Quoted `-d4-ref` and optional `-d4-ref-name` on inline text spans are the
  scoped editable-surroundings form. The source remains native-tokenized,
  displayed as inert text. Ordinary nested formatting spans may hold saved
  text; nested references or nontext results remain protected.
- Anchored picture references and table data sources are separately created
  by the native probe but remain unsupported for surrounding range editing.
  `-d4-ref-url` compiled resources are preserved opaquely; their preservation
  is covered by inert browser/model resource tests, not certified native
  compiled-source decoding. Headers/footers, generic/malformed ranges, hidden
  structures and all previous complex-table guards remain in force.

The full gate compares 497 formula originals/model/browser/recovery archives
with independent native source/cache, text, raw bookmark pairs, getter ranges,
metadata and import/export/reopen results. Formula subtrees and resource bytes
must remain unchanged in editor downloads; transactions that cross or alter
an atom roll back. See the [editor's exact limits](../web-editor/README.md#formula-aware-display-available-on-main).

## Pictures, text boxes and tables

- Inline `img` sizes come from its class (`width`, `height`, borders) and
  `-d4-img-display-mode` (`scaledToFit`, `proportional[Centered]`,
  `truncated[Centered]`, `replicated[Centered]`).
- Anchored pictures and text boxes (`<div id="textBox1">` with paragraphs) come
  after the body content with `position:absolute;display:none` and
  `-d4-anchor-page`, `-d4-anchor-section`, `-d4-anchor-origin`,
  `-d4-anchor-h-offset|v-offset`, `-d4-anchor-h-align|v-align` and
  `-d4-anchor-layout` (`front`, `behind`, `wrap-*`).
- Tables: `table` (`-d4-table-align`, `-d4-ref`, `-d4-bottom-carry-over`),
  `tr` (`-d4-header:true` for repeated header rows, `height`), `td`
  (`colspan`, `rowspan`, `width`, padding and borders). An empty paragraph
  follows each table.

## Preview limits

The preview rebuilds documents from a fixed vocabulary of elements and
validated CSS values; nothing from the document reaches the page unfiltered.
Pages split at hard breaks only (no reflow across pages), text wrap around
anchored objects is not simulated, links do not navigate, and very large
documents are cut after about 8,000 paragraphs with a notice.
