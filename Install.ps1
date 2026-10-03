[CmdletBinding()]
param([string]$GameDirectory, [switch]$Check)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\OfflineFix.psm1') -Force
$folder = Resolve-GameDirectory $GameDirectory
if ($Check) {
    $status = Get-FixStatus $folder
    $status | Format-List
    if ($status.Status -eq 'unsupported') { throw 'This DLL is not supported. No files were changed.' }
} else { Install-OfflineFix $folder }
