# 4WP Editor

A standalone, local-first HTML/CSS/JavaScript editor for ZIP-packaged 4D Write
Pro `.4wp` documents. It has no dependency on Swift, Quick Look, a backend, or
the 4D runtime. Files are processed in the browser and are not uploaded.

## Roadmap and status

Status snapshot: `main` at
[`643c520` / #41](https://github.com/miyako/4d-ql/pull/41).
**Available** means merged there; **In progress** is this unmerged increment;
**Planned** is approved subsequent work, not implemented here;
**Proposed** is an unscheduled idea requiring further decisions.
Phase numbers below organize this roadmap, not past PR numbers.
Phase 7 is pending in this branch, not in that main baseline;
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
| 7. Broader table/range safety | Cell-anchored column insertion; interior cross-cell bookmark management, formatting and guarded additions; grid-validated merged-cell text editing; localized capability reasons | In progress; this independent, unmerged increment. Destructive cross-cell operations, merged structural edits, nested tables and generic ranges remain protected |
| 8. Richer media and objects | More native picture formats, anchored objects and text boxes with preservation-aware controls | Proposed |
| 9. Document/page structure | Page/section settings, headers/footers, tabs and columns | Proposed |
| 10. Layout/printing fidelity | Better pagination, print output and object wrapping, with native/browser differences explicit | Proposed |
| 11. Release readiness | Accessibility, mobile usability, compatibility matrix, persistence/export reliability and release criteria; improvements remain incremental throughout | Proposed completion criteria |

Phases 8 onward are unscheduled proposals, not an authorized implementation queue.
Page/section settings and headers/footers are not part of this increment.
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
accepted in this increment; ranges entering/leaving only part of a table
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
headers/footers, hidden or anchored objects are not editable. Browser-compatible
inline and archive-relative PNG/JPEG/GIF/WebP images are shown without network
requests; other images (including native 4DPicture wrappers) and unsupported
objects have placeholders.
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
generic/malformed ranges, headers/footers, anchored/hidden objects and other
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
section/header/footer/anchored structures, hidden content or unsupported
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

The gate first runs isolated native offset and mutation probes, then creates
genuine browser downloads and model exports, imports them in full 4D, exports
them through 4D and reopens those exports. Its 997 cases include the original 14:
the preloaded brief, a newly formatted document with a hyperlink, image and table,
and original and browser-exported versions of all six fixtures. It checks text, metadata,
image/table counts, formula sources and links; sampled first-character
formatting is compared with native originals. The new document additionally
checks the actual first glyph, bold/italic/underline/strikethrough, size,
highlight and hyperlink, and native decoding of the inserted 48-by-32 image.
Unsupported bookmarked/read-only cases must also remain byte-identical in browser exports.

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
