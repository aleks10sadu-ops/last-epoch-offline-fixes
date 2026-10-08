[CmdletBinding()]
param([string]$Original151, [string]$Original152)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\OfflineFix.psm1') -Force
$passed = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++
}
$m151 = Get-FixManifest -GameVersion '1.5.1'
$m152 = Get-FixManifest -GameVersion '1.5.2'
foreach ($m in @($m151, $m152)) {
    Assert-True ((Get-FixManifest $m.original_sha256).game_version -eq $m.game_version) 'Original hash selected a wrong version.'
    Assert-True ((Get-FixManifest $m.patched_sha256).game_version -eq $m.game_version) 'Patched hash selected a wrong version.'
}
Assert-True ($null -eq (Get-FixManifest ('A' * 64))) 'An unknown DLL selected a manifest.'
Assert-True ((Get-FixManifest $m151.previous_patched_sha256).game_version -eq '1.5.1') 'Legacy development patch no longer supports restore.'

if ($Original151 -and $Original152) {
    $module = Get-Module OfflineFix
    & $module { function script:Get-Process { param($Name, $ErrorAction) } }
    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $testRoot = Join-Path $temporaryBase ('le-offline-version-tests-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    try {
        $backupFolder = Join-Path $testRoot '.le-offline-fixes'
        New-Item -ItemType Directory -Path $backupFolder | Out-Null
        $legacy = Join-Path $backupFolder 'GameAssembly.original.dll'
        $dll = Join-Path $testRoot 'GameAssembly.dll'
        Copy-Item -LiteralPath $Original151 -Destination $legacy
        [byte[]]$source151 = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Original151).ProviderPath)
        [IO.File]::WriteAllBytes($dll, (New-PatchedBytes $source151 $m151))
        Assert-True ((Get-FixStatus $testRoot).Version -eq '1.5.1') 'Installed 1.5.1 status failed.'
        Restore-OfflineFix $testRoot
        Assert-True ((Get-FileHash -LiteralPath $dll).Hash -eq $m151.original_sha256) 'Legacy 1.5.1 backup failed to restore.'
        Copy-Item -LiteralPath $Original152 -Destination $dll -Force
        Assert-True ((Get-FixStatus $testRoot).Version -eq '1.5.2') 'New 1.5.2 status failed.'
        Install-OfflineFix $testRoot
        Assert-True ((Get-FileHash -LiteralPath $legacy).Hash -eq $m151.original_sha256) 'Update overwrote the old backup.'
        $backup152 = Join-Path $backupFolder ('GameAssembly.' + $m152.original_sha256 + '.original.dll')
        Assert-True ((Get-FileHash -LiteralPath $backup152).Hash -eq $m152.original_sha256) 'Update failed to create a separate backup.'
        Assert-True ((Get-FixStatus $testRoot).Status -eq 'installed') 'Installed 1.5.2 status failed.'
        Restore-OfflineFix $testRoot
        Assert-True ((Get-FileHash -LiteralPath $dll).Hash -eq $m152.original_sha256) 'Update rollback restored a wrong game version.'
        Assert-True ((Get-FileHash -LiteralPath $legacy).Hash -eq $m151.original_sha256) 'Rollback damaged the older backup.'
        [IO.File]::WriteAllBytes($dll, [byte[]](1, 2, 3))
        Assert-True ((Get-FixStatus $testRoot).Status -eq 'unsupported') 'Unknown DLL status failed.'
    } finally {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        if ($resolved -ne $testRoot -or -not $resolved.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolved) -notmatch '^le-offline-version-tests-[0-9a-f]{32}$') { throw 'Unsafe temporary cleanup path.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host "PASS: $passed version selection and backup checks." -ForegroundColor Green
