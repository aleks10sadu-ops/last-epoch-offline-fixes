Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AdaptivePatch.ps1')

function Get-FixManifest([string]$SHA256, [string]$GameVersion = '1.5.1') {
    foreach ($path in Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'patch-*.json' -File) {
        $manifest = Get-Content -LiteralPath $path.FullName -Raw | ConvertFrom-Json
        if ($SHA256) {
            if ($SHA256 -in @($manifest.original_sha256, $manifest.patched_sha256, $manifest.previous_patched_sha256)) { return $manifest }
        } elseif ($manifest.game_version -eq $GameVersion) { return $manifest }
    }
    return $null
}

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function ConvertFrom-Hex([string]$Hex) {
    if ($Hex -notmatch '\A(?:[0-9a-fA-F]{2})*\z') { throw 'Invalid hexadecimal patch data.' }
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16) }
    return ,$bytes
}

function New-PatchedBytes([byte[]]$Source, $Manifest = (Get-FixManifest)) {
    if ($Source.Length -ne $Manifest.original_length -or (Get-BytesHash $Source) -ne $Manifest.original_sha256) {
        throw 'Unsupported GameAssembly.dll. An exact supported build is required.'
    }
    if ($Manifest.schema -ne 1) { throw 'Unsupported patch manifest schema.' }
    [byte[]]$prefix = ConvertFrom-Hex $Manifest.append_prefix_hex
    [byte[]]$entry = ConvertFrom-Hex $Manifest.exception_function_hex
    [long]$tableOffset = $Manifest.exception_table_offset
    [long]$tableSize = $Manifest.exception_table_size
    [long]$appendOffset = $Manifest.append_offset
    [long]$outputSize = $Manifest.patched_length
    if ($tableOffset -lt 0 -or $tableSize -le 0 -or $tableSize % 12 -ne 0 -or
        $tableOffset + $tableSize -gt $Source.Length -or $appendOffset -lt $Source.Length -or
        $outputSize -gt 150MB -or $outputSize -lt $appendOffset + $prefix.Length + $tableSize + $entry.Length -or
        $prefix.Length -ne 192 -or $entry.Length -ne 12 -or $Manifest.append_alignment -ne 512 -or
        $appendOffset % 512 -ne 0 -or $outputSize % 512 -ne 0) { throw 'Invalid patch layout.' }
    $output = New-Object byte[] $outputSize
    [Array]::Copy($Source, 0, $output, 0, $Source.Length)
    [Array]::Copy($prefix, 0, $output, $appendOffset, $prefix.Length)
    # The original game's exception table is read locally. It is never distributed.
    [Array]::Copy($Source, $tableOffset, $output, $appendOffset + $prefix.Length, $tableSize)
    [Array]::Copy($entry, 0, $output, $appendOffset + $prefix.Length + $tableSize, $entry.Length)
    foreach ($change in $Manifest.changes) {
        [byte[]]$before = ConvertFrom-Hex $change.before
        [byte[]]$after = ConvertFrom-Hex $change.after
        [long]$offset = $change.offset
        if ($before.Length -ne $after.Length -or $offset -lt 0 -or $offset + $before.Length -gt $Source.Length) {
            throw 'Invalid patch range.'
        }
        for ($i = 0; $i -lt $before.Length; $i++) {
            if ($Source[$offset + $i] -ne $before[$i]) { throw "Original byte mismatch at offset $offset." }
        }
        [Array]::Copy($after, 0, $output, $offset, $after.Length)
    }
    if ((Get-BytesHash $output) -ne $Manifest.patched_sha256) { throw 'Patched file checksum mismatch. Nothing was installed.' }
    return ,$output
}

function Assert-GameClosed {
    if (Get-Process -Name 'Last Epoch', 'LastEpoch' -ErrorAction SilentlyContinue) { throw 'Close Last Epoch before installing or restoring.' }
}

function Resolve-GameDirectory([string]$GameDirectory) {
    if (-not $GameDirectory) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select Last Epoch.exe in your game installation'
        $dialog.Filter = 'Last Epoch executable|Last Epoch.exe|Executable files|*.exe'
        try {
            if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw 'No game folder selected.' }
            $GameDirectory = [IO.Path]::GetDirectoryName($dialog.FileName)
        } finally { $dialog.Dispose() }
    }
    $folder = (Resolve-Path -LiteralPath $GameDirectory).ProviderPath
    if (-not (Test-Path -LiteralPath (Join-Path $folder 'GameAssembly.dll') -PathType Leaf)) { throw 'GameAssembly.dll was not found in this folder.' }
    return $folder
}

function Get-FixStatus([string]$GameDirectory) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $GameDirectory 'GameAssembly.dll') -Algorithm SHA256).Hash
    $manifest = Get-ResolvedManifest $GameDirectory $hash
    $status = 'unsupported'
    $version = 'unknown'
    $reason = ''
    if (-not $manifest) {
        try {
            $manifest = Get-AdaptiveManifest ([IO.File]::ReadAllBytes((Join-Path $GameDirectory 'GameAssembly.dll')))
            $status = 'adaptive-compatible'
        } catch { $reason = $_.Exception.Message }
    }
    if ($manifest) {
        $version = $manifest.game_version
        if ($hash -eq $manifest.original_sha256 -and $status -ne 'adaptive-compatible') { $status = 'original-supported' }
        elseif ($hash -eq $manifest.patched_sha256) { $status = 'installed' }
        elseif ($hash -eq $manifest.previous_patched_sha256) { $status = 'previous-development-patch' }
    }
    [PSCustomObject]@{ Status = $status; SHA256 = $hash; Version = $version; Reason = $reason }
}

function Get-BackupPath([string]$GameDirectory, $Manifest) {
    $folder = Join-Path $GameDirectory '.le-offline-fixes'
    $versioned = Join-Path $folder ('GameAssembly.' + $Manifest.original_sha256 + '.original.dll')
    if (Test-Path -LiteralPath $versioned) { return $versioned }
    # Keep existing 1.5.1 installations reversible without replacing their backup.
    $legacy = Join-Path $folder 'GameAssembly.original.dll'
    if ((Test-Path -LiteralPath $legacy -PathType Leaf) -and
        (Get-FileHash -LiteralPath $legacy -Algorithm SHA256).Hash -eq $Manifest.original_sha256) { return $legacy }
    return $versioned
}

function Write-VerifiedReplacement([string]$Target, [byte[]]$Bytes, [string]$ExpectedCurrentHash, [string]$ExpectedNewHash) {
    $temporary = $Target + '.lefix-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $ExpectedNewHash) { throw 'Temporary file verification failed.' }
        Assert-GameClosed
        if ((Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash -ne $ExpectedCurrentHash) { throw 'GameAssembly.dll changed during the operation. Retry with the game closed.' }
        # Atomic replacement on Windows; the verified persistent backup already exists.
        [IO.File]::Replace($temporary, $Target, [NullString]::Value)
        if ((Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash -ne $ExpectedNewHash) { throw 'Final verification failed. Restore the verified backup.' }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Install-OfflineFix([string]$GameDirectory) {
    Assert-GameClosed
    $target = Join-Path $GameDirectory 'GameAssembly.dll'
    $status = Get-FixStatus $GameDirectory
    if ($status.Status -eq 'installed') { Write-Host 'Already installed. No files changed.'; return }
    if ($status.Status -notin @('original-supported', 'adaptive-compatible')) { throw "Unsupported DLL ($($status.SHA256)). $($status.Reason) No files changed." }
    $manifest = Get-ResolvedManifest $GameDirectory $status.SHA256
    [byte[]]$source = [IO.File]::ReadAllBytes($target)
    if (-not $manifest) {
        $manifest = Get-AdaptiveManifest $source
        Write-Host 'Unlisted build: all structural checks passed. Gameplay compatibility is not yet established.' -ForegroundColor Yellow
    }
    [byte[]]$patched = New-PatchedBytes $source $manifest
    $backupFolder = Join-Path $GameDirectory '.le-offline-fixes'
    if (Test-Path -LiteralPath $backupFolder) {
        if ((Get-Item -LiteralPath $backupFolder).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Backup folder must not be a link.' }
    } else { New-Item -ItemType Directory -Path $backupFolder | Out-Null }
    $backup = Get-BackupPath $GameDirectory $manifest
    if (-not (Test-Path -LiteralPath $backup)) {
        $stream = [IO.File]::Open($backup, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($source, 0, $source.Length) } finally { $stream.Dispose() }
    }
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $manifest.original_sha256) { throw 'Existing backup is not the expected original DLL. It was not overwritten.' }
    Save-AdaptiveManifest $GameDirectory $manifest
    Write-VerifiedReplacement $target $patched $manifest.original_sha256 $manifest.patched_sha256
    Write-Host "Installed Last Epoch $($manifest.game_version) offline fixes." -ForegroundColor Green
    Write-Host "Original DLL backup: $backup"
    Write-Host 'Start the game normally and choose Play Offline. Character saves were not edited.'
}

function Restore-OfflineFix([string]$GameDirectory) {
    Assert-GameClosed
    $status = Get-FixStatus $GameDirectory
    if ($status.Status -in @('original-supported', 'adaptive-compatible')) { Write-Host 'Already original. No files changed.'; return }
    if ($status.Status -notin @('installed', 'previous-development-patch')) { throw 'Unrecognized current DLL. Restore was refused to protect another game version or mod.' }
    $manifest = Get-ResolvedManifest $GameDirectory $status.SHA256
    $backup = Get-BackupPath $GameDirectory $manifest
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw 'Original backup not found. Use the game launcher to verify/restore game files.' }
    [byte[]]$source = [IO.File]::ReadAllBytes($backup)
    if ((Get-BytesHash $source) -ne $manifest.original_sha256) { throw 'Original backup checksum mismatch. Nothing was restored.' }
    Write-VerifiedReplacement (Join-Path $GameDirectory 'GameAssembly.dll') $source $status.SHA256 $manifest.original_sha256
    Write-Host 'Original DLL restored. Character progress and cosmetic caches were kept.' -ForegroundColor Green
}

Export-ModuleMember -Function Get-FixManifest, Get-BytesHash, New-PatchedBytes, Resolve-GameDirectory, Get-FixStatus, Install-OfflineFix, Restore-OfflineFix, Get-AdaptiveManifest
