<#
.SYNOPSIS
Package an already-built, unsigned Windows x86_64 fourdql CLI.
.EXAMPLE
swift build -c release --product fourdql
pwsh -NoProfile -File scripts/package-cli-windows.ps1 -Version 1.2.3
.NOTES
Requires PowerShell 7, Windows x64, and the Swift compiler used for the build.
Does not build, sign, install software, or search PATH for runtime DLLs.
Downloads public redistribution notices over HTTPS (fails closed on errors).
For offline packaging, supply -RuntimeNoticeDirectory with the filenames
listed in $noticeSources below. -SwiftSourceTag overrides the release source
tag for a non-release toolchain. -RuntimeDirectory adds explicit DLL roots.
Output: dist/fourdql-VERSION-windows-x86_64.zip and its unpacked directory.
The ZIP is extracted and its EXE tested with only Windows directories on PATH.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9]+[.][0-9]+[.][0-9]+(?:-[A-Za-z0-9-]+(?:[.][A-Za-z0-9-]+)*)?(?:[+][A-Za-z0-9-]+(?:[.][A-Za-z0-9-]+)*)?$')]
    [string]$Version,
    [string]$OutputDirectory = 'dist',
    [string]$BinaryPath,
    [string[]]$RuntimeDirectory = @(),
    [string]$RuntimeNoticeDirectory,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._+-]*$')]
    [string]$SwiftSourceTag
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64' -or
    -not [Environment]::Is64BitProcess) {
    throw 'Packaging requires Windows x64 and a 64-bit PowerShell 7 process.'
}
. (Join-Path $PSScriptRoot 'package-cli-windows-support.ps1')
$repo = Split-Path $PSScriptRoot -Parent

function Invoke-SwiftOutput {
    param([string]$Executable, [string[]]$Arguments)
    $result = & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
    return ($result -join "`n").Trim()
}

$swift = (Get-Command swift.exe -CommandType Application -ErrorAction Stop).Source
$swiftc = Join-Path (Split-Path $swift -Parent) 'swiftc.exe'
if (-not (Test-Path -LiteralPath $swiftc -PathType Leaf)) {
    throw "Cannot find swiftc.exe beside $swift"
}
$targetInfo = Invoke-SwiftOutput -Executable $swiftc -Arguments @('-print-target-info') | ConvertFrom-Json
if ($targetInfo.target.triple -notmatch '^x86_64-.*windows') {
    throw "Expected a Windows x86_64 Swift toolchain, got $($targetInfo.target.triple)"
}
$swiftVersionText = Invoke-SwiftOutput -Executable $swiftc -Arguments @('--version')
if ($swiftVersionText -notmatch 'Swift version ([0-9]+[.][0-9]+(?:[.][0-9]+)?)') {
    throw "Cannot determine Swift version from: $swiftVersionText"
}
$swiftVersion = $Matches[1]
if (-not $SwiftSourceTag) {
    if ($swiftVersionText -match 'DEVELOPMENT|SNAPSHOT') {
        throw 'Development toolchains require an explicit -SwiftSourceTag for redistribution notices.'
    }
    $SwiftSourceTag = "swift-$swiftVersion-RELEASE"
}
if (-not $BinaryPath) {
    Push-Location $repo
    try {
        $binDirectory = Invoke-SwiftOutput -Executable $swift -Arguments @('build', '-c', 'release', '--show-bin-path')
    } finally { Pop-Location }
    $BinaryPath = Join-Path $binDirectory 'fourdql.exe'
}
$BinaryPath = (Resolve-Path -LiteralPath $BinaryPath).Path
if ([IO.Path]::GetFileName($BinaryPath) -ine 'fourdql.exe') {
    throw '-BinaryPath must name the built fourdql.exe.'
}
$null = Get-CliPeInfo $BinaryPath

$search = [Collections.Generic.List[string]]::new()
function Add-SearchDirectory([string]$Path) {
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Container)) {
        $full = (Resolve-Path -LiteralPath $Path).Path
        if (-not $search.Contains($full)) { $search.Add($full) }
    }
}
Add-SearchDirectory (Split-Path $BinaryPath -Parent)
foreach ($directory in $RuntimeDirectory) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Explicit runtime directory does not exist: $directory"
    }
    Add-SearchDirectory $directory
}
foreach ($directory in $targetInfo.paths.runtimeLibraryPaths) {
    Add-SearchDirectory $directory
    Add-SearchDirectory (Join-Path $directory 'x86_64')
}
# The official Windows installer separates Toolchains, Platforms and Runtimes
# under a common Developer root. Discover it from the actual compiler/SDK,
# never from the runner's inherited PATH or an unrelated installed Swift.
$anchors = @((Split-Path $swiftc -Parent), $env:SDKROOT, $targetInfo.paths.runtimeResourcePath)
foreach ($anchor in $anchors) {
    if (-not $anchor) { continue }
    $directory = [IO.DirectoryInfo]::new($anchor)
    while ($null -ne $directory) {
        Add-SearchDirectory (Join-Path $directory.FullName "Runtimes/$swiftVersion/usr/bin")
        $directory = $directory.Parent
    }
}
if ($env:SDKROOT) {
    foreach ($relative in @('usr/bin', 'usr/bin64', 'usr/lib/swift/windows', 'usr/lib/swift/windows/x86_64')) {
        Add-SearchDirectory (Join-Path $env:SDKROOT $relative)
    }
}
Add-SearchDirectory (Split-Path $swiftc -Parent)
# Newer runtime MSIs can place DLLs in per-assembly SxS subdirectories.
foreach ($directory in @($search.ToArray())) {
    $sxs = Join-Path $directory 'SxS'
    if (Test-Path -LiteralPath $sxs -PathType Container) {
        Add-SearchDirectory $sxs
        foreach ($child in Get-ChildItem -LiteralPath $sxs -Directory) {
            Add-SearchDirectory $child.FullName
        }
    }
    # Per-machine Swift runtime MSIs may install their Win32 assemblies directly
    # into WinSxS. Limit discovery to the active Swift release and architecture;
    # never recursively scan Windows or treat these assemblies as OS DLLs.
    $winSxs = Join-Path $env:SystemRoot 'WinSxS'
    if (Test-Path -LiteralPath $winSxs -PathType Container) {
        foreach ($assembly in Get-ChildItem -LiteralPath $winSxs -Directory -Filter "amd64_*_$swiftVersion.*" |
            Sort-Object Name -Descending) {
            $swiftDlls = @(Get-ChildItem -LiteralPath $assembly.FullName -File -Filter '*.dll' |
                Where-Object { $_.Name -match '^(swift|Foundation|_Foundation|BlocksRuntime|dispatch)' })
            if ($swiftDlls.Count -gt 0) { Add-SearchDirectory $assembly.FullName }
        }
    }
}

$vsRoot = $null
$redistRoots = [Collections.Generic.List[string]]::new()
if ($env:VCToolsRedistDir) { $redistRoots.Add($env:VCToolsRedistDir) }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
    $vsRoot = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) -join ''
    if ($LASTEXITCODE -ne 0) { throw "vswhere failed with exit code $LASTEXITCODE" }
    if ($vsRoot) {
        $redistBase = Join-Path $vsRoot 'VC/Redist/MSVC'
        if (Test-Path -LiteralPath $redistBase -PathType Container) {
            foreach ($child in Get-ChildItem -LiteralPath $redistBase -Directory | Sort-Object Name -Descending) {
                $redistRoots.Add($child.FullName)
            }
        }
    }
}
foreach ($root in $redistRoots) {
    $x64 = Join-Path $root 'x64'
    if (Test-Path -LiteralPath $x64 -PathType Container) {
        foreach ($crt in Get-ChildItem -LiteralPath $x64 -Directory -Filter 'Microsoft.VC*.CRT') {
            Add-SearchDirectory $crt.FullName
        }
    }
}

$output = [IO.Path]::GetFullPath($OutputDirectory)
$name = "fourdql-$Version-windows-x86_64"
$package = Join-Path $output $name
$archive = Join-Path $output "$name.zip"
$verification = Join-Path $output "$name.verify"
foreach ($path in @($package, $archive, $verification)) {
    if (Test-Path -LiteralPath $path) {
        throw "Output already exists; remove it explicitly before packaging again: $path"
    }
}
$null = New-Item -ItemType Directory -Path $package -Force
$systemDirectory = Join-Path $env:SystemRoot 'System32'
try {
    $systemCache = @{}
    $isSystem = {
        param($dll)
        if (-not $systemCache.ContainsKey($dll)) {
            $systemCache[$dll] = Test-CliSystemDll $dll $systemDirectory
        }
        return $systemCache[$dll]
    }
    $records = @(Copy-CliDependencyClosure -BinaryPath $BinaryPath -Destination $package `
        -SearchDirectories $search.ToArray() -IsSystemDll $isSystem)
    Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination $package
    Copy-Item -LiteralPath (Join-Path $repo 'ThirdParty/Selawik/OFL.txt') `
        -Destination (Join-Path $package 'Selawik-OFL.txt')
    Copy-Item -LiteralPath (Join-Path $repo 'docs') -Destination $package -Recurse
    $notices = Join-Path $package 'ThirdParty/Runtime'
    $null = New-Item -ItemType Directory -Path $notices -Force
    # Swift notices follow the installed release tag. The other URLs are fixed
    # license-text snapshots, not claims about the SDK's dependency versions.
    # Include notices for libraries statically embedded in Foundation as well
    # as for DLLs: PE imports alone cannot identify static third-party code.
    $noticeSources = [ordered]@{
        'Swift-LICENSE.txt' = "https://raw.githubusercontent.com/swiftlang/swift/$SwiftSourceTag/LICENSE.txt"
        'Foundation-LICENSE.txt' = "https://raw.githubusercontent.com/swiftlang/swift-foundation/$SwiftSourceTag/LICENSE.md"
        'Foundation-NOTICE.txt' = "https://raw.githubusercontent.com/swiftlang/swift-foundation/$SwiftSourceTag/NOTICE.txt"
        'CorelibsFoundation-LICENSE.txt' = "https://raw.githubusercontent.com/swiftlang/swift-corelibs-foundation/$SwiftSourceTag/LICENSE"
        'Dispatch-LICENSE.txt' = "https://raw.githubusercontent.com/swiftlang/swift-corelibs-libdispatch/$SwiftSourceTag/LICENSE"
        'FoundationICU-LICENSE.txt' = "https://raw.githubusercontent.com/swiftlang/swift-foundation-icu/$SwiftSourceTag/LICENSE.md"
        'ICU-LICENSE.txt' = 'https://raw.githubusercontent.com/unicode-org/icu/release-76-1/LICENSE'
        'BlocksRuntime-LICENSE.txt' = "https://raw.githubusercontent.com/swiftlang/swift-corelibs-libdispatch/$SwiftSourceTag/LICENSE"
        'Curl-LICENSE.txt' = 'https://raw.githubusercontent.com/curl/curl/curl-8_11_1/COPYING'
        'Libxml2-LICENSE.txt' = 'https://raw.githubusercontent.com/GNOME/libxml2/v2.13.5/Copyright'
        'Zlib-LICENSE.txt' = 'https://raw.githubusercontent.com/madler/zlib/v1.3.1/LICENSE'
        'Brotli-LICENSE.txt' = 'https://raw.githubusercontent.com/google/brotli/v1.1.0/LICENSE'
    }
    if (@($records.File | Where-Object { $_ -match '^(msvcp|msvcr|vcruntime|concrt|vcomp)\d' }).Count -gt 0) {
        $noticeSources['MSVC-REDISTRIBUTION.docx'] = 'https://visualstudio.microsoft.com/wp-content/uploads/2021/09/Visual-C-Runtime-2015-2022-License-1.docx'
    }
    foreach ($entry in $noticeSources.GetEnumerator()) {
        $destination = Join-Path $notices $entry.Key
        if ($RuntimeNoticeDirectory) {
            Copy-Item -LiteralPath (Join-Path $RuntimeNoticeDirectory $entry.Key) -Destination $destination
        } else {
            Invoke-WebRequest -Uri $entry.Value -OutFile $destination -MaximumRetryCount 3 -UserAgent 'Mozilla/5.0'
        }
        if ((Get-Item -LiteralPath $destination).Length -lt 100) {
            throw "Empty or invalid redistribution notice: $($entry.Key)"
        }
    }
    $noticeSources | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $notices 'SOURCES.json') -Encoding utf8
    [ordered]@{
        Version = $Version
        Platform = 'windows-x86_64'
        Swift = $swiftVersionText
        SwiftSourceTag = $SwiftSourceTag
        Signed = $false
        Files = $records
        WindowsImports = @($systemCache.Keys | Where-Object { $systemCache[$_] } | Sort-Object)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $package 'runtime-manifest.json') -Encoding utf8
    @"
fourdql $Version for Windows x86_64

Extract the entire folder and keep fourdql.exe beside its DLLs.
Run .\fourdql.exe --help in PowerShell; this is not a GUI application.
No Swift SDK installation is needed. This build is unsigned (no Authenticode).
Windows 10/11 x64 system components are not included.

See docs/CLI.md for command syntax and format references. macOS signing and
notarization instructions do not apply to this unsigned Windows package.
Project, font and runtime license/redistribution notices are included.
runtime-manifest.json records the packaged PE files, hashes and imports.
"@ | Set-Content -LiteralPath (Join-Path $package 'WINDOWS-USAGE.txt') -Encoding utf8

    Compress-Archive -LiteralPath $package -DestinationPath $archive -CompressionLevel Optimal
    Expand-Archive -LiteralPath $archive -DestinationPath $verification
    $extracted = Join-Path $verification $name
    foreach ($record in $records) {
        $file = Join-Path $extracted $record.File
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $record.SHA256) {
            throw "Archive round-trip hash mismatch: $($record.File)"
        }
        foreach ($dependency in (Get-CliPeInfo $file).Imports) {
            if (-not (& $isSystem $dependency) -and
                -not (Test-Path -LiteralPath (Join-Path $extracted $dependency) -PathType Leaf)) {
                throw "Archive is missing dependency $dependency required by $($record.File)"
            }
        }
    }
    $oldPath = $env:PATH
    $oldSdkRoot = $env:SDKROOT
    $oldSwiftRoot = $env:SWIFT_ROOT
    Push-Location $verification
    try {
        $env:PATH = "$systemDirectory;$env:SystemRoot"
        $env:SDKROOT = $null
        $env:SWIFT_ROOT = $null
        $help = & (Join-Path $extracted 'fourdql.exe') --help 2>&1
        if ($LASTEXITCODE -ne 0 -or ($help -join "`n") -notmatch 'fourdql') {
            throw "Packaged EXE clean-PATH --help probe failed (exit $LASTEXITCODE): $($help -join "`n")"
        }
    } finally {
        $env:PATH = $oldPath
        $env:SDKROOT = $oldSdkRoot
        $env:SWIFT_ROOT = $oldSwiftRoot
        Pop-Location
    }
    Write-Host "Packaged and verified: $archive"
    Write-Host "Unpacked CLI: $(Join-Path $package 'fourdql.exe')"
} catch {
    # Never leave an uploadable asset after a failed dependency/license/probe check.
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Recurse -Force }
    throw
} finally {
    if (Test-Path -LiteralPath $verification) { Remove-Item -LiteralPath $verification -Recurse -Force }
}
