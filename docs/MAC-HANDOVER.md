# macOS session handover

Written at the end of a cloud (Linux) session so work can resume on a Mac. Repo
state described here is `main` at `bae7551` (#73 merged). Everything below marked
**not verified** could not be checked from Linux.

## State of the repository

- No uncommitted or stashed work remains from the cloud session.
- Merged this session: #70 (component-wise path confinement, Windows UNC,
  long-path and reparse-point handling), #72 (Windows Explorer preview handler,
  authored in the Windows session), #73 (Windows docs refresh). #71 (design
  proposal) was closed after its open items were folded into #72.
- Branches left on the remote. All their content is merged (squashed) or closed;
  delete them when convenient, nothing needs rescuing:
  `claude/determined-hopper-6beqv7`, `claude/windows-preview-handler-design`,
  `claude/windows-docs-refresh`, `miyako-windows-preview-handler`,
  `claude/paged-column-rules-2bd431` (its change merged as #68).
- A local `main` that predates these merges needs `git pull`.

## Do first on the Mac

1. `git pull` on `main`, then `swift test`. The cloud session had no Swift
   toolchain, so #70 was only compiled and tested by hosted CI (Windows and Linux
   CLI jobs plus the `build` job, all green). Pay attention to anything touching
   `FormDependencies`, `LabelAnalyzer`, `CatalogAnalyzer`, `ByteSource` and the new
   `PathConfinementTests` (its Windows-only tests skip on macOS).
2. `scripts/build.sh --register`, then Space on a `.4DForm` inside a project, a
   `.4lbp` that resolves its table form, and a `.4DCatalog` with a
   `catalog_editor.json`. These are the macOS paths whose path handling now goes
   through `PathConfinement.canonicalURL`/`contains`. Expected behavior is
   unchanged; on macOS `canonicalURL` is still
   `standardizedFileURL.resolvingSymlinksInPath()`. Confirm a symbolic link that
   escapes the project still produces the "escapes" notice.
3. **Not changed, still textual:** `Sources/FourDProjectAccess/ProjectAccessStore.swift`
   (`contains` uses `path == root || path.hasPrefix(root + "/")`) and the `hasPrefix("/")`
   checks in `ProjectPreviewExchange` and `ProjectPreviewServiceProtocol`. They are
   macOS-only and sit behind bookmark checks, so #70 left them alone. Decide
   whether to move `ProjectAccessStore.contains` onto `PathConfinement` for
   consistency (a small, testable change).
4. Read the Japanese sentence added to `README.ja.md` about the Windows preview
   handler; it is a machine translation by the cloud session.

## Write Pro editor (`web-editor/`)

- Phases 1 to 10.9.7 are merged on `main`; 10.10 (further layout parity) and 11
  (release readiness) are **Proposed**, not approved.
- **Stale text to fix first:** `web-editor/README.md` still says `main` is at
  `4ea912a` / #67 and that 10.9.7 (rules between columns) is "in progress, awaiting
  review". #68 (M4d) is already merged, so the snapshot paragraph, the "In
  progress" wording and the 10.9.7 row need updating. Also check whether the Pages
  deployment matches `main`: **not verified**.
- Run locally: `cd web-editor && npm ci && npm test`, and `npm run test:browser`
  (needs Playwright Chromium).
- Any further layout parity (10.10) needs the native oracle: author shapes in
  full 4D and compare native PDF output. That needs 4D on the Mac:
  `bash scripts/check-web-editor-native.sh /absolute/path/to/new-evidence-directory`
  (defaults to `/Applications/4D 21.2/4D.app/Contents/MacOS/4D`; set `FOURD` to
  override; tool4d is not a substitute). The output directory must not exist.
- Phase 11 can be started without 4D: accessibility, mobile usability, a
  compatibility matrix, export/recovery reliability, and written release criteria.
  Agree the criteria before building anything.

## Windows work still open (needs Windows or 4D captures)

From `docs/WINDOWS-HANDOVER.md` and the "Open items and follow-ups" section of
`docs/WINDOWS-PREVIEW-HANDLER.md`:

- Manual Explorer preview-pane checks on Windows 10 and 11 (activation in
  `prevhost.exe` is verified; the pane UI is not automated), helper latency,
  signing/SmartScreen, an ARM64 build, and the dark-mode decision.
- Handover items 2 and 3: more native form references and per-control pixel
  scores, other display scales, Windows 10 font metrics.
- CI pins the Windows build to `windows-2022` because `windows-latest` (Visual
  Studio 18) fails with STL1000 against Swift 6.4.2's Clang 21. Remove the pin
  when a newer Swift toolchain is used.
- Hosted Windows CI reported 304 tests, 0 failures, 4 skipped (two need
  macOS-measured font metrics, two need `FOURD_SAMPLES`). A separate local Windows
  run reported 10 skips whose detail is unknown.

## Tooling notes

- `miyako/skills` (4D agent skills) was cloned read-only in the cloud session; it
  targets 4D projects, not this Swift/web codebase. Relevant if form fixtures are
  touched: `4dform`, `4dcss`, and `4dtools` (provisions `fourdform` for PNG
  previews). It is not vendored as a submodule here.
- Cloud sessions here cannot push to `main` or force-push; work lands through
  PRs, and merges were squash merges pinned to the checked head SHA.

## Status after the macOS session (2026-11-26)

- Verified on macOS with full Xcode (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; Command Line Tools alone lack XCTest): 367 tests, 9 skipped, 0 failures. Web editor: 451 unit and 213 production-browser tests pass (browser printing specs need Poppler, `brew install poppler`).
- `ProjectAccessStore.contains` was left unchanged (optional item 3 above; not requested).
- `web-editor/README.md` status text corrected to #68. Still **not done**: the #68 successor baseline comparison (`reproduce-paged.mjs` requires the #67 evidence), the full-4D native gate (`FOURD` must point at an installed full 4D, e.g. `/Applications/4D 21.2 LTS (100694)/4D.app/Contents/MacOS/4D`), M5a-M5c audits, and manual `build.sh --register` Quick Look checks.
