# 4WP Editor

A standalone, local-first HTML/CSS/JavaScript editor for ZIP-packaged 4D Write
Pro `.4wp` documents. It has no dependency on Swift, Quick Look, a backend, or
the 4D runtime. Files are processed in the browser and are not uploaded.

## Roadmap and status

Status snapshot: `main` at
[`94915de` / #60](https://github.com/miyako/4d-ql/pull/60).
**Available** means merged there; **In progress** is an unmerged increment (none currently);
**Planned** is approved subsequent work, not implemented here;
**Proposed** is an unscheduled idea requiring further decisions.
Phase numbers below organize this roadmap, not past PR numbers.
Page setup, sections/breaks, columns/tabs and preview/printing are available on main;
deployment status is separate. The table is not a
promise of dates or full Write Pro parity.

| Phase | Feature scope | Status |
| --- | --- | --- |
| 1. Foundation | Genuine `.4wp` import/export, original XML/resources retained, local processing, six UI languages, themes and responsive UI | Available |
| 2. Everyday editing | Cross-run text/selections, formatting/styles/lists, basic tables/images, links, sanitized paste, find/replace, counts/zoom, undo/redo, versions and local recovery | Available |
| 3. Native verification and bookmarks | Full-4D import/export/reopen gate; scoped paragraph/flat-list/inline-object bookmark adjustments; unsupported ranges protected | Available; scoped evidence, not arbitrary compatibility |
| 4. Bookmarked tables and native list levels | Same-cell text/paste/cut, paragraph/list and inline-object edits; simple table insertion, row edits and column deletion; native indented/mixed-marker lists. Partial cross-cell bookmarks, column insertion and nested HTML stay protected | Available on main via #39 |
| 5. Bookmark management | List, navigate/highlight, create from selections/carets, rename and delete native bookmarks; exact names, native range validation and atomic history/recovery | Available on main via #40 |
| 6. Formula-aware protected display | Source and stored cached values only when actually available; explicit unavailable-value notice; scoped safe surrounding edits, no evaluation | Available on main via #41 |
| 7. Broader table/range safety | Cell-anchored column insertion; interior cross-cell bookmark management, formatting and guarded additions; grid-validated merged-cell text editing; localized capability reasons | Available on main via #42; destructive cross-cell operations, merged structural edits, nested tables and generic ranges remain protected |
| 8.1. Page setup | Document-level paper presets/custom dimensions, orientation, margins and preference-only units; inherited section values retained | Available on main via #43; deployment status is separate |
| 8.2. Sections and breaks | Insert/remove page and section breaks; defaults and section-specific settings without flattening inheritance | Available on main via #44; deployment status is separate |
| 8.3. Columns and tabs | Column count/gap and paragraph tab stops, with explicit preview limits | Available on main via #47; deployment status is separate |
| 8.4. Preview/output | Section-sized continuous preview and local browser printing without claiming exact 4D pagination | Available on main via #48 |
| 9. Headers and footers | Section-aware text/formatting in stored default/first/left/right areas, protected default-area creation/removal, labeled print content appendix | Available on main via #49 |
| 9.1. Header/footer variants and positioning | Section-local first-page and paired left/right toggles with native copying/removal semantics; four native area margins | Available on main via #50 |
| 10.1. Advanced images and text boxes | Bounded native picture decoding, isolated anchored-picture/text-box views, scoped box text/formatting and object size/offset editing | Available on main via #51 |
| 10.2. Object lifecycle and stored placement | Guarded picture/text-box creation and deletion; native section/page targets, alignment and front/behind/square-wrap metadata | Available on merged main via #52 |
| 10.3. Paged browser preview | Best-effort, read-only single-column paragraph pages and repeating supported first/facing/default headers/footers; matching browser print projection and explicit continuous fallback | Available on merged main via #53 |
| 10.4. Expanded browser pagination | Measured paragraph fragments, supported flat native lists and local inline images in read-only paged preview and matching print | Available on main via #54 |
| 10.5. Paged tables | Measured row-boundary fragments of rectangular paragraph-cell tables, stable columns and repeating native leading header rows in preview and matching print | Available on main via #55 |
| 10.6. Paged columns | Bounded equal-column, sequential paragraph/list/image flow with explicit column breaks and matching browser print | Available on main via #56 |
| 10.7. Continuous-section pages | Area-free compatible single-column boundaries share measured pages and matching browser print; unsupported seams retain explicit fallback | Available on main via #57; deployed |
| 10.8. Paged table-cell lists | Native-evidenced bounded flat cell lists, mixed paragraphs, stable unequal columns and list-bearing leading headers in read-only pages and matching print | Available on main via #59; deployed |
| 10.9. Paged horizontal table spans | Native-evidenced horizontal-only merges with a fully unmerged width-witness row, stable frozen geometry and complete-row/header fragments | Available on main via #60; deployed |
| 10.10. Further layout parity | Vertical/mixed spans, area-bearing or geometry-changing continuous seams, multi-column/complex table pagination, divider rules, arbitrary object wrapping/layers and native-equivalent pagination/balancing | Proposed; unscheduled |
| 11. Release readiness | Accessibility, mobile usability, compatibility matrix, persistence/export reliability and release criteria; improvements remain incremental throughout | Proposed completion criteria |

Steps 8.1–8.4, header/footer variants/positioning and advanced media are available
on main. #60 was deployed by successful Pages run
[`43515562104`](https://github.com/miyako/4d-ql/actions/runs/43515562104)
at `94915de6bd21dfe2c8f33b50106a315951ed5148`.
No increment is currently in progress; the feature campaign is paused and
10.10/11 remain **Proposed**. Arbitrary wrapping and
automatic native pagination remain unscheduled proposals.
Native formula execution/a 4D backend, real-time collaboration and exact
full-Write-Pro parity are **not approved features**.
The [preservation contract](#preservation-contract-and-limits) and
[native gate](#full-4d-release-gate) define today's concrete limits.

## Run

Requires Node.js 22.12+ (or Node.js 20.19+).

```sh
cd web-editor
npm ci
npm run dev
```

Open the localhost URL printed by Vite. `npm run build` produces `dist/`;
serve that directory with a static HTTP server. `npm run preview` serves the
production build locally. Opening `index.html` directly with `file://` is not
supported. Dependencies are bundled locally, not loaded from a CDN.
Production builds include their license texts in `THIRD_PARTY_NOTICES.txt`.

## Page setup (available on main)

**Page setup** in the toolbar opens keyboard-accessible document-default
controls in all six languages and system/light/dark themes. A3, A4, A5,
Letter, Legal and Tabloid use native whole-point dimensions; custom base
width/height, portrait/landscape and four margins are also editable. Apply
commits the entire change as one undo/redo, version and IndexedDB recovery
transaction. Escape or Close returns focus to the toolbar without applying.

Select mm, cm, in or pt as a local preference. Switching units, opening/closing
the panel or applying unchanged values does not rewrite native geometry or
create undo steps. Unchanged imported margin values retain their original
units/precision. New paper dimensions follow the observed 4D rounding to whole
points; the resulting oriented point size is displayed **before** Apply.
Orientation swaps the base dimensions, even for custom width greater than
height; it does not sort them. There is no silent clamping.

Supported paper dimensions are 1–10,000 pt and margins are nonnegative, at most
10,000 pt (or equivalent units). Opposing margins must leave a positive text
area both in document defaults and after retaining section overrides.
Invalid/nonfinite values and section conflicts produce localized errors with
no document mutation. These are conservative editor limits, not claims about
4D's maximum page size; native setters even accept zero-sized paper and margins
larger than the paper, which this UI deliberately rejects.

In document-default scope, only native `div.section0` geometry is changed. Existing `div.sectionN` overrides,
unknown declarations, original body/formula/table XML, bookmark metadata and
archive resources are retained. Geometry-only transactions can change defaults
even when text edits are protected, but never relax those text/structure guards.
Unsupported/invalid geometry, nonnative selectors, nested conditional geometry,
`!important`, inline geometry, subsection geometry and unverified margin
longhands protect **all paper, orientation and margin controls**, with a
specific notice; the preference-only unit selector stays usable.

The preview reflects physical paper width, minimum height and margins. The merged
preview/printing phase provides section-specific white surfaces and browser printing as described
below; neither is an automatic native pagination engine.

## Sections and breaks (available on main)

The same **Page setup** panel identifies the active native section and offers
document-default or numbered section settings. Native sections are inferred
from the flat body's paragraph break declarations, not invented DOM wrappers.
Section names are shown in the selector and can be edited without trimming or
normalization (up to 1,024 UTF-16 units). New names with quotes, backslashes,
control characters or leading/trailing whitespace are rejected: independent
native exports/reimports lose or normalize those names. Existing names remain
preserved when unchanged. Paper dimensions
remain document-wide. Orientation and the four-margin group can either inherit
document defaults or have explicit section overrides; checkboxes and status
labels distinguish those states. Resetting inheritance removes only that
group's declarations, including duplicates, rather than copying current defaults.
Other section/subsection declarations, names, headers/footers, anchored objects,
body XML, formulas, bookmark pairs and archive resources remain authoritative.

**Insert at caret** supports hard page breaks, new-page section breaks and
continuous section breaks at a collapsed text caret in a supported top-level
paragraph without an existing break. Start, interior and end boundaries,
Unicode and positions adjacent to immutable text formulas are covered.
Section insertion is limited to the last section, with no hidden associations,
subsection declarations or unsupported settings; it copies the last section's
explicit orientation/margins into the new unnamed section, as observed natively.
Existing section indices and names are not renumbered or rewritten.
Page-break insertion does not add a section.

**Remove selected break** converts the selected explicit break to an ordinary
paragraph boundary: text is **not joined**, and native offsets do not shift.
Section merging is supported only without any section-specific declarations or
hidden/anchored associations. Native probes demonstrate that merging named
sections can discard names and splitting associated sections can duplicate and
renumber headers/footers and anchored associations. These cases are explicitly
protected, not silently simplified. Table/list/nested boundaries, ranged
selections, malformed/generic ranges, ambiguous section syntax and destructive
cross-cell cases remain protected. Names/settings can still be changed as
body-preserving transactions in otherwise text-protected native documents.

Every change uses one document-wide undo/redo, version and recovery transaction.
Failed actions roll back without a history entry. All six languages, keyboard
controls, system/light/dark appearance and small screens are supported.
Page and section break markers are visible, localized separators on the
continuous preview; they are authoring guides, **not automatic or exact native
pagination**. Supported section geometry is projected on white surfaces in this
preview phase. Stored headers/footers have separate editing scopes below;
they are not placed in simulated page margins.

## Columns and paragraph tabs (available on main)

**Page setup → Text columns** edits document defaults (`div.section0`) or the
selected numbered section. Count (1–20) and gap (0–10,000 pt, or equivalent
mm/cm/in values) have independent explicit/inherited states. Checking inheritance
removes only that declaration, including duplicate overrides; it does not copy
the current default. Existing column rules and unknown section/subsection
declarations remain untouched. Gaps must leave a positive column text width in
every affected section; later paper/margin changes are checked against retained
column overrides too. Invalid values are rejected, never clamped. These width
checks are conservative editor limits: native 4D accepts some unusable gaps.
Ambiguous, inline, conditional or unsupported count/gap declarations disable
column editing with a localized reason.

Select an editable caret or text, then open **Paragraph tabs**. Changes apply
to entire selected paragraphs, including partial selections and supported table
cells. A paragraph reached only at its beginning is excluded. Mixed selections
are identified; the stop list is their union, while displayed stop/default
fields initially use the first matching paragraph. **Set stop** adds or replaces
one absolute position in each selected paragraph; moving a stop to another
existing position is rejected. **Remove stop** removes only that position and
preserves other stops and the default interval/type/leader. Default Apply updates
only fields actually edited, preserving differences between paragraphs.
No-op Apply and preference-only unit changes retain original values and create
no history entry, including when both settings panels are open.

The five native alignments are **left, right, center, decimal and bar**. Editable
leaders are **none, dot, dash and underscore**, for explicit stops and the
default interval. Positions/intervals must be positive and at most 10,000 pt;
absolute positions must be distinct and ascending (up to 128 editable stops,
an editor complexity limit). The final entry in native parallel tab arrays is
the repeating default interval, not another absolute stop.
**Reset to native tab defaults** matches native `WP RESET ATTRIBUTES`: no
absolute stops, a 1.25 cm left-aligned interval and no leader. Unlike section
inheritance reset, this is **not** a return to the named paragraph style.
Named/generated styles, unrelated paragraph declarations and existing text
characters are retained; only the three tab properties are overridden.
Unsupported custom leaders, malformed arrays/unsupported scopes and ambiguous
paragraph style combinations are preserved and protect tab editing rather than
being silently converted. Native quote/backslash leader counterexamples are
retained in probe evidence; no stable native reexport parity is claimed for them.

**Insert tab character** is keyboard-accessible and inserts an actual U+0009
through the registered native text transaction. Tab itself remains focus
navigation. Existing tabs are never replaced with spaces. Formula objects,
bookmark offsets, table guards, protected boundaries and original resource bytes
retain their existing safeguards; a selection crossing a protected formula
remains protected. A caret in a supported paragraph can edit its tab formatting
without changing the paragraph's immutable formula subtree. Text-protected
documents remain text-protected; body-preserving column settings can still be
edited. Existing safe section-split/merge guards are not relaxed for column rules
or other section declarations.

All controls, errors and capability notices are available in EN/JA/FR/DE/ES/IT,
system/light/dark appearance and responsive layouts. Each operation is atomic
for undo/redo, versions and IndexedDB recovery. The continuous browser preview
balances columns **between explicit breaks within each section**, without fixed page heights/native flow.
Tab spacing uses only the default interval; absolute alignment, decimal/bar stops
and leaders are saved for native 4D, **not rendered**. Fonts, line wrapping and
leader placement are not exact native equivalents. Native-equivalent automatic
pagination and floating-object editing are not included. Header/footer text
uses the independent scope editor described below.

The full-4D gate adds focused column/tab originals, independent native mutations,
real browser downloads (including Undo and recovered Redo), effective section and
paragraph getters, exact native reexport declarations/body checks and raw bookmark
and resource checks. It covers Unicode, formulas, inline pictures, simple tables,
named-style/direct-format inheritance, section overrides/resets and hidden
header associations. Native-generated regression archives live in
`tests/fixtures/flow/`; regenerate them from a successful full-4D gate's matching
`Output/layout-*.4wp` files, not from the web model.
The merged columns/tabs increment passed 388 unit tests, 76 browser tests and 1,532 full-4D
import/export/reopen cases. Of the latter, 281 are column/tab cases: 109 model
exports and 172 actual browser downloads. These are scoped attribute/content
checks in full 4D 21.2 `F0012102`, not arbitrary document or visual-layout parity.

## Headers and footers (basic editing available on main)

The **Editing scope** selector separates the body from each stored header/footer,
identified by **native section number, default/first/left/right variant and kind**.
It renders the selected area's supported text, formatting and inert formula cards
instead of editing hidden body XML through the body projection. Scope changes
are preferences, not document edits; recovery retains the selected scope.
Text replacement, direct character formatting, alignment/paragraph spacing,
paragraph and line breaks, safe inline links, find/replace and paragraph-only
sanitized paste reuse central atomic history/version/recovery transactions.
Selections crossing a formula remain protected; no formula execution or
page-number substitution occurs.

**Native default is section-local**, not a document-wide content template.
Native document/default paper geometry is still `div.section0`; numbered
sections inherit or override its geometry, not another section's header text.
Absent header/footer areas are absent, not inherited content. Creating a native
subsection copies existing default content, and creating left or right also
creates its opposite. Existing first/left/right stored areas can be edited
independently. The merged variant/positioning increment below adds explicit
controls for those native operations, not automatic native pagination.

The separate section/kind selectors create an **empty default** header/footer
only in sections without variants. **Remove default area** confirms content
deletion and is available only for supported default areas without variants or
formulas. Undo restores the original content, declarations and associations.
Orphaned style rules, duplicated/malformed area identities, missing variant
enabling rules, unsupported/nested section structure and ambiguous selectors
protect area changes explicitly rather than guessing associations.

Supported areas contain ordinary paragraphs, inline text/formatting/links and
supported immutable inline text formulas. Tables, pictures, nested lists,
anchored/protected content, unsupported formula forms and other native objects
remain read-only with a localized capability notice. They are never flattened
or removed. Header/footer editing preserves the rest of the serialized XML
**exactly**, including body bookmarks, section settings, nonactive variants,
anchored associations and unknown resources. It does not relax the existing
body-range/merged-table/complex-bookmark or section split/merge guards.
Switch to the body for page setup and bookmark tools.

Printing always projects the **whole document**, not just the current editing
scope. In continuous print mode, supported stored header/footer content is included **once per area in a
labeled content appendix** with an explicit placement warning. Native repeating
headers, first/left/right page selection, distances, field evaluation and native
pagination are not reproduced. Unsupported/ambiguous areas keep explicit
preservation notices; download and print in 4D for actual native layout. Preview
and print use disposable models and never dirty the original. The selected paged
increment below adds scoped repeating browser areas, not native placement.

`wp_header_probe` independently creates default, first, left/right, formula,
bookmark-rejection and custom-distance cases in full 4D F0012102. Its native
mutations cover text/formatting, default creation/removal, subsection disabling,
section splits/merges, Unicode growth and paragraph/line breaks. The expanded
gate compares actual browser/model downloads with native originals mutated
independently, effective area getters, local range coordinates, body bookmark
pairs, geometry, formula XML and native reexports/reopens. The browser suite
also covers scope-aware recovery, safe removal/undo, unsupported structures,
six languages, mobile, themes, keyboard focus and content-appendix PDF output.

### Variant controls and positioning (available on main via #50)

The **First page** and **Left/right pages** toggle buttons apply to the selected
**Native section**, to **both header and footer**. Their pressed state and a
section-labeled status distinguish enabled from disabled. **Editing scope**
continues to identify the actual stored area being edited; changing the
configuration target does not silently switch text scope.

Enabling copies this section's current default areas, their paragraph/inline
formatting, immutable formula subtrees and four distances. Missing default areas
remain absent: neither an empty area nor another section's content is invented.
Left/right are one native pair. Disabling **deletes** both affected kinds (and
both sides for left/right), not merely their visibility. A localized confirmation
explains that loss before changing XML. Defaults and other variants remain
unchanged. Re-enabling copies defaults again rather than resurrecting deleted
variant text; Undo/Redo, saved versions and IndexedDB recovery retain the
original content. Formula-containing variants cannot be deleted. Ambiguous
associations, unknown subsection/area declarations, unsupported objects and
identity-bearing content protect the operation rather than being flattened.
Default-area creation/removal remains limited to sections without variants.
An enabled subsection with no stored area stays empty; native deletion probes
confirm that it does not fall back to the default area.

**Native area positioning** edits the four native `margin` distances of the
active **Editing scope**, with its full section/variant/kind label. It does not
change body page margins, paper geometry, section names or the wrapper's
`visibility:hidden;height:0`; native content height is automatic. Top and bottom
participate in native area/body clearance, not a browser fixed-height box.
Native PDFs independently establish that header top/left margins move the
first-page header, footer top/left margins move its footer, and changing the
section's body bottom margin can move the footer even with unchanged area
distances. These observations are not a general placement formula.

mm/cm/in/pt reuse the shared preference-only unit framework. Only edited fields
are saved: unit switches and no-op Apply preserve native units/fractions and
create no undo step. New values must be finite, nonnegative and at most
10,000 pt; opposing area margins must leave positive oriented paper width and
height. Native accepts some off-paper configurations; rejecting them is a
conservative editor constraint. Missing/ambiguous/shared/inline/conditional or
unverified longhand margins are preserved and protected. Invalid values raise
localized errors with no clamping or unrelated geometry reset.

`wp_variant_probe` adds independent full-4D default/header-only/footer-only,
empty, Unicode/formula, first-left landscape and left-first/right-first cases.
It retains native copy/edit/remove/re-enable/distance mutations, local ranges,
effective getters, XML and multi-page PDFs. Native PDFs prove first-page
precedence, paired side selection, first-page side/orientation effects and
absent second-section content. Model and actual browser/recovery downloads are
reimported/exported/reopened in full 4D and compared with those independent
targets, including body bookmarks and resource bytes. Continuous browser
printing retains a **once-per-stored-area labeled appendix**, not native
repeating placement, evaluated fields or native-equivalent pagination.
Native-created regression archives in `tests/fixtures/headers/` come from
`Output/variant-*.4wp`, never from the web model.

The merged #50 increment passed **415 unit tests, 103 browser tests and 1,959
full-4D F0012102 import/export/reopen cases**. The native gate retains the
1,692-case #49 baseline and adds 267 variant/positioning cases, including real
browser operations, Undo and recovered Redo downloads. Nine native originals,
thirteen stages each and four separate area-deletion/creation counterexamples
establish the independent expectations. This is scoped compatibility evidence,
not arbitrary layout parity.

The merged #49 increment passed **408 unit tests, 101 browser tests and 1,692
full-4D import/export/reopen cases**. The unchanged 1,548-case printing baseline
is retained; 144 additions comprise 62 model exports and 82 actual browser and
recovered downloads. Seven independent native cases each retain fourteen
mutation stages. Native-original PDF observations verify first/right selection,
cached formula text, absent-section content and mixed page geometry; they do not
assert browser/native page-count or repetition parity.

## Advanced images and text boxes (available on main)

The **Editing scope** selector includes stored anchored pictures and text boxes
by their original native IDs. These are isolated authoring views, not objects
positioned on simulated pages. Stored page/section/origin/alignment/layout and
display-mode declarations are inspectable as native metadata; absent properties
stay absent. The native defaults observed by the probe are all pages/all
sections, paper origin and zero offsets for added pictures; new text boxes start
on page 1, 8 cm wide, auto height, with 4 pt padding and front layout.
The editor does not create/delete native anchored objects, change associations,
alignment, wrapping, layering or display modes in the #51 increment; #52 below
adds guarded creation/deletion and stored placement.

Supported native text boxes containing ordinary paragraphs and inline formatting
have their own text/formatting scope. Supported immutable text formulas keep
their exact subtrees while surrounding text can change. Edits use the existing
registered document-wide transaction, Undo/Redo, versions and IndexedDB recovery.
Body text, raw bookmark pairs, nonactive objects, headers/footers, formulas and
resources remain unchanged. Body guards are **not** relaxed merely because an
object can be edited in another scope. Nested tables/pictures, identity-bearing
descendants, unknown anchor properties, ambiguous IDs/sections, conditional or
important object CSS and formula pictures remain protected. Text boxes require
their unique native identity-owned `div._divN` rule; shared/missing rules and
inline box geometry are protected because native 4D ignores those inline overrides.

**Object size and offsets** applies only changed fields, preserving unchanged
units/precision and auto dimensions. Width/height are 1–1,200 pt and nonnegative
horizontal/vertical offsets are 0–1,200 pt, in pt/mm/cm/in. Invalid/nonfinite
values fail explicitly, without history or mutation. These are editor limits,
not native maximums. Alignment-based placement remains geometry-protected;
supported box text can still be edited independently. Only paper-origin,
unambiguous native associations are editable. Existing front/behind/wrap-square
metadata is retained, never converted into browser positioning.
Box geometry updates only that identity-owned rule; picture geometry uses
native-verified inline overrides. Unrelated CSS and XML remain exact.

Inline/archive-relative static PNG, JPEG, GIF and WebP previews are admitted by
bounded container/dimension inspection (including PNG chunk checksums), followed
by browser decoding. The
independently observed TCP4 v8 single-codec PNG/JPEG record can also be projected:
the codec-name record, declared sizes, metadata span, reserved bytes and payload
offset/length must agree. The extractor does **not** scan arbitrary bytes for a
magic signature or execute metadata. Other native records/codecs remain explicit
placeholders. Wrapper projection is display-only, may differ from native affine
transforms, and never replaces or rasterizes the authoritative source URI or
archive bytes. Wrapped inline objects remain mutation-protected.

Admission limits are 8 MiB and 40 million decoded pixels per source, with
128 distinct admitted sources, 16 MiB of admitted source bytes and 80 million
pixels per model. At most 512 distinct source attempts (including rejections)
are inspected; further sources receive a budget notice rather than bypassing
admission limits when the cache is full. Animation (including APNG), active SVG/vector/native codecs,
external URLs and malformed/truncated/missing payloads receive explicit localized
notices; browser decode failures replace the picture with a notice too.
Nothing fetches an external image. Original sources remain available on export,
including unsupported and malformed ones. The archive/XML budgets still apply.

The isolated view approximates supported picture fitting and dimensions. Text
box surfaces use stored dimensions as guides without clipping overflowing text.
Browser print includes supported stored objects **once each in a labeled
appendix**, with protected-object notices for unsupported cases. It uses a
disposable model, not the live scope/mappings. Native wrapping, z-order, page
targeting, repetition and pagination are not simulated; formulas are not
evaluated.

`wp_media_probe` independently creates seven native cases (defaults, paper,
section, alignment, formula, nested picture and transformed wrapper), records
seven operation stages and exports native PDFs. It establishes independent box
UTF-16 text ranges, stable object IDs and unchanged body tape/bookmarks across
geometry, box text/formatting, layout and removal. Native PDF text bounds verify
the paper-relative box movement. The expanded gate compares model and actual
browser downloads, Undo and recovered Redo with those independent getter/text
expectations and retained source bytes. Fixtures in `tests/fixtures/media/`
are native-generated originals, not editor-generated expectations.

The merged #51 baseline passed **424 unit tests, 114 browser tests and 2,060
full-4D F0012102 import/export/reopen cases**. The 1,959-case #50 manifest is
unchanged; 101 media cases add 23 model exports and 78 actual browser, recovery,
Undo and recovered-Redo downloads. Browser checks include measured isolated
object widths, malformed/decode-failing sources, immutable print content and
all six languages/themes on mobile. These are scoped preservation and getter
checks, not a claim of native browser layout parity.

## Object lifecycle and stored native placement (available on merged main)

**Create text box** creates a separate native box with an optional single
paragraph (up to 10,000 UTF-16 units), 180 × 90 pt, on page 1 in front of text.
An empty box retains an ordinary editable paragraph. **Create anchored picture**
accepts a local, browser-decoded bounded PNG/JPEG, retaining its original bytes.
Its initial dimensions use the pixel dimensions as points, proportionally
reduced to at most 600 pt on the longest side; normal object dimension limits
also apply. Neither action consumes a body selection or shifts body bookmarks.
New native IDs/classes avoid existing IDs, CSS (including orphaned rules) and
opaque serialized references. Unsafe cascades/associations fail atomically.

**Delete selected object** requires confirmation and only removes a supported,
unambiguously identified object. Formula-bearing boxes/pictures, nested or
unknown content, identity-bearing descendants and externally referenced IDs
remain protected. All nonactive XML, formulas, section/header associations,
original picture sources and raw body bookmark pairs are retained. Deletion
intentionally retains orphaned CSS and archive resources: their other native
consumers cannot be inferred safely. Original files are never modified.

**Stored native placement** supports a numbered document page or all pages of
all sections, or all pages of one existing section. Combining a specific section
and a specific page is deliberately protected. Enter the literal `all` or a
positive integer from 1 to 10,000 for the page; this is a native target, not a
browser-generated page number or an assertion that the page currently exists.
Horizontal offset/center/right, vertical offset/center/bottom and native
front/behind/square-wrap relationships are editable. Left/top native alignment
getters are zero, so **Offset (left/top)** is the single zero-alignment mode.
Clearing alignment removes the class declaration and any picture inline override before
offset editing becomes available. Placement applies only changed fields;
unchanged units, auto dimensions, offsets, display modes and associations retain
their source representations. Text boxes use their unique `div._divN` rules,
and placement controls require the same unique `img._imgN` ownership for pictures.
Native layer changes can renumber classes without renaming objects; controls
follow the actual unique class, never derive its number from the object ID.
Unverified inline box placement and arbitrary imported z-index values remain
protected, like inline box geometry.
Unrelated declarations and unknown structures are never rewritten.

Controls use the existing six languages, system/light/dark appearance and
responsive keyboard-accessible forms. Every action is one document-wide
Undo/Redo, version and recovery transaction; a two-object edit is two actions.
Undoing a creation/deleting an object selects the body when the old scope no
longer exists; restoring an object selects that object's scope. Failed/no-op
changes do not create history entries. Delayed picture reads refuse stale
documents rather than inserting into a replacement document.

These are **native export controls, not a native-layout browser preview**.
The isolated object guide and once-per-object print appendix remain unchanged.
Native pagination, wrapping, layering, repetition and page targeting are not
simulated in the browser; arbitrary z-order, other origins/wrap modes, formula
execution and conversion of inline pictures to anchored objects remain outside
the #52 increment.

The independent full-4D `wp_object_probe` creates three documents (PNG
document-page and section targets, plus an independently native-encoded JPEG) containing
body bookmarks/formulas, a nonactive formula box, a picture and a header.
Fourteen stages record picture/box creation, document-page versus section
targeting, center/right/bottom and left/top alignment, explicit alignment
clearing/offsets, all three supported text relationships, repetition, deletion
and recreation. Every stage retains the original native body tape/bookmark.
`native-object-cases.mjs` compares model exports and actual browser downloads,
reload recovery, Undo and recovered Redo with these independently native-created
getter/text oracles, and checks raw source XML/media/resources independently.

Verification for the merged #52 increment: **429 unit tests, 115 browser tests and
2,240 full-4D F0012102 import/export/reopen cases**. All 2,060 #51 case
definitions remain exactly unchanged; 180 lifecycle cases add 36 model exports
and 144 actual browser, recovery, Undo and recovered-Redo downloads. The final
production build regenerates all lifecycle downloads; the unchanged baseline
inputs and independent native probes are byte/SHA-checked when reused for the
final complete native import/export/reopen pass.

Final evidence: `~/.copilot/evidence/4wp-objects-20261113-gate-04/`;
independent byte/SHA-verified backup:
`~/.copilot/evidence-backups/4wp-objects-20261113-gate-04-33ac49fe/`.
`reproduction.json` records oracle/input provenance, and `SHA256-MANIFEST.json`
in the backup records every retained file. Earlier standalone probes and the
class-renumbering counterexample are independently preserved in
`~/.copilot/evidence-backups/4wp-objects-20261113-probes-33ac49fe/`.
The #52 increment is merged and deployed at the baseline recorded above.

## Paged browser preview (available through #60)

Open **Paged browser preview** above the continuous editor. It is a separate,
read-only projection of the whole document, even while authoring a header/footer.
The editor, selection, undo/redo, versions, recovery and authoritative archive
remain untouched. Closing the preview restores no content because none was
replaced. Escape closes it and returns focus to its summary; its scroll region
is keyboard accessible. All six languages, themes and mobile overflow handling
are retained. Resize and font readiness rebuild a disposable projection; zoom
scales the finished view without changing measured pagination.

Supported body shape: **top-level paragraphs, flat lists and local inline images
in one column or supported equal columns; rectangular tables in one column only**, including inline
formatting, inert links, line breaks, Unicode and supported immutable text
formula cards and locally decoded inline images. Whole paragraphs that fit stay
intact; longer paragraphs/list items split only at measured visual line
boundaries, never within grapheme clusters, images or formula cards. Fragments
retain inline wrappers/formatting and every source character, including whitespace.
The paged projection uses `break-spaces` so preserved spaces wrap within the text
band instead of hanging outside it. First/last fragments retain the paragraph's
outer spacing; continuation fragments do not repeat its first-line indent or list
marker. Explicit
page breaks and new-page section breaks force page boundaries; each section uses
its effective orientation and margins with the document-wide base paper size.
Each paragraph's content appears exactly once in body reading order. These are **browser
page counts**, not native counts or native line positions.

First-page areas take priority on the first browser page **of each section**.
Enabled facing pairs select left/right by physical document-page parity and
the stored document first-right flag (native default: right). Otherwise the
section's default area is selected. Selection is independent for header/footer:
an absent area in an enabled subsection stays empty, without borrowing a
default, another variant or another section. No page fields or formulas are
evaluated; cached text, when actually present, remains cached text.

Selected supported areas repeat inside **browser-only margin bands**. Header
top/left/right and footer bottom/left/right use their own stored margins; the
opposite vertical margin reserves clearance inside the corresponding body-margin
band. Both area content and body must fit without overlap or horizontal overflow.
This is deliberately **not native positioning**: native footer placement can
also depend on body geometry, and the browser does not reproduce 4D line metrics.
Stored areas never selected on the resulting pages remain accessible in their
editing scopes and appear **once on labeled appendix sheets** in preview and print,
so unused default/variant text is not silently excluded from output.

Native lists remain **flat sibling items**, with their own stored indentation,
not invented nested HTML. Numbering follows the original group's `start` and
item position, including mixed bullet/numbered items. Supported markers are
disc/circle/square/hollow-square/diamond/club/none, decimal/leading-zero,
Latin alphabetic and Roman numerals. A quoted native LTR format with exactly
one `#` is supported; marker fonts remain local font-family choices. Starts
and resulting counters are limited to 1–3,999. Nested lists, per-item `value`,
reversed lists, custom/unknown markers and unverified native level/RTL-format
properties fall back explicitly.

Inline pictures reuse the existing inert local raster/native-container/resource
decoder and its admission budgets. Successful browser decoding precedes layout;
authored point dimensions are retained, a missing dimension uses the decoded
aspect ratio, and absent dimensions use decoded pixel size at 96 dpi.
Images and supported formula cards are indivisible atoms. No external media is
fetched, original picture bytes are never rewritten, and oversized images are
not shrunk to fake a successful page. Preparation has a ten-second decode deadline.

Tables in single-column sections use the shared native grid validator, not a second table-association model.
Supported tables have direct native `tr`/`td`/`th` grids, body paragraphs immediately
before and after, and paragraph or bounded flat-list cell contents (including formatting,
Unicode, inert links, line breaks, supported formula cards and safe local inline
pictures). The whole table is measured at its section's text width once.
Its measured width and unequal column widths are frozen in disposable `colgroup`
geometry, never written to source XML. Complete rows move together; no row or cell
is split. Every data row/cell occurs once, in order. Borders, backgrounds, cell
formatting and native left/center/right table alignment are retained in the
browser projection. Fragment cell widths and heights must match the whole-table
measurement within 0.25 CSS px; a changing grid falls back rather than silently
reflowing each page.
Implicit-width tables keep their intrinsic column geometry instead of stretching
to the flex page body. Mixed-size print output has no document-wide fixed width
that would make Chromium shrink portrait content to fit a later landscape page.

Only contiguous leading rows with native `-d4-header:true` repeat, based on
independent full-4D `wk header row count` originals/getters/PDF evidence. A `th`
element alone does not invent a native header. Each fragment requires at least
one data row in addition to its headers. Nonleading/invalid/all-header metadata,
vertical/mixed spans, horizontal grids without an unmerged witness row,
irregular/nested/data-source tables, unsupported lists within cells,
fixed-height structures, negative margins, horizontal overflow, and rows that
cannot fit with their headers fall back explicitly. Limits are 1,000 rows and
10,000 cells per table, the existing 1,000-column grid limit, and the shared
100,000 measured-grapheme/500-sheet budgets. These are conservative browser
limits, not native maxima. Native table row/page counts, border-conflict parity,
carry-over rows and native row splitting are not claimed.
Existing body protection for bookmarked documents with unsupported hidden-area
associations remains in force. Native table recovery evidence edits the safe
first-header scope rather than weakening those body guards.

The **Available/deployed #59** cell-list increment admits direct native `ul`/`ol` blocks
mixed with cell paragraphs. Items are flat inline `li` elements: no nested lists,
paragraph-wrapped items, reversed lists, per-item `value`, unknown levels or
custom marker types. Supported native marker types are `disc`, `circle`, `square`,
`hollow-square`, `diamond`, `decimal`, `lower-latin`, `upper-latin`, `lower-roman`
and `upper-roman`. Counters are **1-3,999**; a numbered marker's quoted native LTR format may contain
exactly one `#` and at most 80 characters. There are at most **10,000 list items
per table**, independently of the row/cell limits. Markers and content must fit
inside their owning cells within 0.25 CSS px; insufficient indentation or an
oversized row falls back without clipping, shrinking or splitting cells.

Independent installed-4D originals/getters/PDFs establish that counters continue
within each native list, not across cells. Explicit item restarts serialize as
separate `ol start` elements and remain separate; the browser does not infer
continuation or invent starts. Native cell `disc` and `diamond` markers use
U+25CF and U+2666. These cell-context glyphs reuse the body marker/counter helper
without changing existing body-list output. Native list font, bold/color,
indentation, wrapped items, mixed paragraphs, safe pictures and inert formulas
are retained in disposable cell content before the whole-table measurement.
List-bearing leading header rows repeat with their markers and frozen grid.
Neither viewing nor printing converts the original XML or broadens table
authoring, native-range/bookmark guards, undo/recovery or formula evaluation.

The **Available/deployed #60** horizontal-span support admits only complete native grids
whose `rowspan` values are all one, with at least one fully unmerged witness row.
That row may follow merged header/body rows; it supplies all underlying column
widths after the whole table is measured at its physical flow width. Disposable
fragments retain original horizontal `colspan` attributes, complete rows and
contiguous native leading headers. Rich merged cells retain supported paragraphs,
flat lists, inline formatting/inert links, local pictures and inert formula caches.
Every cell/atom/marker stays inside its owning bounds, and fragment width/height
must remain within **0.25 CSS px** of the unfrozen whole table.

Installed full 4D 21.2 `F0012102` originals/mutations/getters/PDFs independently
establish unequal 50/70/110 pt settings, later witnesses, zero/one/two headers,
rich merged headers and compatible-seam capacity. The native formula export has
no distinguishable cache and retains the existing explicit unavailable-value
notice; cached values are retained only when actually present. A rich two-header
overflow original remains atomic fallback without altering paper or row geometry.
Browser frozen dimensions are
not asserted equal to native width getters or native collapsed-border decisions.
Vertical/mixed spans, no witness, ambiguous/irregular/overlapping/nested/data-source
grids, unsafe content and changing geometry remain localized atomic fallback with
untouched original downloads. No authoring, bookmark/range guard, formula execution,
row-splitting, continuous-section or multi-column admission is broadened; all prior
row/cell/column/list/grapheme/sheet limits remain. Native wrapping, pagination,
page-count and border-conflict parity remain **Proposed**, not promised.
At the #60 verification snapshot the live site was #59 (`b302afc`, Pages run
[`43502491206`](https://github.com/miyako/4d-ql/actions/runs/43502491206)); #60
was subsequently deployed by Pages run
[`43515562104`](https://github.com/miyako/4d-ql/actions/runs/43515562104).

Horizontal-span (#60) verification: **441 unit tests, 159 production browser tests,
2,524 installed-4D generation cases and 2,538 final strict import/export/reopen
cases passed** under 4D 21.2 `F0012102`. All **2,498 #59 definitions** remain
unchanged by name; **2,240 unaffected inputs and 2,761 dependency archives** were
independently byte/SHA-compared. Final production assets regenerated all affected
exports. All **sixteen genuine headed Chromium Cancel states** passed: continuous,
paged, expanded, tables, columns, seams, cell lists and horizontal spans, each
clean/Redo and dirty/Undo, preserving complete DOM, selection paths/endpoints,
scope, zoom, exact bytes, history and the entire IndexedDB record. The existing
seven-line #58 actual-resize repair, body marker admission and cell-only glyph
overrides remain intact. A prior rich two-header overflow is retained as failed
generation evidence, not represented as a passing gate.

Final evidence: `~/.copilot/evidence/4wp-colspan-20261114-gate-02/`;
independent byte/SHA-verified backup:
`~/.copilot/evidence-backups/4wp-colspan-20261114-gate-02/`.
The source/build/native/browser/PDF/Cancel/baseline reproduction is sealed before
PR publication; exact publication heads and unique/unpushed state are reported
separately from the immutable verification snapshot.

The available #56 column increment admits **2-4 equal-width, left-to-right columns**,
with a **0-72 pt gap** and **at least 72 pt of text width in each column** after
effective section paper margins. Count/gap reuse the existing native authoring
resolver: `div.section0` supplies defaults and exact `div.sectionN` rules override
them. Columns fill **top-to-bottom, then left-to-right, then onto the next physical
page**. The last page is not balanced. An authored `break-after:column` on a
top-level paragraph advances one column (or the next page's first column); a
page break skips any remaining columns. New-page section breaks reset the column
geometry and section-local first-area selection. Headers/footers span the
physical page, not individual columns; facing parity changes only on physical
pages. Stored areas not selected still use bounded labeled appendix sheets.

Paragraph/list fragments retain their shared inline ancestor wrappers, including
on middle fragments whose range starts and ends inside the same text run.
The column increment does not alter column authoring, continuous editing, source
XML or native ranges. Lists, local pictures and inert formula cards use the same
fragment/atom safety checks at the narrower column width. A line/image/formula
that cannot fit its own column causes atomic fallback, never shrinking.
Divider rules, non-native column shapes/spanners, RTL/vertical flow,
more than four columns, oversized gaps, too-narrow geometry, tables inside
multi-column sections, and nested/conflicting column breaks are **unsupported**.
Native last-page balancing, column/page counts, line metrics and formula
evaluation are not claimed. `wp_paged_column_probe` independently authors
two/three/four-column, explicit-break, mixed-landscape, divider-rule and narrow
documents in full 4D, with effective getters, body bookmarks, first/facing areas,
lists/picture/formula content, native first-header edit targets and PDF references.
Native PDFs establish equal-column widths and explicit break progression;
browser PDFs are separately checked against actual measured page/column
membership, not native automatic wrapping.

The available #57 continuous-section increment admits **area-free single-column
seams with identical effective paper, orientation, margins and column count/gap
on both sides**. Native `-d4-section-break-after:continuous` continues in the
current measured body flow, retaining residual capacity instead of creating an
artificial page. Overflow advances physical pages normally. Chains and explicit
page breaks remain ordered; later new-page sections still reset first-area
selection and use physical document parity. Each disposable body fragment keeps
its source section identity; the physical sheet records its starting section
and all participating sections. Names, explicit overrides and inheritance are
not flattened or rewritten.

`wp_continuous_paged_probe` independently authors 14 full-4D originals, native
mutation targets, getters and PDFs. Compatible inherited/explicit settings,
overflow, chains and page/new-page transitions establish the positive subset.
Margin changes can apply within the same native page, while an orientation
change can start a different-sized native page. Multi-column seams have distinct
native flow/balancing behavior and remain unsupported here. A shared native page
keeps the starting section's header/footer; later physical pages use the later
section's facing/default content, **not a deferred first header**. All stored
areas and enabled first/facing variants on either side, including empty ones,
therefore remain outside the supported subset. Geometry-changing seams, column
breaks or multi-column seams also use the dedicated localized continuous-seam
fallback. Unsupported seams never return partial pages.

Already-admitted lists, inline local images/inert formulas and rectangular
single-column tables retain their existing safety rules across compatible
seams. A focused rich-content browser regression uses remaining capacity before
continuing a table on later pages, with fixed widths, repeated leading headers,
complete ordered content, fitting bounds and exact measured print membership.
No native wrapping, final-column balancing, exact native pagination/page counts
or footer coordinates are claimed.

Unsupported continuous seams, unsupported column shapes/geometry/content, unsupported tables/lists/images, anchored
objects, ambiguous associations/settings, fixed-size body paragraphs and
unsupported paragraph content use the existing continuous view/print mode.
Unsplittable oversized lines/atoms, unsafe area bands, oversized unused appendix
areas, more than 500 browser sheets (body plus appendices) or more than 100,000
graphemes measured for splitting or table preparation also fall
back. Localized notices explain the reason; no partial paged view, clipped
content, fabricated fallback text or archive mutation is returned. The fallback
does not certify unsupported native structures; their established preservation
notices and isolated editing scopes remain in force.

With the preview open and supported, **Print / Save as PDF** and the browser's
Print command render the same derived fixed pages using named zero-margin
`@page` rules and explicit internal body/area bands. With it closed, the existing
continuous print projection is unchanged. An open unsupported preview prints
that continuous projection with its explicit localized fallback reason and
labeled area appendices, provided the existing continuous print safety gate
admits the geometry; too-small/ambiguous print geometry still gives an explicit
failure notice and leaves the whole source accessible in the continuous editor.
Use 100% scale and disable browser-added headers/footers.
Print clones the ready, unscaled paged projection rather than measuring a second
layout with print-only image rules. A native browser Print command before image
preparation finishes uses the explicit continuous fallback; it never prints a
success-shaped incomplete paged document.
There is no server, 4D backend, native layout engine, arbitrary object wrapping
or evaluated page-number substitution.

Focused browser PDF checks verify actual automatic boundaries, explicit breaks,
mixed section paper sizes, selected and unused area content, unchanged exports,
resize/zoom/theme stability and recovered history. `wp_paged_probe` adds four
independent full-4D originals and footer-edit targets: right-first, left-first,
mixed orientation and missing areas. Native PDFs establish multi-section
first-page reset and physical facing parity; they are content/geometry oracles,
not a claim of browser/native line-layout equivalence.

Merged #53 verification: **432 unit tests, 130 browser tests and 2,266 full-4D 21.2
`F0012102` import/export/reopen cases passed**. All 2,240 merged #52 case
definitions, including the earlier 2,060, remain unchanged when compared by
case name; no requirement depends on manifest ordering. The existing complete
native gate generated and verified the baseline and new oracles. The final
production build regenerated all 24 paged original/browser/Undo/recovered-Redo
inputs; two additional actual headed Chromium Cancel downloads cover clean/Redo
and dirty/Undo states against the independent native footer targets. All 2,266
inputs then passed the complete native import/export/reopen verifier. Reused
baseline inputs were independently byte/SHA-checked against the complete gate.

Merged #53 evidence: `~/.copilot/evidence/4wp-paged-20261113-gate-04/`;
independent byte/SHA-verified backup:
`~/.copilot/evidence-backups/4wp-paged-20261113-gate-04-410e05a3/`.
`reproduction.json` records final build hashes, unchanged baseline input hashes
and counts; structured unit/browser results, native and browser PDFs, real
Cancel screenshots/recovery comparisons and the complete native report remain
outside the disposable worktree. The backup's `SHA256-MANIFEST.json` covers
every retained file. Earlier native oracles and the full generation gate are
independently preserved in
`~/.copilot/evidence-backups/4wp-paged-20261113-gate-02-addbd3ae/`;
the preceding verified build is preserved in
`~/.copilot/evidence-backups/4wp-paged-20261113-gate-03-410e05a3/`;
the first, failed probe attempt is retained separately without a pass claim.

Merged #54 expanded verification: **433 unit tests, 137 browser tests and 2,283
full-4D 21.2 `F0012102` import/export/reopen cases passed**. All 2,266 #53
case definitions remain unchanged, compared by name. The 17 added cases are
15 actual original/after-layout/edited/Undo/recovered-Redo browser downloads
against three independent native originals/edit targets, plus two real headed
Chromium Cancel downloads for the long paragraph/picture/formula document.
The existing `--paged` Cancel gate was also repeated without replacing its
baseline definitions.

The complete generation gate passed 2,279 cases before the four Cancel
captures. The final production build regenerated all 39 paged/expanded browser
inputs, independently retaining the SHA-256 of the other 2,240 inputs, and the
augmented 2,283-case manifest then passed the full native import/export/reopen
verifier. Measured fragment bounds, exact text/whitespace, styled runs, per-page
PDF token membership, list starts/levels/markers and image decode/size/failure
are covered. Each native long-content reference is **three native pages versus
four browser pages**, explicitly not native pagination parity. Real Cancel
preserves the editor/paged DOM, selection, zoom, history and complete IndexedDB
recovery record in both clean/Redo and dirty/Undo states.

Final expanded evidence: `~/.copilot/evidence/4wp-expanded-20261114-gate-02/`;
independent byte/SHA-verified backup:
`~/.copilot/evidence-backups/4wp-expanded-20261114-gate-02/`.
`reproduction.json` records the baseline, final build hashes, verification counts
and definition/input comparisons. Full native originals/targets/reexports,
native/browser PDFs, structured unit/browser results and actual Cancel captures
remain outside the disposable worktree. The complete first generation gate is
separately backed up at `~/.copilot/evidence-backups/4wp-expanded-20261114-gate-01/`;
the final-export snapshot before native ownership was released remains labeled
`~/.copilot/evidence-backups/4wp-expanded-20261114-gate-02-pending/`, without a
final-pass claim. Each backup has its own `SHA256-MANIFEST.json`.

Merged #55 paged-table verification: **434 unit tests, 141 browser tests and 2,300
full-4D 21.2 `F0012102` import/export/reopen cases passed**. All 2,283 #54 and
2,266 #53 case definitions remain unchanged, independently compared by name.
The 17 added cases are 15 real before/after-layout/header-edit/Undo/recovered-Redo
downloads from three independent native table originals, plus two actual headed
Chromium table Cancel downloads. Native originals include no headers, two
repeating header rows, and a mixed-section one-header table with an inline
picture and formula. Every cell's native getters and complete reexported body,
CSS, formula/bookmark metadata and resources are compared with independent
originals/first-header edit targets.

The final build regenerated all 54 paged/expanded/table browser inputs and six
real Cancel exports before the full native verifier. The other 2,240 baseline
inputs retain independently checked hashes. Browser checks prove maximal
measured row boundaries, complete cell content even when identifiers wrap
across visual lines, unchanged 70/130 pt native-authored columns, repeated
headers, PDF image presence and exact per-page/per-cell PDF content at the
unscaled measured coordinates. Resize/zoom, mixed geometry/areas, source exports,
selection/history and full IndexedDB records survive Cancel and recovered Redo.
Native versus browser page counts are **4/8, 5/10 and 6/10**, respectively:
explicitly not native pagination parity.

Final evidence: `~/.copilot/evidence/4wp-tables-20261114-gate-06/`;
independent byte/SHA-verified backup:
`~/.copilot/evidence-backups/4wp-tables-20261114-gate-06/`.
`reproduction.json` records the baseline, final build hashes, gate counts and
definition/input comparisons. Native originals/getters/PDFs/reexports, complete
browser cell/column measurements, PDF content, real Cancel screenshots/recovery
reports and structured suite results are retained outside the disposable
worktree. The backup has its own complete `SHA256-MANIFEST.json`. Earlier attempts
are retained separately and are not the final verified build.

Paged-column increment verification: **436 unit tests, 145 production browser
tests and 2,337 full-4D 21.2 `F0012102` import/export/reopen cases passed**.
All 2,300 #55 case definitions are unchanged by name; 2,240 unaffected exports
and their original input dependencies retain independently checked exact hashes.
The final production build regenerated all 54 prior paged/expanded/table
downloads and 35 new column downloads; eight actual headed paged Cancel exports
complete the final manifest. Continuous-mode Cancel was also repeated separately.
Every mode compares source/history/recovery state, editor/paged DOM, both
selection endpoints, scope, zoom and complete IndexedDB records in clean/Redo
and dirty/Undo states. The augmented manifest was then re-imported, reexported
and reopened in full 4D under the exclusive native-gate ownership preflight.

The seven native column originals/getters/PDFs independently establish equal
geometry, explicit break progression, retained content/first-header mutations,
and the divider/narrow counterexamples. Supported two/three/four/breaks/mixed
cases have **native/browser body page counts 4/5, 3/4, 3/5, 3/3 and 5/6**;
unused area appendices add separate print sheets. Complete per-column PDF
content, exact measured token membership, unscaled native-authored column
widths/offsets, local image presence, native list markers and selected area
content are checked. Mixed-font PDF extraction uses glyph-center line grouping
so CJK font bounding boxes do not reorder same-line Latin text. This is
evidence of the declared browser subset, not native balancing or page-count parity.

Final column evidence: `~/.copilot/evidence/4wp-columns-20261114-gate-02/`;
independent byte/SHA-verified backup:
`~/.copilot/evidence-backups/4wp-columns-20261114-gate-02/`.
`reproduction.json` records the exact baseline/head/source/build identities and
final gates; `baseline-comparison.json`, input/dependency hash lists, production
suite logs, native originals/targets/getters/reexports/PDFs, browser measurements,
complete column-PDF assertions and real Cancel captures are retained. `Source/`
and `Build/` preserve reproduction inputs outside the disposable worktree.
Each independent backup has a complete `SHA256-MANIFEST.json`. The first complete
native generation is separately retained and backed up as
`4wp-columns-20261114-gate-01`; it is not the final augmented-manifest evidence.

Continuous-section #57 verification (**Available on main; deployed**):
**438 unit tests, 149 production browser tests and 2,409 full-4D
21.2 `F0012102` import/export/reopen cases passed**. Independent native generation
passed 2,399 cases before final-build regeneration and real Cancel exports.
All 2,337 #56 definitions remain unchanged by name, with 2,240 unaffected input
hashes and 2,761 input/dependency archives independently compared. The final
manifest contains 97 regenerated affected baseline exports (including eight
prior Cancel cases) and 72 additional continuous-section cases.

All twelve actual headed Chromium print-preview Cancel states passed: continuous,
paged, expanded, tables, columns and compatible seams, each clean/Redo and
dirty/Undo. Full DOM, selection endpoints, scope, zoom, history, IndexedDB and
exact source bytes remain unchanged. The final augmented manifest was then
strictly imported, exported and reopened in full 4D under the exclusive native
ownership preflight and lock. The rich-content seam regression also checks
remaining-page capacity, ordered fitting list/image/formula/table content,
continued complete rows, repeated native headers and measured PDF membership.
These checks do not expand the supported seam subset or claim native pagination.

Final continuous-section evidence:
`~/.copilot/evidence/4wp-continuous-20261114-gate-02/`; independent byte/SHA-verified
backup: `~/.copilot/evidence-backups/4wp-continuous-20261114-gate-02/`.
`reproduction.json` records the exact source/build/head identities and gates;
`Source/`, `Build/`, `Validation/` and `BrowserTestArtifacts/` retain reproduction
inputs, native/browser/Cancel evidence and all final comparisons outside the
disposable worktree. Both copies have a complete `SHA256-MANIFEST.json`.
The independently backed-up passing generation
`4wp-continuous-20261114-generation-02` and failed first target-terminator attempt
`4wp-continuous-20261114-gate-01` remain separate; neither is the final release
evidence. Earlier diagnostic Cancel logs are retained alongside the passing
`cancel-verified.log` and final native recheck, not presented as passing gates.

Table-cell-list increment verification (**Available/deployed #59**):
**440 units, 153 production browser tests, 2,486 installed-4D generation cases
and a final strict 2,498-case import/export/reopen gate passed** under 4D 21.2
`F0012102`. The exact #58 repair baseline is
`350b7ed2616b989574b09e61343395a3080a54ac`; its seven test-only resize-readiness
lines remain intact. Final browser tests used an exclusive, strict/no-reuse
preview port and independently matched served HTML/JS/CSS bytes and SHA256s.
All **2,409 #57 native definitions** remain unchanged by name, with **2,240
unaffected input hashes and 2,761 dependency archives** independently compared.
The 169 affected baseline definitions were regenerated from final production
assets, including all ten prior paginated Cancel exports. The 89 new definitions
cover real cell-list downloads, safe native edit/Undo/recovered-Redo targets and
the new actual Cancel mode.

All **fourteen** real headed Chromium print-preview Cancel states passed:
continuous, paged, expanded, tables, columns, seams and cell lists, each clean/Redo
and dirty/Undo. Full DOM, selection endpoints, scope, zoom, exact original/dirty
bytes, history and entire IndexedDB records are compared without normalizing
away changes or freezing timers. Native originals/getters/PDFs and browser PDFs
establish complete row/cell/list/marker membership, per-cell starts, marker/font
geometry, wrapped words, first/facing areas and mixed paper geometry. Zero/one/two
native leading header rows, local pictures, inert formulas, residual seam
capacity and terminal oversized/unsupported fallback are included.

Final evidence: `~/.copilot/evidence/4wp-cell-lists-20261114-gate-02/`;
independent byte/SHA-verified backup:
`~/.copilot/evidence-backups/4wp-cell-lists-20261114-gate-02/`.
`Source/`, `Build/`, `Validation/`, native/browser/Cancel artifacts, baseline
comparisons and `reproduction.json` retain exact source/build/commit identities.
The independently backed-up 2,486-case generation (`gate-01`), passing focused
native/Cancel proof (`browser-probe-06`) and precommit evidence remain separate.
No earlier evidence was overwritten or deleted.

## Layout preview and browser printing (available on main)

White section surfaces reflect supported oriented paper dimensions and each
section's inherited/explicit margins. Their height is a **minimum**, not a
clipped page or an automatic page count. Long content continues vertically.
Columns balance between explicit page/section boundaries, with native count
and gap; continuous section separators remain visible authoring guides.

**Print / Save as PDF** opens a localized, keyboard-accessible panel. **Open
browser print dialog** invokes the browser's local printing flow; choose a
printer or Save as PDF there. Opening or canceling the dialog does not mean a
file was saved. The browser's own Print command also prepares the isolated
view. No upload, server PDF service, formula evaluation or download-status
change occurs.

The print projection is freshly rendered from a disposable copy using the
same allowlist, not raw XHTML/CSS or the contenteditable DOM. It does not replace
the editor, change selection/zoom, dirty state, XML/metadata, bookmark pairs,
undo/redo, versions, recovery or resource bytes. Images are local safe rasters;
external/unsupported images and native structures keep explicit placeholders.
Formula cards retain source and available stored values. They are not evaluated.
Unloaded/undecodable images fail explicitly before the button opens the dialog.
Unsupported/ambiguous page, section or column settings disable the button;
printing through the browser menu produces an explicit failure notice, not an
empty page or a misleading default-layout document.
Printing also requires at least **72 pt of text width per column and 72 pt of
text height**. This conservative print-only limit prevents tiny native-valid
areas from clipping browser glyphs; it never clamps or rewrites native settings.

Print CSS uses named `@page` rules for physical size/orientation and four margins.
Explicit page and new-page section breaks start browser pages; identical-geometry
continuous sections can share a page. **Changed geometry in a continuous section
starts a browser page**, rather than pretending to match 4D's continuous layout.
Columns use browser flow/balancing. Selection highlights, break/debug markers,
editor controls, dark chrome and zoom transforms are excluded; real text,
tables, raster images and formula/unsupported placeholders remain. Print tables
fit the available width with wrapping; images fit the content width/height.
This intentionally differs from native table sizing and object layout.

Use the document paper size, default scaling and CSS margins, and disable
browser-added headers/footers. Browser/printer margin overrides, background
printing, fonts, wrapping and automatic page counts can differ. Absolute tab
stops, right/center/decimal/bar alignment and leaders are **not rendered**; only
the repeating default interval is approximate. Continuous mode uses the labeled
header/footer content appendix described above, not native page-margin placement
or repetition. The selected paged increment adds the bounded projection described
above. Arbitrary floating-object layout and native-equivalent automatic pagination remain
proposals, not started.
No arbitrary document, printer or native visual-layout parity is certified.

PDF regressions inspect extracted content, image presence, page dimensions,
word bounding boxes and rasterized theme-independent white paper, not just
button visibility. Browser tests require Poppler (`pdftotext`, `pdfimages`,
`pdftoppm`; e.g. `brew install poppler` or `apt install poppler-utils`).
The full-4D gate additionally creates its own native print originals/PDFs and
effective section/column/tab getters before opening the browser. Evidence
includes `Output/print-report.json`, native and browser PDFs and
`Output/print-browser-report.json`. These are scoped geometry/content and
unchanged-archive assertions, **not** a claim of exact pagination or tab parity.
On a desktop with an installed Playwright Chromium, run
`node scripts/check-print-cancel.mjs /absolute/path/to/native-evidence` after the
gate. It opens the real headed browser print preview and clicks its Cancel button
for clean/redo and dirty/undo states, comparing the editor DOM, selection, zoom
and complete IndexedDB recovery record. Its report/screenshots stay in the
evidence directory. Run builds/browser suites **before**, not during, the native
gate: replacing `dist` while its server is handling a reload invalidates asset URLs.

The merged preview/printing increment passed **394 unit tests, 90 browser tests and 1,548 full-4D
import/export/reopen cases** in 4D 21.2 `F0012102`. The original 1,532 cases
remain; 16 new browser downloads bracket printing of eight independently
native-created sources (portrait, landscape, wide portrait, mixed sections,
columns, native right/leader tabs, long rich content and hidden associations).
Their 29 browser PDF sheets retain the checked content and paper geometry
(within 1 pt, allowing Chromium's subpoint PDF rounding). The rich source is
5 native pages versus 6 browser pages: this is intentionally **not pagination
parity**. Real headed Chromium Cancel is also checked with complete recovery
snapshots, not only simulated print events.

For merged #53, run
`node scripts/check-print-cancel.mjs /absolute/path/to/native-evidence --paged`
once after the gate. It opens the actual headed Chromium print preview with
the paged view active, compares the paged/editor DOM, selection, zoom and
complete recovery record across Cancel, and appends two captured downloads to
`Input/cases.json`. Re-run the complete native import/export/reopen verifier
after importing this augmented manifest in full 4D. The default command retains
its continuous-print behavior; `--paged` outputs use separate names.
For expanded pagination, also run the command with `--expanded`: it uses the
independent long paragraph/inline-picture/formula original and edit target,
captures actual Cancel downloads in clean/Redo and dirty/Undo states and retains
the complete paged/editor/selection/IndexedDB comparison. Its separate
`expanded-cancel-*` names do not replace any baseline case definitions.
For paged tables, also run with `--tables`: the independent mixed-section table,
native repeating header, inline picture/formula and bookmark original/edit target
are checked in both real Cancel states. Its `tables-cancel-*` downloads extend
the manifest without replacing the baseline paged/expanded definitions; native
cell/header getters are compared after import and reopen.
For paged columns, also run with `--columns`: its independent mixed-section
column original and first-header target cover actual Cancel in clean/Redo and
dirty/Undo states. `columns-cancel-*` downloads add two cases without replacing
any prior definitions.
For compatible continuous-section pages, also run with `--seams`: its independent
native overflow source and first-paragraph mutation target cover actual Cancel
in clean/Redo and dirty/Undo states. All six modes (default continuous print,
`--paged`, `--expanded`, `--tables`, `--columns`, `--seams`) compare full DOM,
exact selection endpoint paths, scope, zoom, history, IndexedDB and before/after
source export bytes. `seams-cancel-*` adds two cases without replacing any
baseline definition. The harness settles its own download-triggered draft write
before taking the snapshots and fixes the browser's Date per phase (timers still
run), so dirty-export modification timestamps are identical for exact byte
comparison. It does not normalize away DOM, history, recovery or source changes.
Run all modes, then
re-import the augmented manifest in full 4D and run the complete verifier.

For the strict #56 baseline comparison, run
`node scripts/reproduce-paged.mjs NEW_EVIDENCE_DIRECTORY SEALED_56_BASELINE`
after the initial full gate. It preserves unrelated baseline input/dependency
bytes and regenerates affected paged exports with the current production build.
Run all Cancel modes, then the same command with `--compare` to check every
baseline definition and unaffected hash. Finally run
`bash scripts/check-web-editor-native.sh EVIDENCE_DIRECTORY --recheck`
from the repository root. Recheck uses the same exclusive ownership preflight
and lock and rejects an existing final recheck log.

## GitHub Pages demo

The [Publish web editor demo workflow](../.github/workflows/web-editor-pages.yml)
tests and builds the application, uploads `web-editor/dist`, and deploys it to
GitHub Pages on relevant pushes to `main` or a manual run from `main`. Pull
requests do not publish a demo. Deployment uses the `github-pages` environment
and GitHub's OIDC authentication, with no deployment secrets.
Feature descriptions here describe the checked-out code; an unmerged branch
does not update the deployed demo.

After merging the workflow, select **Settings > Pages > Build and deployment >
Source: GitHub Actions** in the repository, then run **Publish web editor demo**.
The default project site URL is `https://miyako.github.io/4d-ql/`. Vite emits
relative asset URLs so the same build works at that project path or a custom
domain. Deploy the entire `dist/` directory, including its license notices.

## Editing

The app opens with **North Room**, a fictional concept brief for a neighbourhood
reading room. Its editorial typography, inline emphasis, pull quote and small
project table are editable document content, not a feature checklist. The
English example is independent of the UI language and can be downloaded as a
`.4wp`. It starts without unsaved changes; **New document** still opens a blank
page.

Open or drop your own `.4wp`, or start a new document. Selections can span
adjacent formatting runs and paragraphs. Type, cut, paste or apply bold, italic,
underline, strikethrough, highlighting, font, size and color without flattening
the original XML formatting. Underline and strikethrough toggle independently.
The toolbar indicates mixed selections instead of reporting only the first run;
formatting retains the selection and its direction.
Without a text selection, character formatting applies to the whole active
run. Enter splits at the caret; Backspace/Delete joins compatible adjacent
paragraphs; Shift+Enter inserts a line break. Enter on an empty list item exits
the list. Deletion across incompatible containers, such as separate table
cells, is rejected rather than restructuring the document implicitly.

The toolbar provides document paragraph styles plus Normal, Heading 1,
Heading 2 and Quote, lists, alignment and indentation. **More tools** includes
paragraph/line spacing, simple table insertion and row/column edits. Select
a table cell to modify its row or column; merged and irregular tables remain
protected from structural edits. **Editing capabilities** explains current
document restrictions; selecting a cell also shows operation-specific reasons
under More tools. The notices and table actions support keyboard access,
all six UI languages, small screens and system/light/dark appearance.
Rich clipboard paste retains basic text
formatting, paragraphs and lists, but discards scripts, remote images and
unsupported HTML. Copying an entire native document through HTML is not a
preservation workflow: use `.4wp` import/export.
Use Ctrl/Cmd+Shift+V to paste plain text, or **Paste plain text** under More
tools (the button requires clipboard permission). Clipboard failures and stale
asynchronous reads are reported rather than silently inserting elsewhere.
**Link** creates, updates or removes absolute HTTP, HTTPS and mailto links;
embedded credentials and active URL schemes are rejected. Links remain inert
in the editor. Select text to create a link; a caret inside an existing link
updates that whole link. Selections crossing existing links must remove them
before adding a replacement.

Insert PNG/JPEG files through the picker, clipboard image files or drag-and-drop
at the caret/drop position. New images fit the page width initially. Select an
image to resize proportionally or delete it; ordinary displayed images can
also be dragged to a new text position. Inserted images are embedded in the
XHTML, so exports and recovery do not depend on temporary browser URLs.
Each inserted image is limited to 8 MiB and 40 million pixels; resizing accepts
12-1200 pt. Unsupported native image formats remain preserved placeholders.

Find/replace searches literal text across adjacent formatting runs, with
optional case sensitivity and a 1,000-match limit. The footer shows
language-aware word/character counts and document zoom.

### Bookmark management (available on main)

**Bookmarks** opens a keyboard-accessible panel. Select text, an insertion
point, or supported structural boundaries in the document, then enter a name
and choose **Create from selection** (Enter also submits). Creation uses the
original XML projection and native UTF-16 mapping, including empty paragraphs,
Unicode, inline objects, native lists and scoped simple tables, not DOM
`textContent` offsets. Interior ranges spanning cells within one table are
accepted; ranges entering/leaving only part of a table
remain protected.

Choose a listed name to navigate and highlight it. The list and status show
the authoritative zero-based, end-exclusive UTF-16 pair. Text endpoints in
one cell or ordinary paragraphs restore a text selection/caret. Structural
or collapsed boundaries get a dashed marker; structural navigation does not
silently turn into 4D's cell-normalized selection or an editable text range.
If a native structure cannot be mapped safely, an explicit error retains its
original metadata. Escape closes the panel and returns focus to its toggle.

**Rename selected** preserves the exact raw pair; **Delete selected** removes
only that bookmark, never document text or resources. All three mutations
share the central XML transaction and document-wide undo/redo, versions and
IndexedDB recovery. They remain disabled for read-only documents; protected
text cannot acquire a new bookmark. Malformed or duplicate metadata is
preserved, not silently rewritten.

Full 4D 21.2 strips invalid ASCII name characters and overwrites duplicate
names. This UI deliberately does neither: empty names, ASCII spaces/controls
and ASCII punctuation other than `-` and `_` are rejected with a localized
error. Native-compatible Unicode names are preserved exactly, including
non-BMP/combining characters and Unicode spacing/punctuation; invalid
Unicode/XML is rejected. Names are case-sensitive (`ABC` and `abc` can
coexist), with no trimming or Unicode normalization. An exact duplicate create
or rename fails without changing either bookmark. Native evidence includes
1,024-character names; the existing document/archive budget still applies.

Undo/redo is document-wide with grouped typing and selection/caret restoration,
including recovered undo history. Editor-only cursor bookmarks are separate from
native 4D bookmark metadata; snapshots retain both text and native ranges atomically.
History is bounded to 100 snapshots and
approximately 8 MiB of UTF-16 undo history (at least the latest snapshot is
retained). **History** displays automatic versions and lets you name and
restore a version; restoration itself is undoable. Local versions are bounded
to 20 and approximately 8 MiB of UTF-16 XML, with the latest retained.

The current document, original archive resources, undo/redo and local versions
are saved to IndexedDB after a 450 ms pause. Reloading recovers the last
successfully saved session, including images. This is **one active local
session**, not a document library: opening/New replaces its context. Competing
tabs cannot silently overwrite one another's recovery data; a stale writer is
blocked with a download-first warning. Storage errors are visible.
Private browsing, storage eviction, clearing site data, changing browser/origin,
or closing before a pending save finishes can lose recovery data. Local history
is not an independent backup and is not embedded in exported `.4wp` files.

Download creates a genuine ZIP `.4wp` with XHTML, not a renamed HTML file, and
never overwrites the original. Keep independent downloaded copies of important
work. The browser prompts before abandoning edits that have not been downloaded,
even when locally saved. Download status means the browser received the file,
not that it has confirmed a disk write.

Appearance uses Write Pro-inspired blue accents in system/light/dark modes. The document remains white paper
for legibility; dark mode applies to the application chrome. English, Japanese,
French, German, Spanish and Italian UI strings live in `src/i18n.js` and
`src/tool-messages.js`; browser
language detection and the explicit selector share that catalog. Preferences
are stored locally. The toolbar wraps on small screens; complex tables may
scroll horizontally inside the document surface.

## Preservation contract and limits

The original XML DOM is the editing model, **not** the sanitized visual
projection. Untouched imports export the original archive byte-for-byte.
After editing, the app serializes the original DOM, modifying requested text,
formatting or structures and `datetimeModified`; every other archive entry keeps its
uncompressed bytes and name. ZIP compression, entry metadata and XML lexical
formatting may change. Unknown native CSS, attributes, elements, namespaces,
formulas and resource payloads are retained, not translated into editor markup.

The UI renders an allowlisted projection, never the source HTML or stylesheet
directly. Document scripts, navigation, external images, CSS URLs and embedded
active content do not run. Native formulas/data-source tables, protected text,
generic hidden objects remain protected. Headers/footers and supported stored
objects have separate capability-checked scopes described above. Supported
static inline/archive-relative PNG/JPEG/GIF/WebP and bounded native picture
wrappers are projected without network requests; other images and unsupported
objects have explicit placeholders.
They are still retained in exported archives.

### Formula-aware display (available on main)

Formula cards expose the **native tokenized source**, optional name and
**Saved value**, with a keyboard-focusable, localized **Read-only formula**
label. They never evaluate, detokenize or execute the source, fetch references,
or infer results from literals, page numbers or sample data. Source, names and
saved values are untrusted text, not HTML or CSS to execute.

Supported inline text formulas are XHTML `span` references with a quoted
`-d4-ref` (direct or from a supported native stylesheet rule), optional
`-d4-ref-name`, and text/ordinary nested-span content. The original XML,
attributes and archive resources remain authoritative. A distinguishable,
non-whitespace saved textual value is shown exactly, including `0`; otherwise
the card explicitly says the value is unavailable. Empty, NBSP, zero-width and
whitespace-only content is not treated as a saved result. Full 4D 21.2 exports
NBSP for independently computed text, empty, NBSP, numeric-zero and Unicode
formulas: **computation does not imply a cached result in the archive**.
Native import/export also preserves explicitly supplied saved text (`SAVED`
and `0` in the gate); those are stored content, not browser-computed values,
and may be stale.

Each supported text formula occupies **one native UTF-16 slot**, independent
of source/value length. In otherwise supported documents, typing/IME,
grapheme deletion, cut/paste, replacement and character formatting in adjacent
text use registered native-tape transactions, with or without bookmarks.
Paragraph split/join and rich paste can move an intact supported formula
between paragraphs. Formula subtree identity, order, XML/attributes and cached
text are checked atomically; crossing selections, boundary deletion into the
object and formula mutations fail without changing the model. Find/replace
does not search inside cards or match across a formula. History, versions and
recovery retain the original objects and resources.

Compiled `-d4-ref-url` resources, name-only/empty-source references, image
formulas, data-source tables, nested references and nontext results remain
protected. A compiled source is explicitly unavailable; its resource is not
decoded or executed. Surrounding-edit compatibility is not claimed for these
forms. In bookmarked documents they retain the existing whole-document guard.
Formula-containing list conversion, destructive selections across objects,
generic/malformed ranges, unsupported header/footer content, anchored/hidden objects and other
unsupported structures remain protected. The table capabilities below do not
permit formula mutation or crossing a formula atom; the combined transaction
retains formula tracking even without bookmark metadata. The native gate
repeats both established operation matrices, not every possible formula/table
combination.

Named text bookmarks are editable in documents consisting of paragraphs, native
indented/mixed-marker lists, native-shaped tables, ordinary inline
formatting/links and supported inline pictures. A central
transaction maps the original XML to native UTF-16 slots and adjusts bookmark
metadata for explicit edits, including typing/IME, cut, paste, replace-all,
paragraph split/join and image insertion/removal/movement. Formatting does not
shift ranges. Failed or unregistered text/structural changes roll back.

For unmerged tables, this includes edits within a cell, paragraph/list changes
within that cell, table insertion, row insertion/deletion and column deletion.
Column changes register descending cell splices as one atomic transaction,
checking the complete resulting native tape rather than temporarily irregular
rows. **Column insertion** now supports cell-anchored bookmarks, collapsed
cell boundaries, bookmarks outside the table and bookmarks enclosing the
table with following text. A collapsed point at an inserted column's boundary
moves after the new cell, unlike ordinary text insertion. Row-separator
anchors and bookmarks ending exactly at the table boundary block column
insertion: native 4D can delete or relocate them. They are never silently
dropped or coerced.

**Interior cross-cell bookmarks** can be imported, created, navigated, renamed,
deleted and formatted. Text/Unicode, paragraph/line breaks, paste and inline
pictures may be added **outside spanning ranges or at their endpoints**.
Insertion strictly inside such a range is protected: native 4D can expand
its raw pair to a rectangular cell selection. Deletion/replacement and table
insertion/row/column changes are protected whenever such a bookmark exists,
because their native normalization is command-dependent. This is intentionally
conservative, including deletions outside the spanning range. Destructive
browser selections across cells remain rejected. An edit that would turn an
enclosing bookmark into an unsupported partial-table range rolls back.

**Merged-cell text editing** supports direct `tr`/`td`/`th` grids with positive,
nonoverlapping, complete `rowspan`/`colspan` coverage (at most 1,000 columns).
Cell paragraph/list content, spans, attributes and resources stay authoritative.
Native horizontal, vertical and rectangular merges are independently probed.
Text edits within a cell use the same registered tape; cross-cell bookmarks
have the restrictions above. Row/column edits on merged/irregular tables are
still protected, not expanded or flattened. All supported tables require body
paragraphs immediately before and after them; nested tables are not supported.
Bookmarks confined to a cell/row separator, collapsed boundaries and full-table
enclosures retain their previous support except for the explicit column-insertion
anchor guard. Deleting the final row/column remains rejected.

Full 4D 21.2 represents native list indentation as flat `li` elements with
paragraph indentation and marker CSS, sometimes in adjacent `ul`/`ol` groups.
Those levels are retained through text, paste, split/join, marker and indentation
edits; only compatible sibling items can be joined. Arbitrarily nested HTML
lists are different: native 21.2 imports their child text into the parent item,
including added spaces. Such bookmarked imports and nested-list insertion
remain protected, not silently flattened or advertised as native multilevel
list support. Newer 4D multi-level style-sheet semantics are not certified.

**Replacement policy:** replacing a selection replays native **deletion followed
by insertion**, not a single `WP SET TEXT` replacement (which has different,
content-dependent boundary behavior). Insertion at a nonempty bookmark's start
shifts it; insertion inside extends it; insertion at its end is excluded. A
collapsed bookmark stays before insertion at its own position. Deletion shrinks
overlaps and removes entirely deleted nonempty bookmarks and strictly enclosed
collapsed bookmarks, as observed in 4D. Thus replacing an entire bookmarked
selection removes that bookmark; undo restores it. Arbitrary native-command
equivalence is not claimed.

Generic `ranges` metadata, malformed/duplicate/out-of-bounds bookmarks, endpoints
inside surrogate pairs, and bookmarked documents containing invalid/incomplete
table grids, ranges entering/leaving only part of a table, nested HTML lists, unsupported formula forms,
unsupported section/header/footer/anchored structures, hidden content or unsupported
pictures remain **read-only**. Unsupported browser input operations (for example
word-delete/autocorrect input types without established mapping) are also rejected,
not inferred from a whole-run text diff. Standard typing, grapheme deletion and
IME composition use explicit selection ranges. No bookmark stripping, silent
conversion or destructive import mode is offered.

This is an experimental **document editor**, not a replacement for the
4D Write Pro engine. It does not evaluate formulas or reproduce native
pagination, sections, tabs, image wrapping, font metrics or advanced native
layout. Section-break paragraphs and protected/native structures cannot be
split or merged destructively. Unsupported content is not necessarily shown in full. Preserve your
originals and **reopen edited downloads in the full 4D application before
production use**. New-document and edit compatibility has structural tests
against real 4D 21.2 fixtures. An isolated full-4D compatibility gate also verifies
the cases described below; this is scoped evidence, not general native-layout
or arbitrary-document certification.

Input limits: 16 MiB ZIP, 32 MiB total expanded data, 512 entries, 20,000
elements, 60,000 DOM nodes, 64 levels. CRC corruption, ambiguous HTML entries,
DTD/entity declarations, encryption, multi-disk ZIP and ZIP64 are rejected.
Exactly one UTF-8 XHTML document in the XHTML namespace is required. Bare HTML
is not accepted as `.4wp`.
Edits are also checked for XML validity, complexity and expanded archive budget;
failed transactions roll back. Export additionally enforces the compressed ZIP
limit and leaves the open document intact if it cannot produce an acceptable
archive. Large documents/images may reach browser storage quotas sooner.

## Verify

```sh
npm test
npx playwright install chromium
npm run test:browser
```

Tests use the repository's six real `.4wp` fixtures, exercise untouched and
edited round trips, native resource retention, bookmark/protected-content
guards and native-offset transformations, malformed input, localization,
continuous editing, tables/images,
clipboard sanitization, version restoration, reload recovery and browser
editing/download workflows.
The browser suite builds and serves the production bundle, including its CSP.
See [format evidence](../docs/WRITEPRO-FORMAT.md) for the observed 4D dialect.

### Full-4D release gate

Before releasing import/export changes, run from the repository root:

```sh
bash scripts/check-web-editor-native.sh /absolute/path/to/new-evidence-directory
```

The output directory must not exist and should be outside disposable worktrees.
The script requires installed web-editor dependencies and Playwright Chromium.
It defaults to `/Applications/4D 21.2/4D.app/Contents/MacOS/4D`; set `FOURD` to
another full application's executable if needed. **tool4d cannot substitute for
the full application's Write Pro engine.** Only a copied repository fixture
project runs, dataless, without opening personal projects or changing fixtures.
Missing application/report, compilation/native errors, timeouts and semantic
differences fail the gate. The gate uses the shared fail-fast directory lock
`$HOME/.copilot/4d-ql-native-gate.lock`; coordinate app ownership before manual
probes too. A live lock is never removed by another run. A timeout terminates
only that gate's own process.

The gate first runs isolated native section/break, page geometry, offset and mutation probes, then creates
genuine browser downloads and model exports, imports them in full 4D, exports
them through 4D and reopens those exports. The previous 1,079 cases include the original 14:
the preloaded brief, a newly formatted document with a hyperlink, image and table,
and original and browser-exported versions of all six fixtures. It checks text, metadata,
image/table counts, formula sources and links; sampled first-character
formatting is compared with native originals. The new document additionally
checks the actual first glyph, bold/italic/underline/strikethrough, size,
highlight and hyperlink, and native decoding of the inserted 48-by-32 image.
Unsupported bookmarked/read-only cases must also remain byte-identical in browser exports.

The 82 page cases add model exports and genuine browser Apply/Undo/recovered-Redo
downloads for presets, custom/rotated paper, fractional and zero margins,
section inheritance, six complex table shapes and all fourteen formula variants.
Each is compared with a separately imported original mutated by native
`WP SET ATTRIBUTES`, never an expected result derived from the editor model.
Native document/section getters, native PDF MediaBox geometry, text, raw bookmark
metadata, formula/table XML and original resource bytes are checked. The
original 997 cases remain in the gate. Page probes also retain default,
orientation, whole-point rounding and native invalid-value observations in
`Output/page-report.json`, native-created originals/targets and PDFs.

The section increment adds 172 cases, bringing the gate to **1,251
import/export/reopen cases**. Independently native-created start/interior/end
page/new-page/continuous break probes with Unicode, formulas and bookmark
endpoints; ordinary-paragraph replacement and deletion counterexamples;
existing inherited/overridden sections; names, resets, first-page headers and
anchored-section associations. `Output/section-report.json` retains all 27
structural probes, 17 name export/reimport probes and explicit settings/reset
observations. The cases also exercise typing after breaks and combined landscape
section overrides with formulas and bookmarks. Model exports and
real-browser Apply/Undo/recovered-Redo downloads are compared with independent
native `WP Insert break`, `WP SET ATTRIBUTES` and `WP RESET ATTRIBUTES` edits.
Native getters, per-slot ranges, raw bookmark pairs, effective section geometry,
names, header/footer/anchor associations, native-reexported body and stylesheet
XML, and original resource bytes must agree. Merely opening the ZIP is not a pass.

The additional cases cover 165 native delete-then-insert combinations (all
selection boundaries in a nine-character document, empty/ASCII/non-BMP insertion,
overlapping and collapsed bookmarks at interior/start/end positions), eleven
native offset fixtures, ten native structural/formatting operations, and six
real-browser bookmark editing downloads.
Imported and reopened bookmark names, positions and selected text must equal
the independently executed native operations, not just the browser model's
predictions. The offset fixtures cover Japanese, non-BMP and combining text,
paragraphs, soft breaks, inline pictures, empty placeholders, flat lists and
styled runs. `tests/fixtures/native-ranges.json` preserves a compact native oracle;
`tests/fixtures/native-structures.json` adds the original structural oracle;
`tests/fixtures/native-complex.json` adds 25 representative complex-table cases.
The original structural
probe executes 32 table/list cases twice: with single-slot/collapsed and
whole-table bookmarks, and with an additional partial-cross-boundary matrix.
The gate compares 30 supported model edits/offset exports and 21 real-browser
downloads with independent native results, plus an unchanged protected boundary
document. Counterexamples remain in the native report, not counted as supported
editing cases.
Both raw serialized bookmark pairs and native bookmark names, positions and
selected text are checked. Native `WP Bookmark range` can normalize cell
selections, so its reported pair is not substituted for the raw archive pair.
Regenerate the oracles only from a successful full-4D probe:

```sh
cd web-editor
node scripts/capture-range-evidence.mjs /absolute/path/to/evidence-directory
```

The management increment adds 114 import/export/reopen cases to the previous
258: 88 exact-name exports, ten model operations and 16 browser downloads
(including five after undo/redo and IndexedDB reload recovery).
An independent native probe covers 160 name inputs and 13 management
operations: empty/invalid/escaped ASCII names, Unicode and case distinctions,
long names, native duplicate overwrite counterexamples, collapsed selections,
rename/delete, cell text/terminators, row separators, whole tables and native
list ranges. The browser intentionally rejects the normalization/overwrite
counterexamples rather than claiming native command equivalence for them.
Both browser/model input archives and native reexports are checked against
native raw serialized pairs, names, getter ranges and selected text.

The formula increment adds 497 cases to the preceding 372: 14 independent
native originals, 240 model edits, 240 actual browser downloads and three
downloads after undo/redo and IndexedDB reload. The native oracle covers
uncomputed/computed formulas, empty/NBSP/zero/Unicode sources, names, formatting,
supplied saved text/zero/empty/NBSP, anchored image formulas and data-source
tables. Twelve supported variants each receive twenty independent native
operations: insertion before/at either boundary/after, deletion, deletion then
insertion, split/join on either side and exactly at both formula boundaries,
line break, rich-text-equivalent paste before/after/at either boundary,
and formatting. Actual browser IME commits are included. Raw serialized pairs,
native text/bookmark getters, metadata,
source/name/cache, unchanged formula XML and resource bytes are checked.
Compiled-resource preservation has inert browser/model tests, **not** native
compiled-source decoding or editing certification.
`tests/fixtures/native-formulas.json` is regenerated by the same oracle capture
script. The shared `$HOME/.copilot/4d-ql-native-gate.lock` serializes full-4D
gates across worktrees; a held lock fails explicitly instead of launching a
second application instance. Coordinate ownership; never remove another run's lock.

The broader-range increment adds 128 round trips to the 869-case formula baseline:
84 scoped model exports and 44 actual browser downloads (22 operations, each
also downloaded after undo, IndexedDB reload and recovered redo).
`wp_complex_probe` independently executes 108 native cases: every collapsed
point and ordered endpoint pair in six shapes (ordinary, uneven-length,
empty-cell, horizontal merge, vertical merge and rectangular merge), across
18 text/formatting/table commands. Native text ranges over each cell establish
scope independently of the editor. Raw original/native pairs, getter ranges
and selected text remain in `Output/range-report.json` and the complex archives.
Scoped exports remove only out-of-scope test bookmarks, not document content;
an opaque test resource verifies byte preservation in browser/model exports.
The matrix retains counterexamples for interior insertion, cross-cell deletion,
structural normalization and column separator anchors. The gate does not
replay those commands as supposedly compatible browser operations.

Keep the entire evidence directory (including `Output/range-report.json`,
`Output/range-errors.json`, the copied probe project, native originals and
reexports, `Input/cases.json`, `Output/native-report.json`, and both native logs)
outside disposable worktrees. These are scoped observations from full 4D 21.2
`F0012102`, not certification of arbitrary bookmark or native-layout semantics.

The gate does not evaluate formulas or certify pagination, visual
fidelity, all character formatting, other 4D versions or untested documents.
