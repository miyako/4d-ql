<#
.SYNOPSIS
Build the x64 Windows Explorer preview handler and its native self-tests.
.EXAMPLE
pwsh -NoProfile -File scripts/build-windows-preview-handler.ps1 -CliPath .build\x86_64-unknown-windows-msvc\debug\fourdql.exe
.NOTES
Requires PowerShell 7, Visual Studio C++ x64 tools, Windows x64, and the WebView2
Runtime. The pinned WebView2 SDK package is downloaded over HTTPS if not cached.
Use -RunSelfTest to exercise WebView2 and COM activation through prevhost.exe.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '.build\windows-preview-handler'),
    [string]$CliPath,
    [string]$WebView2PackagePath,
    [switch]$RunSelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or -not [Environment]::Is64BitProcess) {
    throw 'Building the preview handler requires 64-bit PowerShell on Windows.'
}

$version = '1.0.4370.26'
$packageHash = '1C0DACAC84B70109B3FD42F90C53A0BA942ABC3A87590D7A4E0CCD86E4A06CF4'
$repository = Split-Path $PSScriptRoot -Parent
$output = [IO.Path]::GetFullPath($OutputDirectory)
$packageCache = Join-Path $env:LOCALAPPDATA "4DQuickLook\WebView2SDK\Microsoft.Web.WebView2.$version.nupkg"
if (-not $WebView2PackagePath) {
    if (-not (Test-Path -LiteralPath $packageCache -PathType Leaf)) {
        $null = New-Item -ItemType Directory -Path (Split-Path $packageCache -Parent) -Force
        $download = "$packageCache.$PID.tmp"
        try {
            Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$version" `
                -OutFile $download -MaximumRetryCount 3
            if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ine $packageHash) {
                throw 'Downloaded WebView2 SDK package checksum mismatch.'
            }
            Move-Item -LiteralPath $download -Destination $packageCache
        } finally {
            if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
        }
    }
    $WebView2PackagePath = $packageCache
}
$WebView2PackagePath = (Resolve-Path -LiteralPath $WebView2PackagePath).Path
if ((Get-FileHash -LiteralPath $WebView2PackagePath -Algorithm SHA256).Hash -ine $packageHash) {
    throw "WebView2 SDK package checksum mismatch: $WebView2PackagePath"
}

$sdkRoot = Join-Path $output "sdk-$version"
$null = New-Item -ItemType Directory -Path $sdkRoot -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($WebView2PackagePath, $sdkRoot, $true)
$includeDirectory = Join-Path $sdkRoot 'build\native\include'
$nativeDirectory = Join-Path $sdkRoot 'build\native\x64'
foreach ($required in @(
    (Join-Path $includeDirectory 'WebView2.h'),
    (Join-Path $nativeDirectory 'WebView2Loader.dll.lib'),
    (Join-Path $nativeDirectory 'WebView2Loader.dll')
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required WebView2 SDK file is missing: $required"
    }
}

$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
$vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw "Cannot find Visual Studio locator: $vswhere"
}
$vsRoot = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) -join ''
if ($LASTEXITCODE -ne 0 -or -not $vsRoot) {
    throw 'Visual Studio C++ x64 build tools are not installed.'
}
$vcvarsall = Join-Path $vsRoot 'VC\Auxiliary\Build\vcvarsall.bat'
if (-not (Test-Path -LiteralPath $vcvarsall -PathType Leaf)) {
    throw "Cannot find vcvarsall.bat: $vcvarsall"
}
$null = New-Item -ItemType Directory -Path $output -Force

function Invoke-VcCommand([string]$Command) {
    $line = 'call "{0}" x64 >nul && cd /d "{1}" && {2}' -f $vcvarsall, $repository, $Command
    & $env:ComSpec /d /s /c $line
    if ($LASTEXITCODE -ne 0) { throw "Visual C++ command failed with exit code $LASTEXITCODE" }
}

$includeArg = '/I"{0}"' -f $includeDirectory
$handlerObject = Join-Path $output 'PreviewHandler.obj'
$selfTestObject = Join-Path $output 'PreviewHandlerSelfTest.obj'
$smokeObject = Join-Path $output 'WebView2HostSmoke.obj'
$handlerDll = Join-Path $output 'FourDPreviewHandler.dll'
$selfTestExe = Join-Path $output 'PreviewHandlerSelfTest.exe'
$smokeExe = Join-Path $output 'WebView2HostSmoke.exe'
$source = Join-Path $repository 'Support\WindowsPreviewHandler'

Invoke-VcCommand ('cl.exe /nologo /EHsc /std:c++17 /W4 /DUNICODE /D_UNICODE {0} /Fo"{1}" /c "{2}"' -f `
    $includeArg, $handlerObject, (Join-Path $source 'PreviewHandler.cpp'))
Invoke-VcCommand ('link.exe /nologo /DLL /OUT:"{0}" /LIBPATH:"{1}" /EXPORT:DllCanUnloadNow=FourDPreviewHandlerCanUnloadNow /EXPORT:DllGetClassObject=FourDPreviewHandlerGetClassObject "{2}" WebView2Loader.dll.lib user32.lib shlwapi.lib shell32.lib ole32.lib uuid.lib' -f `
    $handlerDll, $nativeDirectory, $handlerObject)
Invoke-VcCommand ('cl.exe /nologo /EHsc /std:c++17 /W4 /DUNICODE /D_UNICODE /Fo"{0}" /c "{1}"' -f `
    $selfTestObject, (Join-Path $source 'PreviewHandlerSelfTest.cpp'))
Invoke-VcCommand ('link.exe /nologo /OUT:"{0}" "{1}" user32.lib ole32.lib advapi32.lib uuid.lib' -f `
    $selfTestExe, $selfTestObject)
Invoke-VcCommand ('cl.exe /nologo /EHsc /std:c++17 /W4 /DUNICODE /D_UNICODE {0} /Fo"{1}" /c "{2}"' -f `
    $includeArg, $smokeObject, (Join-Path $source 'WebView2HostSmoke.cpp'))
Invoke-VcCommand ('link.exe /nologo /OUT:"{0}" /LIBPATH:"{1}" "{2}" WebView2Loader.dll.lib user32.lib ole32.lib' -f `
    $smokeExe, $nativeDirectory, $smokeObject)
Copy-Item -LiteralPath (Join-Path $nativeDirectory 'WebView2Loader.dll') -Destination $output -Force

if ($RunSelfTest) {
    if (-not $CliPath) {
        $swift = Get-Command swift.exe -CommandType Application -ErrorAction Stop
        $binDirectory = & $swift.Source build --show-bin-path
        if ($LASTEXITCODE -ne 0) { throw 'swift build --show-bin-path failed.' }
        $CliPath = Join-Path ($binDirectory -join '').Trim() 'fourdql.exe'
    }
    $CliPath = (Resolve-Path -LiteralPath $CliPath).Path
    . (Join-Path $PSScriptRoot 'package-cli-windows-support.ps1')
    $null = Get-CliPeInfo $CliPath
    Copy-Item -LiteralPath $CliPath -Destination (Join-Path $output 'fourdql.exe') -Force
    $fixture = Join-Path $repository 'Tests\FourDFileKitTests\Fixtures\FormProject\Project\Sources\Forms\Controls\form.4DForm'
    if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) {
        throw "Preview self-test fixture is missing: $fixture"
    }
    Push-Location $output
    try {
        & $selfTestExe $handlerDll $fixture
        if ($LASTEXITCODE -ne 0) { throw "In-process preview self-test failed with exit code $LASTEXITCODE" }

        $registrationScript = Join-Path $PSScriptRoot 'windows-preview-handler.ps1'
        & $registrationScript -Action Register -HandlerPath $handlerDll
        try {
            & $selfTestExe '--out-of-proc' $handlerDll $fixture
            if ($LASTEXITCODE -ne 0) { throw "prevhost.exe preview self-test failed with exit code $LASTEXITCODE" }
        } finally {
            & $registrationScript -Action Unregister -HandlerPath $handlerDll
        }
    } finally {
        Pop-Location
    }
}

Write-Host "Built x64 preview handler and self-tests in $output"
