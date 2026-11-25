<#
.SYNOPSIS
Register or unregister the x64 4D Explorer preview handler for the current user.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Register', 'Unregister')]
    [string]$Action,
    [string]$HandlerPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or -not [Environment]::Is64BitProcess) {
    throw 'Preview-handler registration requires 64-bit PowerShell on Windows.'
}
if (-not $HandlerPath) {
    $packagedDll = Join-Path $PSScriptRoot 'FourDPreviewHandler.dll'
    $HandlerPath = if (Test-Path -LiteralPath $packagedDll -PathType Leaf) {
        $packagedDll
    } else {
        Join-Path $PSScriptRoot '..\.build\windows-preview-handler\FourDPreviewHandler.dll'
    }
}

$clsid = '{734A81C0-607D-4D0A-9E9B-67C7B06E4B21}'
$appId = '{6D2B5079-2F0B-48DD-AB7F-97CEC514D30B}'
$previewHandlerInterface = '{8895B1C6-B41F-4C1C-A562-0D564250836F}'
$displayName = '4D Quick Look Preview Handler'
$extensions = @(
    '.4dd', '.4db', '.4dcatalog', '.4dsettings', '.4dlink', '.4dpreferences',
    '.4si', '.4dproject', '.4df', '.4st', '.4qr', '.4lbp', '.4wp', '.4vp',
    '.4dm', '.4dform'
)
$handlerPath = [IO.Path]::GetFullPath($HandlerPath)
$classesRoot = 'Software\Classes'
$classPath = "$classesRoot\CLSID\$clsid"
$serverPath = "$classPath\InprocServer32"
$previewListPath = 'Software\Microsoft\Windows\CurrentVersion\PreviewHandlers'
$registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser,
    [Microsoft.Win32.RegistryView]::Registry64
)

function Get-RegistryValue([string]$Path, [string]$Name = '') {
    $key = $registry.OpenSubKey($Path, $false)
    if (-not $key) { return $null }
    try { return $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    finally { $key.Dispose() }
}

function Set-RegistryValue([string]$Path, [string]$Name, [string]$Value) {
    $key = $registry.CreateSubKey($Path, $true)
    if (-not $key) { throw "Cannot create per-user registry key: $Path" }
    try { $key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $key.Dispose() }
}

function Remove-RegistryValue([string]$Path, [string]$Name) {
    $key = $registry.OpenSubKey($Path, $true)
    if (-not $key) { return }
    try { $key.DeleteValue($Name, $false) }
    finally { $key.Dispose() }
}

function Remove-EmptyKey([string]$Path) {
    $key = $registry.OpenSubKey($Path, $false)
    if (-not $key) { return }
    try {
        if ($key.SubKeyCount -ne 0 -or $key.ValueCount -ne 0) { return }
    } finally { $key.Dispose() }
    $separator = $Path.LastIndexOf('\')
    if ($separator -gt 0) {
        $parent = $registry.OpenSubKey($Path.Substring(0, $separator), $true)
        if ($parent) {
            try { $parent.DeleteSubKey($Path.Substring($separator + 1), $false) }
            finally { $parent.Dispose() }
        }
    }
}

function ConvertTo-ComparablePath([string]$Path) {
    if (-not $Path) { return $null }
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Notify-ShellAssociationsChanged {
    if (-not ('FourDQuickLookShellNotifications' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FourDQuickLookShellNotifications {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
}
'@
    }
    [FourDQuickLookShellNotifications]::SHChangeNotify(
        0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero
    )
}

try {
    if ($Action -eq 'Register') {
        if (-not (Test-Path -LiteralPath $handlerPath -PathType Leaf)) {
            throw "Preview-handler DLL does not exist: $handlerPath"
        }

        $existingName = Get-RegistryValue $classPath
        $existingAppId = Get-RegistryValue $classPath 'AppID'
        $existingServer = Get-RegistryValue $serverPath
        if ($existingName -and $existingName -ne $displayName) {
            throw "The preview-handler CLSID is already registered as '$existingName'."
        }
        if ($existingAppId -and $existingAppId -ine $appId) {
            throw "The preview-handler CLSID already uses a different AppID: $existingAppId"
        }
        if ($existingServer -and (ConvertTo-ComparablePath $existingServer) -ine
            (ConvertTo-ComparablePath $handlerPath)) {
            throw "The preview-handler CLSID is already backed by another DLL: $existingServer"
        }
        $existingListName = Get-RegistryValue $previewListPath $clsid
        if ($existingListName -and $existingListName -ne $displayName) {
            throw "The PreviewHandlers list already contains a different name for $clsid."
        }
        foreach ($extension in $extensions) {
            $associationPath = "$classesRoot\SystemFileAssociations\$extension\ShellEx\$previewHandlerInterface"
            $existingHandler = Get-RegistryValue $associationPath
            if ($existingHandler -and $existingHandler -ine $clsid) {
                throw "$extension already has a different preview handler: $existingHandler"
            }
        }

        Set-RegistryValue $classPath '' $displayName
        Set-RegistryValue $classPath 'AppID' $appId
        Set-RegistryValue $serverPath '' $handlerPath
        Set-RegistryValue $serverPath 'ThreadingModel' 'Apartment'
        Set-RegistryValue $previewListPath $clsid $displayName
        foreach ($extension in $extensions) {
            $associationPath = "$classesRoot\SystemFileAssociations\$extension\ShellEx\$previewHandlerInterface"
            Set-RegistryValue $associationPath '' $clsid
        }
        Notify-ShellAssociationsChanged
        Write-Host "Registered $displayName for the current user without changing file ProgIDs or default applications."
    } else {
        $existingServer = Get-RegistryValue $serverPath
        if ($existingServer -and (ConvertTo-ComparablePath $existingServer) -ine
            (ConvertTo-ComparablePath $handlerPath)) {
            throw "Registration points to a different DLL; refusing to remove it: $existingServer"
        }
        foreach ($extension in $extensions) {
            $associationPath = "$classesRoot\SystemFileAssociations\$extension\ShellEx\$previewHandlerInterface"
            if ((Get-RegistryValue $associationPath) -ieq $clsid) {
                Remove-RegistryValue $associationPath ''
                Remove-EmptyKey $associationPath
                Remove-EmptyKey (Split-Path -Path $associationPath -Parent)
            }
        }
        if ((Get-RegistryValue $previewListPath $clsid) -eq $displayName) {
            Remove-RegistryValue $previewListPath $clsid
        }
        if ($existingServer) {
            $registry.DeleteSubKeyTree($classPath, $false)
        }
        Notify-ShellAssociationsChanged
        Write-Host "Unregistered $displayName for the current user."
    }
} finally {
    $registry.Dispose()
}
