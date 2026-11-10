# Run on any platform with PowerShell 7:
# pwsh -NoProfile -File scripts/test-package-cli-windows.ps1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'package-cli-windows-support.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    try { & $Action } catch {
        Assert-True ($_.Exception.Message -match $Pattern) "Wrong failure: $_ (expected $Pattern)"
        return
    }
    throw "Expected failure matching: $Pattern"
}
function Write-ProbePe {
    param([string]$Path, [string[]]$Imports = @(), [string[]]$DelayImports = @(), [int]$Machine = 0x8664)
    $bytes = [byte[]]::new(4096)
    function Put-U16([int]$Offset, [uint16]$Value) {
        [BitConverter]::GetBytes($Value).CopyTo($bytes, $Offset)
    }
    function Put-U32([int]$Offset, [uint32]$Value) {
        [BitConverter]::GetBytes($Value).CopyTo($bytes, $Offset)
    }
    Put-U16 0 0x5a4d
    Put-U32 0x3c 0x80
    Put-U32 0x80 0x4550
    Put-U16 0x84 $Machine
    Put-U16 0x86 1
    Put-U16 0x94 240
    $optional = 0x98
    Put-U16 $optional 0x20b
    Put-U32 ($optional + 60) 0x200
    Put-U32 ($optional + 108) 16
    $section = $optional + 240
    Put-U32 ($section + 8) 0xe00
    Put-U32 ($section + 12) 0x1000
    Put-U32 ($section + 16) 0xe00
    Put-U32 ($section + 20) 0x200
    $nameOffset = 0x800
    foreach ($table in @(
        @{ Index = 1; Stride = 20; NameOffset = 12; Offset = 0x200; Names = $Imports },
        @{ Index = 13; Stride = 32; NameOffset = 4; Offset = 0x400; Names = $DelayImports }
    )) {
        if ($table.Names.Count -eq 0) { continue }
        Put-U32 ($optional + 112 + $table.Index * 8) ($table.Offset + 0xe00)
        Put-U32 ($optional + 116 + $table.Index * 8) (($table.Names.Count + 1) * $table.Stride)
        $descriptor = $table.Offset
        foreach ($name in $table.Names) {
            if ($table.Index -eq 13) { Put-U32 $descriptor 1 }
            Put-U32 ($descriptor + $table.NameOffset) ($nameOffset + 0xe00)
            $encoded = [Text.Encoding]::ASCII.GetBytes($name)
            $encoded.CopyTo($bytes, $nameOffset)
            $nameOffset += $encoded.Length + 1
            $descriptor += $table.Stride
        }
    }
    [IO.File]::WriteAllBytes($Path, $bytes)
}

$root = Join-Path (Split-Path $PSScriptRoot -Parent) ".build/windows-packaging-probe-$([guid]::NewGuid().ToString('N'))"
try {
    foreach ($script in @('package-cli-windows.ps1', 'package-cli-windows-support.ps1', 'test-package-cli-windows.ps1')) {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $PSScriptRoot $script), [ref]$tokens, [ref]$errors)
        Assert-True ($errors.Count -eq 0) "PowerShell parse errors in ${script}: $errors"
        if ($script -eq 'package-cli-windows.ps1') {
            $parameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Version' }
            $validation = $parameter.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidatePattern' }
            $pattern = $validation.PositionalArguments[0].Value
            foreach ($version in @('1.2.3', '0.0.0-ci.12345', '1.2.3-rc.1+build.42')) {
                Assert-True ($version -match $pattern) "Valid package version rejected: $version"
            }
            foreach ($version in @('../escape', '1.2.3-ci.', 'v1.2.3', '1.2')) {
                Assert-True ($version -notmatch $pattern) "Invalid package version accepted: $version"
            }
        }
    }
    $source = Join-Path $root 'input'
    $runtime = Join-Path $root 'runtime'
    $destination = Join-Path $root 'output'
    $null = New-Item -ItemType Directory -Path $source, $runtime, $destination -Force
    $exe = Join-Path $source 'fourdql.exe'
    Write-ProbePe $exe @('KERNEL32.dll', 'swiftCore.dll', 'swiftCore.dll') @('Foundation.dll')
    Write-ProbePe (Join-Path $runtime 'swiftCore.dll') @('vcruntime140.dll')
    Write-ProbePe (Join-Path $runtime 'Foundation.dll') @('swiftCore.dll') @('api-ms-win-core-file-l1-1-0.dll')
    Write-ProbePe (Join-Path $runtime 'vcruntime140.dll') @('KERNEL32.dll')
    Write-ProbePe (Join-Path $runtime 'unused-tool.dll')
    '<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity name="Foundation" version="1.0.0.0" processorArchitecture="amd64" type="win32"/></assembly>' |
        Set-Content -LiteralPath (Join-Path $runtime 'Foundation.manifest')
    $info = Get-CliPeInfo $exe
    Assert-True ($info.Imports.Count -eq 3) 'Normal and delay imports must be deduplicated and combined.'
    Assert-True ($info.Imports -contains 'Foundation.dll') 'Missing delay import.'
    $system = { param($name) $name -ieq 'KERNEL32.dll' -or $name -like 'api-ms-win-*' }
    $records = @(Copy-CliDependencyClosure $exe $destination @($source, $runtime) $system)
    Assert-True ($records.Count -eq 4) 'Transitive closure should contain exactly four PE files.'
    Assert-True ((Get-ChildItem -LiteralPath $destination -File).Count -eq 5) 'Unexpected files copied.'
    Assert-True (Test-Path -LiteralPath (Join-Path $destination 'Foundation.manifest')) 'Private assembly manifest omitted.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destination 'unused-tool.dll'))) 'Copied unrelated DLL.'
    foreach ($record in $records) {
        Assert-True ($record.SHA256 -match '^[0-9a-f]{64}$') 'Missing manifest hash.'
    }
    # A cycle must terminate; a dependency's basename is case-insensitive.
    Write-ProbePe (Join-Path $runtime 'swiftCore.dll') @('Foundation.dll')
    $records = @(Copy-CliDependencyClosure $exe $destination @($source, $runtime) $system)
    Assert-True ($records.Count -eq 3) 'Dependency cycles should terminate.'
    Remove-Item -LiteralPath (Join-Path $runtime 'Foundation.dll')
    Assert-Throws { Copy-CliDependencyClosure $exe $destination @($source, $runtime) $system } 'Missing non-system dependency'
    Write-ProbePe (Join-Path $runtime 'Foundation.dll') -Machine 0xaa64
    Assert-Throws { Copy-CliDependencyClosure $exe $destination @($source, $runtime) $system } 'Expected x86_64'
    Write-ProbePe (Join-Path $runtime 'Foundation.dll') -Machine 0x14c
    Assert-Throws { Get-CliPeInfo (Join-Path $runtime 'Foundation.dll') } 'Expected x86_64'
    $malformed = Join-Path $root 'malformed.exe'
    [IO.File]::WriteAllBytes($malformed, [byte[]]@(0x4d, 0x5a))
    Assert-Throws { Get-CliPeInfo $malformed } 'Truncated or invalid'
    Write-ProbePe $malformed @('../bad.dll')
    Assert-Throws { Get-CliPeInfo $malformed } 'Invalid imported DLL name'
    Write-ProbePe $malformed
    $bytes = [IO.File]::ReadAllBytes($malformed)
    [BitConverter]::GetBytes([uint32]4294967280).CopyTo($bytes, 0x110)
    [BitConverter]::GetBytes([uint32]40).CopyTo($bytes, 0x114)
    [IO.File]::WriteAllBytes($malformed, $bytes)
    Assert-Throws { Get-CliPeInfo $malformed } 'Unmapped PE RVA'
    Write-ProbePe $malformed @('swiftCore.dll')
    $bytes = [IO.File]::ReadAllBytes($malformed)
    [BitConverter]::GetBytes([uint32]20).CopyTo($bytes, 0x114)
    [IO.File]::WriteAllBytes($malformed, $bytes)
    Assert-Throws { Get-CliPeInfo $malformed } 'Unterminated PE import directory'
    Write-ProbePe $malformed -DelayImports @('Foundation.dll')
    $bytes = [IO.File]::ReadAllBytes($malformed)
    [BitConverter]::GetBytes([uint32]0).CopyTo($bytes, 0x400)
    [IO.File]::WriteAllBytes($malformed, $bytes)
    Assert-Throws { Get-CliPeInfo $malformed } 'Unsupported VA-based delay import'
    # WinSxS manifests are outside their DLL directories and their identity
    # need not equal the imported DLL basename.
    $sxs = Join-Path $root 'WinSxS/amd64_swift.foundation_6.4.2.0_none_probe'
    $sxsManifests = Join-Path $root 'WinSxS/Manifests'
    $null = New-Item -ItemType Directory -Path $sxs, $sxsManifests -Force
    Write-ProbePe (Join-Path $sxs 'Foundation.dll')
    $sxsManifest = Join-Path $sxsManifests 'amd64_swift.foundation_6.4.2.0_none_probe.manifest'
    '<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity name="Swift.Foundation" version="6.4.2.0" processorArchitecture="amd64" type="win32"/></assembly>' |
        Set-Content -LiteralPath $sxsManifest
    $null = Copy-CliDependencyClosure (Join-Path $sxs 'Foundation.dll') $destination @($sxs) $system
    Assert-True (Test-Path -LiteralPath (Join-Path $destination 'Swift.Foundation.manifest')) 'WinSxS private assembly manifest omitted.'
    Remove-Item -LiteralPath $sxsManifest
    Assert-Throws { Copy-CliDependencyClosure (Join-Path $sxs 'Foundation.dll') $destination @($sxs) $system } 'Missing WinSxS assembly manifest'
    Assert-True (Test-CliSystemDll 'api-ms-win-core-file-l1-1-0.dll' $runtime) 'API sets are OS dependencies.'
    Assert-True (Test-CliSystemDll 'ext-ms-win-ntuser-window-l1-1-0.dll' $runtime) 'Extension API sets are OS dependencies.'
    Assert-True (-not (Test-CliSystemDll 'vcruntime140.dll' $runtime)) 'VC CRT must not be treated as an OS dependency.'
    Assert-True (-not (Test-CliSystemDll 'missing.dll' $runtime)) 'Unknown DLL must fail closed.'
    # Archive structure must preserve the enclosing folder, including its EXE.
    $zip = Join-Path $root 'probe.zip'
    Compress-Archive -LiteralPath $destination -DestinationPath $zip
    $unpack = Join-Path $root 'unpacked'
    Expand-Archive -LiteralPath $zip -DestinationPath $unpack
    Assert-True (Test-Path -LiteralPath (Join-Path $unpack 'output/fourdql.exe')) 'ZIP did not preserve the containing folder.'
    Write-Host 'Windows packaging probes passed (PE imports, delay imports, closure, failures, manifests, ZIP layout, syntax).'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
