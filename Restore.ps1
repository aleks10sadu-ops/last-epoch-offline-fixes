[CmdletBinding()]
param([string]$GameDirectory)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\OfflineFix.psm1') -Force
Restore-OfflineFix (Resolve-GameDirectory $GameDirectory)
