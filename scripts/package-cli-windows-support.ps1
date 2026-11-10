# Shared with the platform-independent packaging probes. No external PE tools required.
Set-StrictMode -Version Latest

function Get-CliPeInfo {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    function Assert-Range([long]$Offset, [long]$Size) {
        if ($Offset -lt 0 -or $Size -lt 0 -or $Offset + $Size -gt $bytes.LongLength) {
            throw "Truncated or invalid PE file: $Path (offset $Offset, size $Size)"
        }
    }
    function Read-U16([long]$Offset) {
        Assert-Range $Offset 2
        [BitConverter]::ToUInt16($bytes, [int]$Offset)
    }
    function Read-U32([long]$Offset) {
        Assert-Range $Offset 4
        [BitConverter]::ToUInt32($bytes, [int]$Offset)
    }
    if ((Read-U16 0) -ne 0x5a4d) { throw "Not a PE file: $Path" }
    $pe = [long](Read-U32 0x3c)
    if ((Read-U32 $pe) -ne 0x4550) { throw "Invalid PE signature: $Path" }
    $machine = Read-U16 ($pe + 4)
    if ($machine -ne 0x8664) {
        throw ('Expected x86_64 PE machine 0x8664, got 0x{0:x4}: {1}' -f $machine, $Path)
    }
    $sectionCount = Read-U16 ($pe + 6)
    $optionalSize = Read-U16 ($pe + 20)
    $optional = $pe + 24
    Assert-Range $optional $optionalSize
    if ($optionalSize -lt 112 -or (Read-U16 $optional) -ne 0x20b) {
        throw "Expected a PE32+ optional header: $Path"
    }
    $directoryCount = Read-U32 ($optional + 108)
    if ($directoryCount -gt [math]::Floor(($optionalSize - 112) / 8)) {
        throw "Invalid PE data-directory count: $Path"
    }
    $headerSize = Read-U32 ($optional + 60)
    $sections = @(
        for ($i = 0; $i -lt $sectionCount; $i++) {
            $section = $optional + $optionalSize + $i * 40
            Assert-Range $section 40
            [pscustomobject]@{
                RVA = [long](Read-U32 ($section + 12))
                RawSize = [long](Read-U32 ($section + 16))
                RawOffset = [long](Read-U32 ($section + 20))
            }
        }
    )
    function Convert-Rva([long]$Rva, [long]$Size) {
        if ($Rva -lt $headerSize -and $Rva + $Size -le $headerSize) {
            Assert-Range $Rva $Size
            return $Rva
        }
        foreach ($section in $sections) {
            $relative = $Rva - $section.RVA
            if ($relative -ge 0 -and $relative + $Size -le $section.RawSize) {
                $offset = $section.RawOffset + $relative
                Assert-Range $offset $Size
                return $offset
            }
        }
        throw "Unmapped PE RVA $Rva in $Path"
    }
    function Read-DllName([long]$Rva) {
        $name = [Text.StringBuilder]::new()
        for ($i = 0; $i -lt 260; $i++) {
            $offset = Convert-Rva ($Rva + $i) 1
            $character = $bytes[$offset]
            if ($character -eq 0) {
                $result = $name.ToString()
                if ($result -notmatch '^[A-Za-z0-9_+.-]+[.]dll$') {
                    throw "Invalid imported DLL name '$result' in $Path"
                }
                return $result
            }
            [void]$name.Append([char]$character)
        }
        throw "Unterminated PE import name in $Path"
    }
    $imports = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # IMAGE_IMPORT_DESCRIPTOR and ImgDelayDescr, including imports not used by --help.
    foreach ($table in @(
        @{ Index = 1; Stride = 20; NameOffset = 12 },
        @{ Index = 13; Stride = 32; NameOffset = 4 }
    )) {
        if ($directoryCount -le $table.Index) { continue }
        $directory = $optional + 112 + $table.Index * 8
        $rva = [long](Read-U32 $directory)
        $size = [long](Read-U32 ($directory + 4))
        if ($rva -eq 0 -and $size -eq 0) { continue }
        if ($rva -eq 0 -or $size -lt $table.Stride) {
            throw "Invalid PE import directory in $Path"
        }
        $terminated = $false
        for ($position = 0L; $position + $table.Stride -le $size; $position += $table.Stride) {
            $descriptor = Convert-Rva ($rva + $position) $table.Stride
            $nonzero = $false
            for ($field = 0; $field -lt $table.Stride; $field += 4) {
                if ((Read-U32 ($descriptor + $field)) -ne 0) { $nonzero = $true }
            }
            if (-not $nonzero) { $terminated = $true; break }
            if ($table.Index -eq 13 -and (Read-U32 $descriptor) -ne 1) {
                throw "Unsupported VA-based delay import in $Path"
            }
            $nameRva = Read-U32 ($descriptor + $table.NameOffset)
            [void]$imports.Add((Read-DllName $nameRva))
        }
        if (-not $terminated) { throw "Unterminated PE import directory in $Path" }
    }
    [pscustomobject]@{ Machine = $machine; Imports = @($imports | Sort-Object) }
}

function Test-CliSystemDll {
    param([string]$Name, [string]$SystemDirectory)
    if ($Name -match '^(api-ms-win-|ext-ms-win-).+[.]dll$') { return $true }
    # These can be preinstalled on a runner, but are not part of Windows.
    if ($Name -match '^(msvcp|msvcr|vcruntime|concrt|vcomp)\d.*[.]dll$') { return $false }
    $path = Join-Path $SystemDirectory $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($path)
    # Fail closed for anything not identified as a Windows component. In
    # particular never classify arbitrary Swift/VC DLLs in System32 as OS files.
    return $info.CompanyName -match '^Microsoft Corporation$' -and
        $info.ProductName -match 'Windows.*Operating System'
}

function Copy-CliDependencyClosure {
    param(
        [Parameter(Mandatory)][string]$BinaryPath,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string[]]$SearchDirectories,
        [Parameter(Mandatory)][scriptblock]$IsSystemDll
    )
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($BinaryPath)
    $resolved = @{}
    $records = [Collections.Generic.List[object]]::new()
    while ($queue.Count -gt 0) {
        $source = $queue.Dequeue()
        $name = [IO.Path]::GetFileName($source)
        $key = $name.ToLowerInvariant()
        if ($resolved.ContainsKey($key)) { continue }
        $pe = Get-CliPeInfo $source
        $resolved[$key] = $source
        Copy-Item -LiteralPath $source -Destination (Join-Path $Destination $name)
        # Preserve private assembly metadata, including per-machine MSI
        # manifests stored in WinSxS/Manifests rather than beside the DLL.
        $manifest = [IO.Path]::ChangeExtension($source, '.manifest')
        $sourceDirectory = Split-Path $source -Parent
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf) -and
            (Split-Path (Split-Path $sourceDirectory -Parent) -Leaf) -ieq 'WinSxS') {
            $manifest = Join-Path (Split-Path $sourceDirectory -Parent) `
                "Manifests/$(Split-Path $sourceDirectory -Leaf).manifest"
            if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
                throw "Missing WinSxS assembly manifest for $source"
            }
        }
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            $xml = [xml](Get-Content -LiteralPath $manifest -Raw)
            $identity = $xml.SelectSingleNode('/*[local-name()="assembly"]/*[local-name()="assemblyIdentity"]')
            if (-not $identity -or $identity.name -notmatch '^[A-Za-z0-9_+.-]+$') {
                throw "Invalid private assembly identity in $manifest"
            }
            Copy-Item -LiteralPath $manifest -Destination (Join-Path $Destination "$($identity.name).manifest")
        }
        $records.Add([pscustomobject]@{
            File = $name
            SHA256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
            Imports = $pe.Imports
        })
        foreach ($dependency in $pe.Imports) {
            if (& $IsSystemDll $dependency) { continue }
            if ($resolved.ContainsKey($dependency.ToLowerInvariant())) { continue }
            $candidate = $null
            foreach ($directory in $SearchDirectories) {
                $path = Join-Path $directory $dependency
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    # Check before selecting: do not silently skip a wrong-arch
                    # DLL and make packaging depend on directory ordering.
                    $null = Get-CliPeInfo $path
                    $candidate = $path
                    break
                }
            }
            if (-not $candidate) {
                throw "Missing non-system dependency '$dependency' imported by '$source'. Searched: $($SearchDirectories -join '; ')"
            }
            $queue.Enqueue($candidate)
        }
    }
    return $records.ToArray()
}
