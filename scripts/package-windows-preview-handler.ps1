<#
.SYNOPSIS
Create a Windows x64 CLI package with the optional Explorer preview handler.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9]+[.][0-9]+[.][0-9]+(?:-[A-Za-z0-9-]+(?:[.][A-Za-z0-9-]+)*)?(?:[+][A-Za-z0-9-]+(?:[.][A-Za-z0-9-]+)*)?$')]
    [string]$Version,
    [string]$OutputDirectory = 'dist',
    [string]$CliPackageDirectory,
    [string]$HandlerBuildDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '.build\windows-preview-handler')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'The preview-handler package can only be created on Windows.' }

$output = [IO.Path]::GetFullPath($OutputDirectory)
$packageName = "fourdql-$Version-windows-x86_64-preview-handler"
$cliName = "fourdql-$Version-windows-x86_64"
if (-not $CliPackageDirectory) {
    $CliPackageDirectory = Join-Path $output $cliName
}
$CliPackageDirectory = (Resolve-Path -LiteralPath $CliPackageDirectory).Path
$HandlerBuildDirectory = (Resolve-Path -LiteralPath $HandlerBuildDirectory).Path
$support = Join-Path $PSScriptRoot 'package-cli-windows-support.ps1'
. $support
$null = Get-CliPeInfo (Join-Path $CliPackageDirectory 'fourdql.exe')
$null = Get-CliPeInfo (Join-Path $HandlerBuildDirectory 'FourDPreviewHandler.dll')
$null = Get-CliPeInfo (Join-Path $HandlerBuildDirectory 'WebView2Loader.dll')
$null = Get-CliPeInfo (Join-Path $HandlerBuildDirectory 'PreviewHandlerSelfTest.exe')
$destination = Join-Path $output $packageName
$archive = Join-Path $output "$packageName.zip"
$verification = Join-Path ([IO.Path]::GetTempPath()) "4dql-preview-package-$([guid]::NewGuid().ToString('N'))"
foreach ($required in @(
    (Join-Path $CliPackageDirectory 'fourdql.exe'),
    (Join-Path $HandlerBuildDirectory 'FourDPreviewHandler.dll'),
    (Join-Path $HandlerBuildDirectory 'WebView2Loader.dll'),
    (Join-Path $HandlerBuildDirectory 'PreviewHandlerSelfTest.exe'),
    (Join-Path $HandlerBuildDirectory 'sdk-1.0.4370.26\LICENSE.txt'),
    (Join-Path $HandlerBuildDirectory 'sdk-1.0.4370.26\NOTICE.txt')
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required package input is missing: $required"
    }
}
foreach ($path in @($destination, $archive, $verification)) {
    if (Test-Path -LiteralPath $path) {
        throw "Output already exists; remove it explicitly before packaging again: $path"
    }
}

$null = New-Item -ItemType Directory -Path $destination -Force
try {
    Get-ChildItem -LiteralPath $CliPackageDirectory -Force |
        Copy-Item -Destination $destination -Recurse
    foreach ($file in @('FourDPreviewHandler.dll', 'WebView2Loader.dll', 'PreviewHandlerSelfTest.exe')) {
        Copy-Item -LiteralPath (Join-Path $HandlerBuildDirectory $file) `
            -Destination (Join-Path $destination $file)
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows-preview-handler.ps1') `
        -Destination $destination
    $webViewNotices = Join-Path $destination 'ThirdParty\WebView2'
    $null = New-Item -ItemType Directory -Path $webViewNotices -Force
    Copy-Item -LiteralPath (Join-Path $HandlerBuildDirectory 'sdk-1.0.4370.26\LICENSE.txt') `
        -Destination $webViewNotices
    Copy-Item -LiteralPath (Join-Path $HandlerBuildDirectory 'sdk-1.0.4370.26\NOTICE.txt') `
        -Destination $webViewNotices

    Compress-Archive -LiteralPath $destination -DestinationPath $archive -CompressionLevel Optimal
    Expand-Archive -LiteralPath $archive -DestinationPath $verification
    $extracted = Join-Path $verification $packageName
    foreach ($file in @(
        'fourdql.exe', 'FourDPreviewHandler.dll', 'WebView2Loader.dll',
        'PreviewHandlerSelfTest.exe', 'windows-preview-handler.ps1',
        'ThirdParty\WebView2\LICENSE.txt', 'ThirdParty\WebView2\NOTICE.txt'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $extracted $file) -PathType Leaf)) {
            throw "Archive is missing required file: $file"
        }
    }
    $roundTripFiles = @{
        'fourdql.exe' = Join-Path $CliPackageDirectory 'fourdql.exe'
        'FourDPreviewHandler.dll' = Join-Path $HandlerBuildDirectory 'FourDPreviewHandler.dll'
        'WebView2Loader.dll' = Join-Path $HandlerBuildDirectory 'WebView2Loader.dll'
        'PreviewHandlerSelfTest.exe' = Join-Path $HandlerBuildDirectory 'PreviewHandlerSelfTest.exe'
    }
    foreach ($file in $roundTripFiles.Keys) {
        $sourceHash = (Get-FileHash -LiteralPath $roundTripFiles[$file] -Algorithm SHA256).Hash
        $archiveHash = (Get-FileHash -LiteralPath (Join-Path $extracted $file) -Algorithm SHA256).Hash
        if ($sourceHash -ine $archiveHash) {
            throw "Archive round-trip hash mismatch: $file"
        }
    }
    Write-Host "Packaged Windows preview handler: $archive"
} catch {
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    throw
} finally {
    if (Test-Path -LiteralPath $verification) { Remove-Item -LiteralPath $verification -Recurse -Force }
}
