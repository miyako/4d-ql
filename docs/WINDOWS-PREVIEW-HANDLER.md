# Windows Explorer preview handler

The optional x64 Explorer preview handler uses the existing `fourdql.exe --html`
renderer and WebView2 Runtime. It runs in the Windows Preview Host
(`prevhost.exe`) and is distributed as a separate ZIP alongside the standalone
CLI package. The standalone CLI remains usable without the handler or WebView2.

## Install and remove

Extract the entire `fourdql-VERSION-windows-x86_64-preview-handler` directory
and keep all files together. The machine needs the Microsoft Edge WebView2
Evergreen Runtime. Open PowerShell 7 in that directory and register the handler
for the current user:

```powershell
.\windows-preview-handler.ps1 -Action Register
```

No administrator access is required. Registration adds only per-user COM,
PreviewHandlers, and `SystemFileAssociations` entries for the file types
supported by `fourdql`. It does not change file ProgIDs, default applications,
or machine-wide settings. Existing ProgID-specific preview handlers remain
authoritative; this handler is registered as a fallback.

To remove the registration before deleting or moving the package:

```powershell
.\windows-preview-handler.ps1 -Action Unregister
```

The preview process runs at the integrity level selected by Windows and stores
WebView2 data and temporary HTML under the current user's `LocalAppDataLow`.
The helper is bounded by a five-second timeout, 32 MiB output cap, and 512 MiB
process-memory limit. WebView2 scripting and navigation away from the generated
local preview are disabled.

## Build and verification

On 64-bit Windows with PowerShell 7, Visual Studio's C++ x64 tools, and a Swift
Windows x64 toolchain:

```powershell
swift build -c release --product fourdql
$bin = (swift build -c release --show-bin-path).Trim()
.\scripts\build-windows-preview-handler.ps1 `
    -CliPath (Join-Path $bin 'fourdql.exe') -RunSelfTest
```

The build downloads the pinned WebView2 SDK NuGet package and verifies its
SHA-256 before compilation. The self-test exercises both direct COM activation
and activation through `prevhost.exe`, including WebView2 navigation.

The release package is assembled from a previously verified CLI package and
the handler build:

```powershell
.\scripts\package-cli-windows.ps1 -Version 1.2.3
.\scripts\package-windows-preview-handler.ps1 -Version 1.2.3
```

The resulting archive includes the CLI's runtime DLLs, the handler and loader,
the registration script, the self-test executable, and WebView2 SDK notices.
The automated host test does not automate Explorer's UI or preview-pane
selection; it verifies the registered COM class activates in `prevhost.exe`.

## Open items and follow-ups

Carried over from the earlier design proposal. None of these is implemented or
verified unless stated.

- **Explorer UI.** Activation is verified in `prevhost.exe`, not through the
  Explorer preview pane. Check manually on Windows 10 and 11, at 100/150/200 %
  display scale, in light and dark mode, while resizing the pane, arrow-keying
  quickly through many files, and on a file on a network share. Record versions
  in this document.
- **x64 CLI self-test.** The first local validation used an ARM64 CLI helper, so
  the x64 self-test runs only in the hosted Windows job. Review that job's log on
  each release.
- **Leaks and robustness.** Watch `prevhost.exe` memory and handles over a few
  hundred selections, and confirm that rapid selection changes cancel the helper
  without blocking the UI thread.
- **Latency.** Measure process start plus Swift runtime load for the `fourdql.exe`
  helper while arrow-keying. If it is too slow, cost a long-lived helper or an
  exported C ABI loaded by a helper process.
- **Hosting model.** Forms, labels and catalogs read sibling files, so the handler
  needs file-based initialization; single-file types could use a more isolated
  stream-based host. Confinement relies on `PathConfinement` and the helper's
  limits.
- **Confinement through the handler.** Exercise forms whose stylesheet or `$ref`
  escapes the project through `..`, a junction and a symbolic link, and paths with
  spaces, non-ASCII characters, UNC and over 260 characters.
- **Associations.** Check what 4D itself registers for these extensions on a
  machine with 4D installed, and that a `SystemFileAssociations` fallback never
  displaces an existing preview handler or default app.
- **Signing and distribution.** The package is unsigned. Test whether SmartScreen
  or Smart App Control blocks the unsigned handler DLL on current Windows 11.
  Later: MSIX or WiX, code signing, and an ARM64 build.
- **Dark mode.** Form previews select a theme explicitly (see the handover's
  Windows HTML contract). Decide whether the shell's dark/light state should also
  set WebView2's preferred color scheme for the other report types.
