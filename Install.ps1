[CmdletBinding()]
param([string]$GameDirectory, [switch]$Check, [switch]$Analyze)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\OfflineFix.psm1') -Force
$folder = Resolve-GameDirectory $GameDirectory
if ($Analyze) {
    $manifest = Get-AdaptiveManifest ([IO.File]::ReadAllBytes((Join-Path $folder 'GameAssembly.dll')))
    $manifest | Select-Object game_version, build, original_sha256, patched_sha256, adaptive | Format-List
    Write-Host 'Analysis only. No game files were changed.'
} elseif ($Check) {
    $status = Get-FixStatus $folder
    $status | Format-List
    if ($status.Status -eq 'unsupported') { throw 'This DLL is not supported. No files were changed.' }
} else { Install-OfflineFix $folder }
