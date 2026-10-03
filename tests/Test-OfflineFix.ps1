[CmdletBinding()]
param([string]$OriginalDll)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repository 'src\OfflineFix.psm1') -Force
$module = Get-Module OfflineFix
$passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Expect-Error([scriptblock]$Action, [string]$MessagePattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert-True ($null -ne $caught) 'An unsafe operation unexpectedly succeeded.'
    Assert-True ($caught -match $MessagePattern) "Unexpected error: $caught"
    $script:passed++
}
function Clone-Manifest($Value) { $Value | ConvertTo-Json -Depth 10 | ConvertFrom-Json }

# A small independent fixture: distinctive exception bytes must be copied from
# the source, while the new function data comes from the manifest.
[byte[]]$source = New-Object byte[] 4096
[byte[]]$table = 17, 34, 51, 68, 85, 102, 119, 136, 153, 170, 187, 204
[Array]::Copy($table, 0, $source, 256, 12)
[byte[]]$expected = New-Object byte[] 4608
[Array]::Copy($source, 0, $expected, 0, 4096)
for ($i = 4096; $i -lt 4288; $i++) { $expected[$i] = 90 }
[Array]::Copy($table, 0, $expected, 4288, 12)
for ($i = 4300; $i -lt 4312; $i++) { $expected[$i] = 165 }
$expected[32] = 3
$fixture = [PSCustomObject]@{
    schema = 1; game_version = 'test'; original_length = 4096; patched_length = 4608
    original_sha256 = (Get-BytesHash $source); patched_sha256 = (Get-BytesHash $expected)
    previous_patched_sha256 = ('F' * 64); append_offset = 4096; append_alignment = 512
    append_prefix_hex = ('5a' * 192); exception_function_hex = ('a5' * 12)
    exception_table_offset = 256; exception_table_size = 12
    changes = @([PSCustomObject]@{ offset = 32; before = '00'; after = '03' })
}
[byte[]]$actual = New-PatchedBytes $source $fixture
Assert-True ((Get-BytesHash $actual) -eq $fixture.patched_sha256) 'Reconstructed fixture differs.'
Assert-True ((Get-BytesHash $source) -eq $fixture.original_sha256) 'Builder mutated the input.'
$passed++

[byte[]]$damaged = $source.Clone(); $damaged[200] = 1
Expect-Error { New-PatchedBytes $damaged $fixture } 'Unsupported GameAssembly'
$bad = Clone-Manifest $fixture; $bad.exception_table_offset = 4090
Expect-Error { New-PatchedBytes $source $bad } 'Invalid patch layout'
$bad = Clone-Manifest $fixture; $bad.changes[0].offset = -1
Expect-Error { New-PatchedBytes $source $bad } 'Invalid patch range'
$bad = Clone-Manifest $fixture; $bad.changes[0].before = 'ff'
Expect-Error { New-PatchedBytes $source $bad } 'Original byte mismatch'
$bad = Clone-Manifest $fixture; $bad.changes[0].after = '04'
Expect-Error { New-PatchedBytes $source $bad } 'checksum mismatch'
$bad = Clone-Manifest $fixture; $bad.append_prefix_hex = 'invalid'
Expect-Error { New-PatchedBytes $source $bad } 'Invalid hexadecimal'
$bad = Clone-Manifest $fixture; $bad.schema = 2
Expect-Error { New-PatchedBytes $source $bad } 'manifest schema'

$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $temporaryBase ('le-offline-fixes-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    # These replacements exist only inside the test module's memory. Production
    # code has no process-check override or user-supplied manifest parameter.
    & $module {
        param($Manifest)
        $script:TestManifest = $Manifest
        $script:TestGameRunning = $false
        function script:Get-FixManifest { $script:TestManifest }
        function script:Get-Process {
            param($Name, $ErrorAction)
            if ($script:TestGameRunning) { [PSCustomObject]@{ Name = 'Last Epoch' } }
        }
    } $fixture

    function Test-Transactions([byte[]]$Original, $Manifest, [string]$Name) {
        $folder = Join-Path $testRoot $Name
        New-Item -ItemType Directory -Path $folder | Out-Null
        $dll = Join-Path $folder 'GameAssembly.dll'
        $cache = Join-Path $folder 'owned_cosmetics.json'
        [IO.File]::WriteAllBytes($dll, $Original)
        [IO.File]::WriteAllText($cache, 'fixture inventory: do not alter')
        $cacheHash = (Get-FileHash -LiteralPath $cache).Hash
        & $module { param($Value) $script:TestManifest = $Value } $Manifest
        Install-OfflineFix $folder
        Assert-True ((Get-FixStatus $folder).Status -eq 'installed') 'Installation did not produce the supported patched hash.'
        $backup = Join-Path $folder '.le-offline-fixes\GameAssembly.original.dll'
        Assert-True ((Get-FileHash -LiteralPath $backup).Hash -eq $Manifest.original_sha256) 'Original backup was not preserved.'
        Install-OfflineFix $folder
        Assert-True ((Get-FileHash -LiteralPath $backup).Hash -eq $Manifest.original_sha256) 'Repeated installation damaged the backup.'
        Restore-OfflineFix $folder
        Restore-OfflineFix $folder
        Assert-True ((Get-FixStatus $folder).Status -eq 'original-supported') 'Rollback did not restore the original.'
        Assert-True ((Get-FileHash -LiteralPath $cache).Hash -eq $cacheHash) 'Cosmetic cache was changed.'
        $script:passed++

        [IO.File]::WriteAllBytes($backup, [byte[]](1, 2, 3))
        Expect-Error { Install-OfflineFix $folder } 'Existing backup'
        Assert-True ((Get-FileHash -LiteralPath $dll).Hash -eq $Manifest.original_sha256) 'Invalid backup led to a DLL write.'
        [IO.File]::WriteAllBytes($backup, $Original)
        [IO.File]::WriteAllBytes($dll, [byte[]](1, 2, 3))
        Expect-Error { Install-OfflineFix $folder } 'Unsupported DLL'
        Expect-Error { Restore-OfflineFix $folder } 'Unrecognized current DLL'
        [IO.File]::WriteAllBytes($dll, $Original)
        & $module { $script:TestGameRunning = $true }
        Expect-Error { Install-OfflineFix $folder } 'Close Last Epoch'
        Expect-Error { Restore-OfflineFix $folder } 'Close Last Epoch'
        Assert-True ((Get-FileHash -LiteralPath $dll).Hash -eq $Manifest.original_sha256) 'Running-game refusal modified the DLL.'
        & $module { $script:TestGameRunning = $false }
    }

    Test-Transactions $source $fixture 'synthetic'
    if ($OriginalDll) {
        $realManifest = Get-Content -LiteralPath (Join-Path $repository 'src\patch-1.5.1.json') -Raw | ConvertFrom-Json
        [byte[]]$realOriginal = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $OriginalDll).ProviderPath)
        [byte[]]$realPatched = New-PatchedBytes $realOriginal $realManifest
        Assert-True ((Get-BytesHash $realPatched) -eq $realManifest.patched_sha256) 'Real patched hash does not match the game-validated DLL.'
        $passed++
        Test-Transactions $realOriginal $realManifest 'real-copy'
    }
    Write-Host "PASS: $passed checks, including patch integrity, installation and rollback." -ForegroundColor Green
} finally {
    # Delete only the exact unique temporary test folder created above.
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved -ne $testRoot -or -not $resolved.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^le-offline-fixes-tests-[0-9a-f]{32}$') { throw 'Unsafe temporary cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
    Remove-Module OfflineFix
}
