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
- Tab stops: `-d4-tab-stop-offset`, `-d4-tab-stop-type` (`left right center decimal bar`)
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

### Document page geometry (full 4D F0012102)

`wp_page_probe`, executed by the web editor's full-4D gate before browser
exports, establishes these scoped observations. Native-created `.4wp` originals,
targets, PDFs, getter values and invalid-value results remain in
`Output/page-report.json` and the page evidence archives.

- A new native document omits `div.section0` entirely: getters return
  `595pt` × `842pt`, portrait (`0`) and `2.5cm` on all four sides.
  Nondefault values serialize in `div.section0`, not in an element in the body.
- Width and height are **base dimensions**, stored as whole points. Setting
  `210mm` × `297mm` yields `595pt` × `842pt`; `600.125pt` × `800.875pt`
  yields `600pt` × `801pt`. Margins retain units and fractional precision:
  `12.345mm 0pt 0.5in 1.25cm` is a four-sided native shorthand.
- Portrait does not sort dimensions: native `900pt` × `500pt` portrait produces
  a 900 × 500 PDF MediaBox. Landscape (`1`) swaps the base dimensions without
  changing the serialized width/height: the same base pair becomes 500 × 900.
  Thus orientation must not be inferred only from width versus height.
- Width/height setters on a section raise error 205; paper size is document-level.
  A section can override orientation and margins. Setting only its left margin
  serializes all four margin sides. After document defaults change, that
  explicit group stays intact while absent orientation/margin declarations
  inherit. Export may omit an explicit value equal to the current default;
  this does not authorize the editor to flatten or remove existing declarations.
- Negative widths/margins raise error 204. Native setters accept zero dimensions
  and margins exceeding the paper. The editor intentionally requires positive
  paper dimensions (at most 10,000 pt), nonnegative margins and positive text
  areas in every retained section. This is a conservative supported scope,
  not a claim that native 4D rejects every other layout.

The page gate compares model and browser Apply/Undo/recovered-Redo downloads
with independent native mutations of the original documents, native document
and section getters, native-exported PDF page boxes, and native reexported body
XML/raw bookmark pairs. Geometry-only editor changes leave original body,
formula/reference subtrees, bookmark metadata, nongeometry CSS and resource
bytes unchanged, including protected documents. Supported section geometry is
projected on continuous white surfaces, not exact or automatic native pages.

### Section/break authoring evidence (full 4D F0012102)

`wp_section_probe` independently creates 27 structural cases before editor
exports: page (`2`), new-page section (`1`) and continuous section (`5`) breaks
at body start, interior, before/after a text formula and body end; existing
inherited/overridden sections; names, first-page headers and section-anchored
pictures. Explicit section setting/reset observations are recorded separately.
The source, inserted, ordinary-paragraph and deleted archives plus getter/slot
reports are retained in `Output/section-report.json` and adjacent files.

- Each inserted break occupies **one UTF-16 slot**, represented by a paragraph
  boundary in exported flat XHTML. `WP Get text` reports CR, not an extra
  form-feed or synthetic section atom. All three kinds follow the established
  native insertion rules for enclosing/collapsed bookmarks; formulas still
  occupy exactly one slot.
- Replacing that slot with `wk paragraph break` removes the page/section break
  while retaining a paragraph boundary and the same bookmark offsets. Deleting
  the slot instead joins text and shifts ranges. The editor's explicit removal
  deliberately uses the former semantics.
- Section identifiers in selectors and header/footer classes are positional
  indices starting at 1. Native insertion splits the section, retains its old
  name on the first part, makes the new part unnamed, copies explicit geometry,
  and shifts later indices. It can copy section/first-page headers and change
  anchored associations. Native merge can discard the earlier section's name.
  The editor consequently permits section insertion only in the last section
  without hidden/subsection/unsupported structures, and merges only when no
  section-specific declarations or associations would be lost or renumbered.
- Section orientation and margins inherit from document defaults **by absence**.
  Native `WP RESET ATTRIBUTES` removes those overrides. A margin setter on one
  side serializes the four-sided group. The browser edits that group explicitly
  and removes the entire group on reset, never materializing defaults as a
  substitute for inheritance. Width/height remain document-only.
- Geometry/name-only edits retain original body, hidden object XML, unknown
  section/subsection declarations, bookmarks and resources. The gate compares
  full native reexports and getters with separately mutated native originals,
  including section names and header/footer/anchored associations.
- Seventeen native name export/reimport probes cover Unicode/non-BMP/combining
  characters, spaces, punctuation and 1,024-unit names. Native names containing
  quotes can disappear on reimport, backslashes are removed, and surrounding
  whitespace/control characters are normalized. The editor rejects those new
  names instead of silently adopting native normalization; unchanged imported
  names are retained.

The browser shows localized explicit-break markers and section-sized continuous
surfaces. It does not render automatic native pagination or page-margin
header/footer placement. The separate header/footer scope editor is described
below. Browser printing uses the same safe projection on a disposable
model copy; it does not change native XML or associations.

### Column/tab authoring evidence (full 4D F0012102)

`wp_layout_probe` creates document/default/section column and paragraph-tab
archives independently of the web model. `Output/layout-report.json` retains
49 primary cases (four column variants and 45 alignment/leader combinations),
named-style/direct-format cascade/reset observations and ten HTML-import
counterexamples. Genuine 4WP archive-import probes also confirmed inline
tab overrides before model implementation. The full gate compares independent
`wp_layout_apply` mutations against actual model/browser exports, native
effective getters and exact native reexports, not merely ZIP readability.

- Native document defaults use `div.section0 { column-count:2;column-gap:18pt }`;
  numbered sections override each independently. Native reset removes only
  the count/gap overrides. Existing `column-rule-*` declarations survive.
  Factory values are one column and `12pt`. Native supports counts through 20.
  The editor additionally requires gaps to leave positive usable text width
  in every affected section; native accepts gaps that produce unusable layout.
- Paragraph `-d4-tab-stop-offset`, `-d4-tab-stop-type` and
  `-d4-tab-stop-leading` are parallel arrays. The **last** entry describes
  default repeating tabs. For example `36pt 72pt 18pt`, `left right center`,
  `'' '.' '_'` means absolute left/right stops at 36/72 pt, then an 18 pt
  center-aligned repeating interval with underscore leaders.
- Native types are left (`0`), right (`1`), center (`2`), decimal (`3`) and
  bar (`4`), for both absolute and default tabs. No leader, dot, dash and
  underscore survive the supported setter/import/export/reopen matrix.
  Other single characters can work (Japanese/non-BMP examples are retained),
  but multi-character leading strings are truncated. Quote/backslash leaders
  expose native parsing/reexport losses; these are not supported editable
  leaders and are not represented as a successful native roundtrip matrix.
  Their editor no-op exports are separately checked for byte identity.
- Native tab reset is **not style inheritance reset**. Resetting tabs/defaults
  on a paragraph with a tabbed named style materializes factory values:
  no absolute stops, a `1.25cm` left interval, no leader. A different paragraph
  without that named style can instead lose its generated override entirely.
  The editor writes the effective factory group, leaving the named style and
  unrelated paragraph declarations untouched. Removing one stop preserves
  the other stops and the default interval/type/leader, including fractional
  precision and different settings across selected paragraphs.
- Native defaults applied at document level can materialize on paragraphs
  rather than becoming an inheritable body CSS rule. Supported native exports
  use named `p.Name,li.Name` rules, generated `_pN` direct-format rules and/or
  inline overrides. Partial offset-only formatting retains style-supplied
  type/leading arrays when lengths agree. The editor protects ambiguous scopes,
  malformed arrays and unverified style combinations instead of flattening them.
- U+0009 remains a real UTF-16 text character. Browser entry uses registered
  native splices and existing table/formula/bookmark guards; formatting does
  not change those offsets. Independent native cases include inline images,
  table-cell tabs, Unicode, formulas and hidden headers.

The browser balances columns between explicit breaks on its continuous surface and uses
the default tab interval as approximate CSS spacing. It does **not** implement
absolute tab alignment, bar/decimal alignment, leaders, native font metrics,
native automatic page flow.

### Browser print projection (available on main)

Named CSS pages use oriented native paper dimensions and four margins. Explicit
page/new-page section breaks create browser pages. Continuous sections with the
same geometry can share a page; changing geometry forces a browser page, unlike
native continuous flow. Tables are fitted/wrapped to content width and safe
rasters constrained to content width/height. Original sizes, declarations,
formula subtrees, hidden associations and resources remain authoritative and
unchanged in the `.4wp` model. Unsupported structures remain visible placeholders.
Browser print results are not native-equivalent pagination or font/tab rendering.

`wp_print_probe` supplies independent native-created originals, native PDFs and
effective geometry/column/tab getters. The browser gate checks paper boxes,
content tokens, word bounds, image presence and byte-identical `.4wp` downloads
before/after printing. Native and browser PDF comparisons establish scoped
geometry/content only, not arbitrary visual, wrapping or automatic page-count
equivalence. Right-aligned leader tabs are retained as a deliberate unsupported
rendering comparison, not converted to fabricated leader text.

Headers and footers follow the body as
`<div class="section1Header|section3FirstHeader|section1LeftHeader|…Footer" style="visibility: hidden; height: 0">`.
Their rules hold `margin` (distance from the paper edge, sides, gap to the
body). Every section gets its own copy. A page uses the header and footer of
the section it starts in: with a continuous break, the new section's header
appears only from its next page. With `-d4-page-first-right:false`, page 1 is
a left page.

### Header/footer editing evidence (available on main via #49; full 4D F0012102)

`wp_header_probe` creates seven independent native cases: default, first page,
left/right, right/left, immutable text formulas, header-bookmark rejection and
custom distances. Fourteen stages per case retain original and mutated `.4wp`
files, native-original PDFs, effective area getters, local selected text/range
coordinates, body bookmark/range units and geometry. The gate compares web-model
and real browser downloads with those independent native mutations after
import/export/reopening. This is section-aware content editing, not browser
pagination or native field evaluation.

- `WP Get header/footer` on an absent later section returns no area; content
  does not inherit from the preceding section or `section0`. Document defaults
  still supply section geometry. A stored default area is section-local.
- Native subsection creation copies the section's current default header/footer.
  Creating left also creates right, and conversely. First/left/right enabling
  rules export as `div.sectionNFirst|Left|Right { white-space:normal }` with
  separate trailing `sectionNFirst|Left|RightHeader|Footer` divs. Native disabling
  removes the selected subsection; disabling left/right removes the pair.
  Editing one stored area's text does not change the default or opposite
  subsection. The merged text editor edits existing areas; the separate
  unmerged variant increment below adds enable/disable controls.
- Each area has its **own** UTF-16 range domain starting at 1. Supported text
  formulas consume one local native slot, independently of cached/source length.
  Unicode insertion, paragraph/line breaks and formatting in an area do not
  change body bookmark pairs or body text. `WP NEW BOOKMARK` on a header range
  returns native error **110**; the editor does not invent a header bookmark
  coordinate scheme or route header edits through body bookmark splices.
- Native default creation exports an empty ordinary paragraph in a hidden
  trailing area. At 36 pt page margins, headers use
  `margin:1cm 36pt 0.5cm` and footers `margin:0.5cm 36pt 1cm`.
  Independently set four-sided distances survive text/formatting edits and
  reimport. These area margins are distinct from `-d4-page-margin`; the
  serialized wrapper's `height:0`/hidden visibility is not an editable physical
  header height. Existing area CSS and native geometry stay authoritative.
- Splitting an associated body section can copy and renumber its areas; merging
  can discard associations. The preexisting section-structure protections remain
  in force. Default-area create/remove is exposed only for sections without
  variants. Removing an area with a formula, unsupported object or ambiguous
  association is protected, not interpreted as permission to discard that object.

The text/formatting scope transaction permits changes only inside one identified div and checks
that all other serialized XML is unchanged, including metadata, body bookmarks,
nonactive variants and anchored associations. Default-area create/remove likewise
checks all XML outside the exact target wrapper and its exact CSS rules.
Original formula nodes and archive
resource bytes are immutable. Tables, pictures, protected/anchored content,
unsupported references and lists within areas have explicit capability notices.
Browser print includes supported stored content once in a labeled appendix,
not repeated page margins; native 4D remains the compatibility/placement authority.

### Header/footer variants and positioning (in progress; full 4D F0012102)

`wp_variant_probe` independently creates nine native cases and thirteen stages
per case. `Output/variant-report.json` retains effective subsection/area getters,
body bookmark pairs, local Unicode/formula ranges, geometry and native margin
validation. Associated `.4wp` files and multi-page native PDFs are authoritative;
`variant-pdf-report.json` records scoped word-coordinate/content assertions.

- Enabling first copies **both** current section-default areas, including their
  four margins and immutable formula subtrees. Header-only/footer-only defaults
  copy only the present kind. Empty sections gain enabling rules but **no area
  content**. Nothing inherits from another section. Enabling either facing side
  creates both sides from defaults, not from first-page or the opposite variant.
- Disabling first removes its stored header/footer wrappers and enabling/area
  rules. Disabling either facing side removes the **pair**, including independently
  edited nonempty text. Defaults and other subsections remain untouched.
  Re-enabling freshly copies defaults, not the removed content. The UI confirms
  destructive removal and makes it atomic for undo/version/recovery; immutable
  formula removal and unknown/ambiguous associations/declarations stay guarded.
- First-page content takes priority over facing-page content. Native PDFs cover
  a three-page first section plus an absent-area second section. With
  `-d4-page-first-right:false` and landscape orientation, the second physical
  page uses the right variant and the third uses left; the first uses first-page
  content. The next section does not borrow the preceding section's areas.
  Separate native deletion/creation counterexamples prove that an absent area
  inside an **enabled** first/facing subsection does not fall back to the
  section-default area. Removing a default does not remove already-copied
  variants. Creating a first-only header does not populate other scopes.
- Native area `margin` stores top/right/bottom/left, independently of the body's
  `-d4-page-margin`. Native setters preserve fractional values/units and export
  the four-side group; negative values raise error 204, while zero and even
  off-paper values are accepted. Changing body page margins does not rewrite
  stored area margins or copy them into variants. Native PDF footer coordinates
  can nevertheless move with the body's bottom margin.
- Header top/left and footer top/left positioning are independently checked in
  PDFs against native mutations. The wrapper's hidden `height:0` is serialization,
  **not** a physical editable height. Content height is automatic. The editor
  saves four explicit native margins, conservatively requiring finite values
  through 10,000 pt and positive remaining oriented paper dimensions; it does not
  claim exact native body-clearance or font/layout calculation.

Variant transactions exclude only their precisely enumerated subsection/area
wrappers and exact rules from the outside-XML invariant. Formula copies must be
byte-identical subtrees; original formula node identities/order remain immutable.
Position-only transactions preserve all body XML/bookmarks/formulas/resources,
unknown declarations and sibling areas. Unsupported/shared/conditional/inline or
unverified longhand margins are protected rather than normalized. Browser
projection remains inert and allowlisted. Continuous browser printing presents
stored content once in a labeled appendix, **not** native repeating placement.

### Paged browser projection (#60 deployed snapshot; vertical row bands in this version)

`wp_paged_probe` extends the existing full-4D print gate with four independent
six-page, two-section documents and native first-footer edit targets. Right-first
(including the omitted native default), explicit first-left, mixed section
orientation and deleted first-header/right-footer cases are checked through
native PDF words, section/area getters and import/export/reopen.

The browser projection selects first-page content on each section's first
browser page, then paired facing content using physical document page parity
and `div.section0`'s `-d4-page-first-right` flag; otherwise it selects the section
default. An enabled but absent area stays empty. Native area content is neither
inherited across variants/sections nor fabricated. Unselected stored areas are
retained once in a labeled browser appendix.

The merged #53 projection paginates whole, fitting, single-column paragraphs.
The merged #54 increment also cuts paragraphs/flat list items at measured browser
line boundaries and admits locally decoded inline pictures as indivisible atoms.
Graphemes, source whitespace and styled wrappers remain intact; only disposable
DOM fragments are created. Native flat sibling lists retain positional numbering
and per-item indentation rather than being turned into arbitrary nested HTML.
Explicit page/new-page-section boundaries and effective
section paper geometry are projected on disposable models. Browser header-top
and footer-bottom margin bands use stored area margins but deliberately do
**not** claim native vertical coordinates, body-clearance calculation or page
counts. Unsupported shapes/settings, unsupported continuous seams, oversized lines/atoms
or unsafe bands retain continuous view/printing with an explicit notice.
Neither projection changes source XML/resources, formulas, bookmark coordinates,
editing scopes, history or recovery.

`wp_expanded_paged_probe` independently creates long formatted paragraph, native
flat-list/level and inline-picture/formula documents, native first-paragraph edit
targets, bookmark ranges and PDF references. Browser page-token membership,
decoded image presence, measured bounds and original/Undo/recovered-Redo exports
are checked separately. Native import/export/reopen checks effective getters,
exact native reexported body/CSS, raw bookmark pairs, formulas and resource bytes
against the independent native targets. Native PDF page counts remain reference
evidence, **not** a layout-equivalence assertion.

`wp_paged_table_probe` adds independently native-created rectangular tables,
unequal 70/130 pt columns, row borders/padding/backgrounds, cell formatting and
bookmarks, plus a mixed-section inline-picture/formula case. `wk header row count`
serializes header membership as `-d4-header:true` on contiguous leading `tr`
rules, not a `thead` wrapper or a `th`-tag inference. Native PDFs independently
establish repeated headers; `wp_paged_table_stats` compares native header counts
and every cell's width, padding, text, color, background and bold attributes
after browser export and native import/reopen against independent originals and
first-header edit targets. Existing body protection for bookmarked documents
with hidden areas is unchanged; the gate uses the independently editable header
scope for Undo/Redo/recovery rather than admitting a protected body operation.

The browser uses the shared native grid validator and permits direct rows with
horizontal merges, vertical row bands and at least one width-witness row that owns
every column unmerged, with
paragraphs or supported bounded flat cell lists. It measures the complete table once at the
section's width, freezes the measured column geometry in disposable DOM, and
places complete rows (or whole vertical bands) on pages. Leading native header rows repeat explicitly;
every data row/cell appears once. Fragment cell widths/heights must remain within
0.25 CSS px of the whole-table measurement. No-witness, header-crossing bands,
nested/irregular/data-source
tables, unsupported cell lists, invalid/nonleading/all-header metadata and rows or bands that cannot
fit with their headers use explicit continuous fallback. The scope is bounded
to 1,000 rows and 10,000 cells per table and the existing sheet/grapheme budgets.
Source table XML, media, formulas, bookmarks and editing/recovery/history remain
immutable. Browser row/page counts, carry-over rows, native row splitting,
border-conflict behavior and automatic native pagination parity are not claimed.

The table-cell-list increment is **Available/deployed via #59**.
`wp_cell_list_probe` independently authors 18 installed-4D originals, header/body
edit targets and PDFs, with paragraph-level getters and unequal 90/140 pt columns.
Flat native lists may coexist with cell paragraphs. A contiguous `ol start="7"`
with two items prints 7 and 8; applying a start to both native paragraphs produces
two separate `ol start="7"` elements, both printing 7. Starts are independent
between cells and rows. Whole-cell start getters may return the native mixed
value sentinel (-2147483648); paragraph getters and the original XML remain
authoritative, never a made-up common counter.

Supported cell styles are `disc`, `circle`, `square`, `hollow-square`, `diamond`,
`decimal`, lower/upper Latin and lower/upper Roman. Independent native PDF
codepoints establish cell `disc` as U+25CF and `diamond` as U+2666; the shared
marker helper applies these only in cell context, retaining existing body output.
The subset preserves native list font, indentation, computed bold/color, wrapped
items, mixed cell paragraphs, decoded local pictures and inert formula subtrees.
Counters remain 1-3,999 with the existing single-`#`, quoted LTR format subset.
At most 10,000 list items are admitted per table, in addition to the existing
row/cell/grid/sheet/grapheme limits. Nested, reversed, per-item-value,
paragraph-wrapped, custom/unknown-level lists and unsafe marker/cell geometry
explicitly fall back. Content and markers must remain inside their own complete
cells within 0.25 CSS px. List-bearing native leading headers repeat without
counter loss or duplication. Prepared disposable lists are measured with the
whole table once, before the same frozen-grid complete-row preview/print path.
Source XML/resources, native ranges, selection and history/recovery are unchanged.
No table authoring, row splitting, nesting or native pagination
parity is added. #57's compatible continuous-section pages are Available on main
and deployed; broader layout/native parity remains Proposed and unscheduled.

Horizontal-span support is **Available/deployed via #60**.
`wp_colspan_probe` independently creates ten installed-4D originals, pre-merge
and split mutations, getter records, safe header/body edit targets and native PDFs.
It establishes unequal 50/70/110 pt column settings, witnesses after merged rows
(including row 6), zero/one/two native leading headers, rich merged header lists,
inline formatting/inert links, local pictures and an inert native formula
inside surviving merged cells. A compatible area-free seam uses residual capacity.
Alternating merges without any complete witness, vertical spans and mixed spans
remain excluded based on their actual native serialized shape. A native merge
covering entire rows can collapse rows or columns rather than preserve the
requested span: command arguments alone are not an admission oracle.
The installed native exporter retained no distinguishable cache for the computed
formula, even with visible references disabled; the browser displays its existing
unavailable-cache notice, not an invented result. Cached values remain supported
when actually stored. The same rich table with two headers exceeds the available
row height and independently establishes terminal atomic overflow fallback.

Under #60 all `rowspan` values had to equal one (vertical row bands below lift that). The shared native grid validator must confirm
complete, nonoverlapping coverage; at least one fully unmerged row supplies every
underlying browser column width. The complete table is measured in its owning
physical flow, then frozen and cloned by complete rows with original `colspan`
attributes. All inline atoms/markers stay in their owning cell, and every fragment
cell retains whole-table width/height within 0.25 CSS px. Unstable geometry is
rejected, never clipped, stretched or shrunk. Native width getters and browser
collapsed-border/intrinsic dimensions are separate evidence, not an equality
or native wrapping/pagination/page-count/border-conflict parity claim.
Authoring, native-range/bookmark guards, formula execution, row splitting,
continuous-section/multi-column admission and all existing budgets are unchanged.

`wp_paged_column_probe` independently authors seven full-4D documents: two,
three (zero gap), four columns, explicit column/page breaks, a landscape section
with a three-column override, a divider-rule counterexample and a five-column
narrow counterexample. Original/first-header edit targets retain body bookmarks,
lists, a local picture, a text formula and first/facing/default areas. Effective
`wk column count`/`wk column spacing` and section paper getters are recorded
alongside independent native PDFs, rather than treating browser exports as a
column-layout oracle.

Native equal columns occupy the oriented page's text width less `(count-1)*gap`,
divided by `count`. The two-column 480-by-420 pt explicit-break oracle has
60 pt vertical/36 pt horizontal margins, 18 pt gap and 195 pt columns. Native PDF
`COLA` starts at x=36 pt, `COLB` at x=249 pt on the same page; a second column
break puts `COLC` at x=36 pt on page 2. A page break puts `PAGED` on page 3,
not the unused second column of page 2. The first/left/right headers follow
physical pages, not column slots. Native paragraph column breaks serialize as
`break-after:column`, distinct from `page-break-after:always`.

The available #56 browser subset admits 2-4 equal LTR columns without divider
rules, gaps from 0 through 72 pt and at least 72 pt of text width per column.
It reuses the count/gap resolver, oriented paper geometry, measured visual-line
fragments, native list markers and indivisible local image/formula atoms.
Disposable column slots fill sequentially top-to-bottom then left-to-right;
the last page is deliberately not balanced. Explicit page breaks skip remaining
slots and new-page sections reset geometry and first-area selection. The
same finished DOM is cloned for browser print. Every supported body character
occurs once; shared inline ancestor wrappers are retained even on middle
fragments. Native page counts, final-column balancing, word wrapping and formula
evaluation are not reproduced. Multi-column tables, divider rules, custom
column shapes/spanners, RTL/vertical flow, nested/conflicting breaks and
out-of-bound geometry use localized atomic continuous fallback. Single-column
table behavior and all established limits/protections remain unchanged.

`wp_continuous_paged_probe` independently creates 14 native originals and
mutation targets with native section names, inherited/explicit geometry,
break/column getters, tail bookmarks and PDFs. The compatible one-column,
area-free cases continue on the occupied page, including a seam after automatic
overflow. An explicit page break before the seam, successive continuous seams
and a later new-page section retain physical page progression.

The native margin-change counterexample places section 2 at x=72 pt on the
same physical page, rather than inserting a page. The orientation counterexample
starts a 420-by-480 pt second page after a 480-by-420 pt first page.
Default and first/facing area counterexamples establish that a shared page keeps
the areas of the section that started it. In the overflow first/facing original,
section 2 starts on physical page 3 under section 1's right header; physical
page 4 uses section 2's left header, **not section 2's first header**.
These observations do not establish general native wrapping, column balancing,
exact pagination/page counts or footer coordinates.

The in-progress browser subset permits only identical effective paper,
orientation, all margins and one-column count/gap on both sides, without stored
areas, enabled first/facing variants or column breaks. Empty areas/variants are
not treated as absent. Compatible seams retain the current disposable flow;
new sheets are created only for measured overflow or existing explicit page/
new-page boundaries. Sheet ownership is its starting section; per-fragment
section identities and participating-section metadata remain separate from
physical page numbers. Original names, inheritance, XML/resources, bookmarks,
formulas, editing state and recovery remain authoritative and untouched.
Existing admitted paragraph/list/image/formula and rectangular table handling
is reused without relaxing authoring guards. A rich-content browser regression
checks residual seam capacity, later table fragments, stable widths, repeated
leading headers, complete ordered fitting content and exact print membership.
Geometry-changing, area-bearing, multi-column or otherwise unsupported seams
use localized atomic continuous fallback. #57 is available on main and deployed;
Vertical row bands are **implemented in this version** (milestone M1), not merged
or deployed. `wp_rowspan_probe` independently creates thirteen installed-4D
originals (`vertical`, `header`, `two-headers`, `mixed`, `unicode`, `lists`, `rich`,
`media`, `seam`, `chain`, `tall`, `header-cross`, `no-witness`) with the requested
merge list, native getters, safe header/body edit targets and PDFs, on 300×360 pt
paper with unequal 50/70/110 pt columns. Observed full 4D 21.2 `F0012102` behavior:

- `WP TABLE MERGE CELLS` with a row count serializes `rowspan` on the surviving
  cell, which holds the covered cells' paragraphs in reading order; covered rows
  keep only their remaining cells. A 2×2 merge serializes `colspan` and `rowspan`
  together.
- A merge covering every column of two rows **collapses into one row**: the
  second row is removed, its text joins a `colspan="3"` cell and no `rowspan` is
  written (the `mixed` original has 25 rows, not 26). Row counts therefore come
  from native getters, never from the requested arguments.
- With `wk header row count` 1, a merge from the header row into the first body
  row is **silently declined** (no error, no span). The native API did not produce
  a header band crossing into the body; such XML stays protected in the browser.
- Native PDF pagination **splits** vertically merged cells and their bands across
  pages (for example `vertical` page 2 starts inside the rows 9–11 band). The
  browser intentionally keeps each band whole instead; this is a documented
  difference, not parity.
- In a first probe run, a disc list in a 50 pt merged cell wrapped `R10A` as
  `R10`/`A`, and the rich PDF **omitted row 19 entirely** at a page boundary
  (retained as `4wp-rowspan-20261114-probe-01`). After moving the list and formula
  into the 110 pt column, every serialized token appears exactly once in every
  native PDF, with leading headers repeated on each table page.

Browser admission: the shared grid validator must confirm complete, nonoverlapping
coverage, and a width witness must own all grid columns itself (a row covered by a
vertical merge never qualifies). Rows tied together by `rowspan`, including chained
merges, form one band; leading native headers must end on a band boundary. Bands
are placed whole after the whole-table measurement and frozen geometry; each band
keeps its original `rowspan`/`colspan`, and every fragment cell keeps whole-table
width/height within 0.25 CSS px. A band that cannot fit on an empty page with its
headers (`tall`, and `rich`, where the browser's protected formula display beside a
four-item cell list is taller than the page body) falls back with the localized
`pagedBand` notice. No-witness grids keep `pagedTables`. Authoring, native-range
guards, formula execution, row splitting and all budgets are unchanged; native
wrapping/pagination/page-count/border-conflict parity remains Proposed.

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

### Scoped web media evidence (full 4D F0012102)

The independent `wp_media_probe` creates anchored pictures (`img1`) and text
boxes (`textBox1`) with default, explicit paper, section-2, alignment, formula,
nested-image and transformed-picture variants. Seven stages export original,
geometry, text replacement, formatting, layout, picture removal and box removal.
All stages retain the exact body text/range and original raw body bookmark.
`WP Text range(box; 1; 4)` replaces `BOX`, not body characters at those coordinates.
The native getters and native PDF text bounds are the oracle, not the browser DOM.

Default added pictures have auto dimensions, all-page/all-section anchors,
paper origin (getter `3`), zero offsets, no alignment and behind layout. Native
text boxes start on page 1/all sections, paper origin, width `8cm`, auto height,
padding `4pt`, white background, solid `1pt` border and front layout.
The picture display-mode getter returns `scaledToFit` by default and
`proportionalCentered` after the independent mode-change stage; geometry-only
targets retain the original mode. This getter requires a string-compatible
output variable, unlike the integer anchor/layout getters.
Setting a specific section preserves its association independently of source
DOM order. Offset setters do not remove existing center/right/bottom alignment;
the web editor therefore protects offset controls for aligned objects rather
than treating alignment as an interchangeable coordinate.

Full-4D import/reopen counterexamples establish that box width/height/offset
overrides on the root `div`'s inline `style` are ignored, even though the same
picture overrides work. Box geometry must update the unique native
`div._divN` rule associated with `textBoxN`. The scoped transaction excludes
only that rule's four geometry declarations from its outside-XML comparison;
all other declarations, selectors and source text remain authoritative.

For the independently observed single-codec TCP4 v8 wrapper, little-endian
header fields at offsets 8/12/16/20/24 are codec count, payload byte length,
codec-record byte length, metadata byte length and a zero reserved field.
At 28 is a negative UTF-16 codec-name length, followed by that name. After the
codec record and metadata span are 24 reserved zero bytes, then an eight-byte
payload offset/length record. The bounded web extractor requires exactly one
PNG/JPEG codec, matching lengths/offsets and a complete supported raster
envelope; it never searches arbitrary metadata for a codec signature.
This is a deliberately narrow observed representation, not a general TCP4 spec.
Native affine/display metadata stays opaque and authoritative; extracting its
payload is a labeled display-only projection, not a source conversion.

The merged #51 media baseline retains object IDs, all association/layout/display attributes,
nonactive XML/formulas/resources and body bookmark pairs. Ordinary box
text/formatting and validated paper-origin size/offset edits use isolated
transactions; creation/removal, association/alignment/layout/display-mode
changes, nested identity-bearing content, unknown metadata and formula pictures
remain protected. Supported stored objects print once in an isolated appendix,
not at native page coordinates. See the [editor support contract](../web-editor/README.md#advanced-images-and-text-boxes-available-on-main).

### Object lifecycle and placement (in progress; full 4D F0012102)

`wp_object_probe` independently constructs three native documents with two body
sections, Unicode text, a body formula/bookmark, a nonactive picture, a formula
text box and a section-1 header. Its fourteen stages add a second picture and
box, change document-page or section association, align, clear alignment/edit
offsets, change front/behind/square-wrap relationships, repeat on all pages,
delete each added object and recreate objects. Native getters and exports, not
browser-generated documents, are the oracle. The third document uses an
independently native-encoded JPEG, including exact-byte browser creation and
native reopening, rather than assuming PNG evidence covers both authoring
codecs. All stages retain the body text
tape, body native ranges and raw bookmark coordinates.

- New native pictures and boxes obtain independent IDs (`img2`, `textBox2`);
  the box uses its identity-owned `div._div2`. Explicit dimensions/page/layout
  survive independently of the preexisting objects. Browser creation emits
  explicit paper-origin defaults (page 1/front) rather than assuming ordinary
  HTML positioning. Native box content is an independent paragraph scope.
- Document page 2 exports `-d4-anchor-page:2` with no section restriction.
  Section 2/all pages exports `-d4-anchor-section:2` and omits the page
  declaration. All pages/all sections omit both. The browser only authors these
  evidenced combinations; specific-section/specific-page combinations stay
  protected. Unchanged imported associations are retained.
- Right/bottom getters are `1`, center is `2`, and left/top/no alignment is `0`.
  Setting alignments to zero removes the serialized alignment declarations.
  It does not erase stored offsets. Offset setters alone do **not** clear an
  existing nonzero alignment. The browser removes declarations from the unique
  owned rule and any picture inline override when explicitly clearing alignment; it
  never substitutes a CSS `none` or invents a second left/top mode.
- Layout getters are behind `0`, front `1`, square wrap `3`, serialized as
  `behind`, `front`, `wrap-square`. Both pictures and boxes export `z-index:-1`
  behind text and remove it for front/square wrap. Native export can reorder
  the trailing object elements while keeping their IDs and body tape intact;
  source DOM order is not a native layer model. The section-2 behind-box
  counterexample exports `textBox2` with class `_div1`, and the nonactive
  `textBox1` with `_div2`. Class numbering is **not** the native object ID.
  Editing must follow the actual, unique owned class and rule, never derive
  `_divN`/`_imgN` from an object's ID suffix.
  Arbitrary imported z-index values and unverified inline box placement remain
  protected, not interpreted as evidence-backed native geometry.
  Returning a section-scoped box from behind to front can also retain a
  different getter-enumeration order after import/reopen. The new gate matches
  object getters by native ID, not array index, while independently requiring
  unchanged nonactive source XML and element order.
- Native deletion removes the targeted object without moving body bookmark
  endpoints or deleting the nonactive formula box/header/picture. Recreation
  can reuse the deleted native IDs; browser creation deliberately does not
  reuse IDs/classes still referenced by retained CSS or opaque metadata.
  Browser deletion preserves orphaned CSS and archive resources and refuses
  formula-bearing, referenced, nested, unknown or ambiguous objects.

All browser actions retain nonactive source XML, complete formula subtrees,
original media URIs/bytes and raw bookmark pairs, and use document-wide
history/version/recovery transactions. The guide/print appendix does not
simulate these native placement, wrapping, layer, repetition or pagination
semantics. Other origins, arbitrary layers/wrap modes and picture display-mode
changes remain native-only. See the [in-progress support contract](../web-editor/README.md#object-lifecycle-and-stored-native-placement-in-progress).

## Preview limits

The preview rebuilds documents from a fixed vocabulary of elements and
validated CSS values; nothing from the document reaches the page unfiltered.
Pages split at hard breaks only (no reflow across pages), text wrap around
anchored objects is not simulated, links do not navigate, and very large
documents are cut after about 8,000 paragraphs with a notice.
