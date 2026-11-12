# 4WP Editor

A standalone, local-first HTML/CSS/JavaScript editor for ZIP-packaged 4D Write
Pro `.4wp` documents. It has no dependency on Swift, Quick Look, a backend, or
the 4D runtime. Files are processed in the browser and are not uploaded.

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
underline, font, size and color without flattening the original XML formatting.
Without a text selection, character formatting applies to the whole active
run. Enter splits at the caret; Backspace/Delete joins compatible adjacent
paragraphs; Shift+Enter inserts a line break. Enter on an empty list item exits
the list. Deletion across incompatible containers, such as separate table
cells, is rejected rather than restructuring the document implicitly.

The toolbar provides document paragraph styles plus Normal, Heading 1,
Heading 2 and Quote, lists, alignment and indentation. **More tools** includes
paragraph/line spacing, simple table insertion and row/column edits. Select
a table cell to modify its row or column; merged and irregular tables remain
protected from structural edits. Rich clipboard paste retains basic text
formatting, paragraphs and lists, but discards scripts, remote images and
unsupported HTML. Copying an entire native document through HTML is not a
preservation workflow: use `.4wp` import/export.

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

Undo/redo is document-wide with grouped typing, bounded to 100 snapshots and
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

Documents with nonempty bookmark/range metadata are **read-only**, because
changing text without 4D's character-offset semantics could corrupt ranges.
No bookmark stripping, silent conversion or destructive import mode is offered.

This is an experimental **document editor**, not a replacement for the
4D Write Pro engine. It does not evaluate formulas or reproduce native
pagination, sections, tabs, image wrapping, font metrics or advanced native
layout. Section-break paragraphs and protected/native structures cannot be
split or merged destructively. Unsupported content is not necessarily shown in full. Preserve your
originals and **reopen edited downloads in the full 4D application before
production use**. New-document and edit compatibility has structural tests
against real 4D 21.2 fixtures; native 4D reopening is not certified.

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
guards, malformed input, localization, continuous editing, tables/images,
clipboard sanitization, version restoration, reload recovery and browser
editing/download workflows.
The browser suite builds and serves the production bundle, including its CSP.
See [format evidence](../docs/WRITEPRO-FORMAT.md) for the observed 4D dialect.
