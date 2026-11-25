# Windows Explorer preview handler: design and handover

Status: **proposal, nothing implemented or built.** This document hands handover
item 1 ("Explorer preview-handler integration and Windows packaging", in
[WINDOWS-HANDOVER.md](WINDOWS-HANDOVER.md)) to a session that has a Windows
machine. It was written without one, so every statement about Windows shell
behavior is marked **verify** and must be confirmed before it is relied on.
Statements about this repository were checked against `main`.

## Goal

Select a 4D file in File Explorer with the preview pane open (Alt+P) and see the
same static preview the macOS Quick Look extension shows, for the same file
types, without 4D installed.

Non-goals for the first increment: thumbnails, property handlers, an
installer-grade UI, signing and Microsoft Store distribution, ARM64 builds,
editing, and any form of formula or method execution.

## What exists to build on (verified in this repo)

| Piece | Where | Relevance |
|---|---|---|
| File to HTML pipeline | `FourDRender.PreviewPipeline.html(for:contentType:options:)` | The one entry point shared by Quick Look and the CLI. Returns a complete, script-free HTML document. |
| CLI | `fourdql --html <file>`, `--json`, `--thorough`, `--content-types` | Prints the HTML to stdout. Windows x86-64 ZIP built by CI (`cli-build.yml`, `scripts/package-cli-windows.ps1`) with its runtime DLLs. |
| Windows form rendering | `FormRenderer`, `FormPlatform.windows`, `CFourDWindows` (WIC, DirectWrite) | Forms preview with Windows Classic and Fluent UI appearances on Windows. |
| HTML contract | `HTMLRenderer` | Self-contained: no scripts, CSP `default-src 'none'; img-src data: 'self'; style-src 'unsafe-inline'` (plus `font-src data:` only when the embedded Selawik substitute is used), `color-scheme: light dark`. |
| Limits | `AnalysisOptions.preview`: 1.5 s analysis budget, bounded records; analyzers cap sizes (XML 4 MiB, dependencies 4 MiB each / 16 MiB total / 64 files, methods 256 KiB) | A preview is bounded in time and memory by design. |
| Path confinement | `PathConfinement` (PR #70) | Dependency reads (stylesheets, pictures, `$ref` JSON, XLIFF, label forms, catalog layout) stay inside the project or form folder: UNC, `\\?\`, junction and case-aware. **Not yet run on Windows.** |
| File types | analyzers' `filenameExtensions` | `.4dd` `.data` `.4db` `.4dcatalog` `.4dsettings` `.4dlink` `.4dpreferences` `.4dproject` `.4si` `.4df` `.4st` `.4qr` `.4lbp` `.4wp` `.4vp` `.4dm` `.4dform`. `fourdql --content-types` prints the authoritative list. |

Not present on Windows and not to be assumed: the macOS app, the Quick Look
extension, `FourDProjectAccess` and its XPC service and security-scoped
bookmarks (all declared only under `#if os(macOS)` in `Package.swift`).

## Prerequisite: make the Windows baseline trustworthy

Do these first; a handler built on an unverified base will be hard to debug.

1. Run `swift test` on Windows and fix failures. In particular run
   `swift test --filter PathConfinementTests`: the Windows file-system tests
   (junction escape, symbolic link, 8.3 names, 300+ character paths, UNC through
   `\\localhost\C$`) have never executed. A confinement bug here is a security
   bug in the handler, because a preview handler reads files an attacker may
   have crafted.
2. CI currently pins the Windows CLI build to `windows-2022` because
   `windows-latest` (Visual Studio 18) fails with `STL1000` against Swift 6.4.2's
   Clang 21. Check whether a newer Swift toolchain removes the pin.
3. Confirm `fourdql.exe --html` output on Windows for one file of every family,
   including a `.4DForm` inside a `Project/Sources/...` tree.

## Architecture

### Recommended: thin native handler plus the out-of-process CLI

```
Explorer ──> prevhost.exe ──loads──> FourDPreviewHandler.dll   (native C++, no Swift)
                                         │  IInitializeWith…  → file path
                                         │  IPreviewHandler   → owns a child window
                                         ├─ spawns  fourdql.exe --html <path>   (job object, timeout, output cap)
                                         └─ hosts   WebView2 in the preview rectangle, shows the HTML
```

Why this shape (reasoning, not measured):

- **Isolation.** All parsing of untrusted binary and XML happens in a separate
  process under a job object with a wall-clock limit and a memory limit. A parser
  crash or runaway cannot take down `prevhost.exe`, which is shared by other
  previewers.
- **No Swift runtime in the shell process.** The handler DLL stays small and
  native. Loading a Swift toolchain's runtime into `prevhost.exe` risks DLL
  conflicts and a large attack surface. **Verify** whether a Swift-built COM DLL
  is workable before dismissing it; it would remove the process hop.
- **Reuse.** The CLI already is the pipeline, already ships for Windows with its
  runtime DLLs, and is already tested by CI.
- **Do not use managed code in the handler.** Microsoft has long advised against
  managed preview handlers loaded into `prevhost.exe` (runtime version conflicts
  between handlers in one process). **Verify** current guidance for .NET before
  choosing C# at all.

Alternative worth costing if the CLI hop is too slow: a C ABI exported from a
Swift DLL (`fdw_preview_html(path, options, out_utf8, out_len)`), loaded by a
helper process rather than by `prevhost.exe`.

### Interfaces

- Implement `IPreviewHandler`, `IObjectWithSite`, `IOleWindow`,
  `IPreviewHandlerVisuals` (background and text color, font) and
  `IInitializeWithFile`.
- **Decision needed: `IInitializeWithFile` vs `IInitializeWithStream`.**
  Stream-based handlers can run in a low-integrity, more isolated host, but forms,
  labels and catalogs need sibling files (`styleSheets.css`, `Resources/`,
  `TableForms/`), which a stream cannot provide. Recommended: file-based, set
  `DisableLowILProcessIsolation` so the handler is not forced to a low-integrity
  host, and rely on `PathConfinement` plus the job-object limits for safety.
  Single-file types (`.4dd`, `.4st`, `.4qr`, `.4wp`, `.4vp`, `.4dm`, ...) could
  register a stream-based handler. **Verify** which of these two hosting models
  the 4D types need, by testing a form that references a stylesheet.
- Registration for each extension (HKCR or per-user HKCU; **verify** which works
  without elevation on Windows 11): the `ShellEx\{8895b1c6-b41f-4c1c-a562-0d564250836f}`
  value pointing to the handler CLSID, the CLSID's `AppID`
  `{6d2b5079-2f0b-48dd-ab7f-97cec514d30b}` (the 64-bit `prevhost.exe` surrogate),
  and an entry under `PreviewHandlers`. Also register `PerceivedType`/`Content Type`
  as appropriate and a friendly name.
- Raise `SHChangeNotify(SHCNE_ASSOCCHANGED, ...)` after (un)registration.

### Showing the HTML

- Host **WebView2** in the child window. Prefer the Evergreen runtime already
  present on Windows 11; check for it and show a plain-text fallback with a
  download hint otherwise.
- `NavigateToString` has a 2 MB limit (**verify** current value). Previews with
  embedded images and form SVG exceed that. Write the HTML to a private temp file
  and navigate to it, or serve it through
  `SetVirtualHostNameToFolderMapping`. Delete it when the preview is destroyed.
- The user data folder must be a writable per-user location
  (`%LOCALAPPDATA%\4DQuickLook\WebView2`), not the handler's directory.
  **Verify** that it initializes inside `prevhost.exe` at the handler's integrity
  level. This is the highest-risk unknown; prove it with a hello-world handler
  before any other work.
- Disable everything the preview does not need: scripts (`IsScriptEnabled=false`;
  the generated HTML needs none), `AreDefaultContextMenusEnabled`, dev tools,
  status bar, autofill, downloads, and block all navigation except the initial
  document. The generated CSP already forbids network access.
- Appearance: the HTML follows `prefers-color-scheme`. Pass the shell's dark/light
  state (`IPreviewHandlerVisuals`, or the app-mode registry value) to
  `CoreWebView2Profile.PreferredColorScheme`. Form previews on Windows select a
  theme explicitly (see the handover's Windows HTML contract), not from the
  browser scheme.

### Process, limits and failure handling

| Concern | Proposal |
|---|---|
| Time | Kill `fourdql.exe` after about 5 s (the analysis budget is 1.5 s; project dependency reads and rendering add more). Show a "preview timed out" page. |
| Output | Cap stdout at, say, 32 MiB; kill and show an error beyond it. |
| Memory | Job-object memory limit and `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`. |
| Errors | `fourdql` exits `0` even when text/HTML analysis fails and writes an error report to stdout (documented in `docs/CLI.md`); the page is shown as is. Handle only spawn, timeout, size and crash failures in the handler. |
| Selection changes | Explorer destroys and recreates the handler quickly. `Unload` must cancel the child process and release WebView2 without blocking the UI thread; run the spawn on a worker thread and marshal back. |
| Encoding | Read stdout as UTF-8 bytes and write them unchanged; do not pass through the console code page. |
| Path spelling | Pass the path from `IInitializeWithFile` unchanged. It can be a UNC or `\\?\` path, which is why `ByteSource` and `PathConfinement` were made to accept them. Use the wide-character process APIs and avoid a shell. |
| Large files | `.4dd` previews read only header blocks; a 220 MB data file previews in about 30 ms on macOS. Re-measure on Windows over a network share. |

### Authorization model (differs from macOS)

macOS needs user-granted, bookmark-backed folder access because the Quick Look
extension is sandboxed. Explorer handlers run as the user, so the first increment
needs **no** authorization UI: the handler can read what the user can read, and
confinement is enforced in the analyzers. Revisit only if the handler is moved to
a low-integrity host (the stream option above), in which case sibling-file access
for forms would need a broker.

## Packaging

1. Build `FourDPreviewHandler.dll` (CMake or MSBuild, x64) and a small
   `register.ps1` / `unregister.ps1` pair using `regsvr32` or direct registry
   writes. Per-user registration is preferred; **verify** that it works for
   previews on Windows 10 and 11.
2. Ship in the existing Windows ZIP, or as a second ZIP: `fourdql.exe` with its
   runtime DLLs, the handler DLL, the registration scripts and notices. The
   handler locates `fourdql.exe` next to itself.
3. Later: MSIX or WiX installer, code signing (handlers from unsigned DLLs may be
   blocked by SmartScreen or policy), and an ARM64 variant. Extend the release
   verification scripts (`scripts/verify-release.py`,
   `scripts/test-package-cli-windows.ps1`) to cover the new files.
4. Extend `scripts/package-cli-windows.ps1`'s smoke test (it extracts the ZIP and
   runs the EXE with only Windows directories on `PATH`) to run the handler's
   self-test mode (below) the same way.

## Test plan

Automated, on a Windows CI runner (pin the runner as in `cli-build.yml`):

- A self-test executable that instantiates the handler's COM class directly,
  initializes it with a fixture path, calls `SetWindow`/`DoPreview`, waits for
  `NavigationCompleted`, and asserts on the page title or a DOM probe. This avoids
  driving Explorer.
- Failure paths: missing `fourdql.exe`, timeout, oversized output, a corrupt
  fixture, a path with spaces, non-ASCII characters, a UNC path and a path over
  260 characters.
- Confinement through the handler: a `.4DForm` whose stylesheet or `$ref` points
  outside the project through `..`, a junction and a symbolic link must show the
  existing "escapes the preview's project/form folder" notice, not the content.
- Reuse the fixtures under `Tests/FourDFileKitTests/Fixtures/`.

Manual, on Windows 10 and 11 (record versions and display scales in the doc):

- Preview pane for each extension, light and dark mode, 100/150/200 % scale,
  resizing the pane, fast arrow-key selection through many files, a file on a
  network share, a locked file, and uninstall leaving no registry residue.
- Memory and handle leaks over a few hundred selections (Task Manager,
  `prevhost.exe`).

## Open questions for the Windows session

1. Does WebView2 initialize and render inside `prevhost.exe` for a per-user
   handler, and at which integrity level? (Spike first.)
2. File-based or stream-based initialization per type; is
   `DisableLowILProcessIsolation` required and acceptable?
3. Is per-user (HKCU) registration honored by Explorer's preview pane on
   Windows 10 and 11 without elevation?
4. Is spawning `fourdql.exe` fast enough (process start plus Swift runtime load)
   for arrow-key browsing? If not, cost the DLL-export alternative or a
   long-lived helper process.
5. Do the 4D Classic and Fluent form themes need the shell's dark/light state to
   pick the initial theme, or is the form's own `fluentUI` setting enough?
6. Does Windows ship, or let users install, anything that already associates
   these extensions (for example 4D itself registering `.4DProject` or `.4DForm`)?
   Registration must not break an existing preview handler or default app.
7. Signing: which certificate, and does SmartScreen or Smart App Control block an
   unsigned handler DLL on current Windows 11?
8. Is there a role for PowerToys Peek or other third-party hosts as an alternative
   to a native handler? Treat as research only.

## Suggested order of work

1. Windows baseline: `swift test`, `PathConfinementTests`, `fourdql --html` per type.
2. Hello-world C++ preview handler with WebView2 showing a static page, registered
   per user. Settle questions 1 to 3.
3. Spawn `fourdql.exe` with job-object limits and show real previews; add the
   self-test executable and CI.
4. Theming, resizing, error pages, selection-change robustness.
5. Packaging, registration scripts, release verification, README and CLI docs
   (this repository documents "no Explorer preview handler" in several places;
   update them in the same change that ships one).

## Out of scope here, tracked elsewhere

Handover items 2 and 3 (more native Windows references, other display scales,
Windows 10 font metrics) concern form rendering fidelity, not the handler.
