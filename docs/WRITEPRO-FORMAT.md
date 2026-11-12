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

These observations do not establish table, nested-list, formula, floating-object,
header/footer, section-break or generic `ranges` offsets. Bookmarked documents
containing those structures, unsupported pictures or invalid/surrogate-splitting
range endpoints remain read-only in the editor.

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
