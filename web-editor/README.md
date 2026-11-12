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

Open or drop your own `.4wp`, or start a new document. Click a text run to edit;
select text **within one run** to apply bold, italic, underline, font, size or
color. With no selection, formatting applies to the whole active run. Runs
correspond to the original XML text nodes, so adjacent runs can have different
formatting. Cross-run selections are not supported. Paragraph alignment and
adding paragraphs are available; Enter inserts a new paragraph after the active
top-level paragraph, not a split at the caret. Shift+Enter inserts a line break.
Inside tables/lists, use the existing text runs; paragraph insertion there is
disabled. With no active run, the add button appends a body paragraph.

Undo/redo is document-wide, bounded to 100 snapshots and approximately 8 MiB
of UTF-16 history (at least the latest snapshot is retained). Download creates
a genuine ZIP `.4wp` with XHTML, not a renamed HTML file. The original is never
overwritten. Download is not autosave: keep the downloaded file before closing
the tab. The browser prompts before abandoning edits that have not been
downloaded. Download status means the browser received the file, not that it
has confirmed a disk write.

Appearance uses Write Pro-inspired blue accents in system/light/dark modes. The document remains white paper
for legibility; dark mode applies to the application chrome. English, Japanese,
French, German, Spanish and Italian UI strings live in `src/i18n.js`; browser
language detection and the explicit selector share that catalog. Preferences
are stored locally. The toolbar wraps on small screens; complex tables may
scroll horizontally inside the document surface.

## Preservation contract and limits

The original XML DOM is the editing model, **not** the sanitized visual
projection. Untouched imports export the original archive byte-for-byte.
After editing, the app serializes the original DOM, modifying only edited text
or formatting and `datetimeModified`; every other archive entry keeps its
uncompressed bytes and name. ZIP compression, entry metadata and XML lexical
formatting may change. Unknown native CSS, attributes, elements, namespaces,
formulas and resource payloads are retained, not translated into editor markup.

The UI renders an allowlisted projection, never the source HTML or stylesheet
directly. Document scripts, navigation, external images, CSS URLs and embedded
active content do not run. Native formulas/data-source tables, protected text,
headers/footers, hidden or anchored objects are not editable. Browser-compatible
inline PNG/JPEG/GIF/WebP images are shown; other images (including archive-relative
assets and native 4DPicture wrappers) and unsupported objects have placeholders.
They are still retained in exported archives.

Documents with nonempty bookmark/range metadata are **read-only**, because
changing text without 4D's character-offset semantics could corrupt ranges.
No bookmark stripping, silent conversion or destructive import mode is offered.

This is an experimental **text/formatting editor**, not a replacement for the
4D Write Pro engine. It does not evaluate formulas or reproduce native
pagination, sections, tabs, image wrapping, font metrics or advanced native
layout. There is no image/table insertion, structural deletion or rich HTML
paste. Unsupported content is not necessarily shown in full. Preserve your
originals and **reopen edited downloads in the full 4D application before
production use**. New-document and edit compatibility has structural tests
against real 4D 21.2 fixtures; native 4D reopening is not certified.

Input limits: 16 MiB ZIP, 32 MiB total expanded data, 512 entries, 20,000
elements, 60,000 DOM nodes, 64 levels. CRC corruption, ambiguous HTML entries,
DTD/entity declarations, encryption, multi-disk ZIP and ZIP64 are rejected.
Exactly one UTF-8 XHTML document in the XHTML namespace is required. Bare HTML
is not accepted as `.4wp`.

## Verify

```sh
npm test
npx playwright install chromium
npm run test:browser
```

Tests use the repository's six real `.4wp` fixtures, exercise untouched and
edited round trips, native resource retention, bookmark/protected-content
guards, malformed input, localization, and browser editing/download workflows.
The browser suite builds and serves the production bundle, including its CSP.
See [format evidence](../docs/WRITEPRO-FORMAT.md) for the observed 4D dialect.
