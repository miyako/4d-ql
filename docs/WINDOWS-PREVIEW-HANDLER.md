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
