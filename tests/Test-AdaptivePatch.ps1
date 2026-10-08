[CmdletBinding()]
param([string]$Original151, [string]$Original152)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repository 'src\OfflineFix.psm1') -Force
$module = Get-Module OfflineFix
$passed = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++
}
function Expect-Error([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert-True ($null -ne $caught -and $caught -match $Pattern) "Unexpected error: $caught"
}

# CI can compile the portable analyzer and check malformed images without a game DLL.
Expect-Error { Get-AdaptiveManifest ([byte[]](1,2,3)) } 'Unsupported PE'
if (-not $Original151 -or -not $Original152) {
    Write-Host "PASS: $passed adaptive compilation / malformed-image check. Real-DLL checks require local copies."
    return
}
$template = Get-Content -LiteralPath (Join-Path $repository 'src\adaptive-template.json') -Raw | ConvertFrom-Json
[byte[]]$s151 = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Original151).ProviderPath)
[byte[]]$s152 = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Original152).ProviderPath)
foreach ($source in @($s151, $s152)) {
    $hash = Get-BytesHash $source
    $fixed = Get-FixManifest $hash
    $adaptive = Get-AdaptiveManifest $source
    Assert-True ($adaptive.patched_sha256 -eq $fixed.patched_sha256) 'Adaptive output differs from independently built fixed patch.'
    Assert-True ((Get-BytesHash (New-PatchedBytes $source $adaptive)) -eq $fixed.patched_sha256) 'Reconstruction differs from the fixed patch.'
    Assert-True ((Get-BytesHash $source) -eq $hash) 'Analysis mutated the source DLL.'
}
$image = New-Object LastEpochOfflineFix.PortableImage -ArgumentList (,$s151)
$found = @{}
foreach ($f in $template.functions) {
    $found[$f.name] = $image.FindFunction($f.name, $f.length,
        ([LastEpochOfflineFix.PortableImage]::Hex($f.anchor)), $f.anchor_offset, [int[]]$f.mask_ranges, $f.normalized_sha256)
}
[byte[]]$changed = $s151.Clone()
$p = $image.Offset($found.constructor, 1); $changed[$p] = $changed[$p] -bxor 1
Expect-Error { Get-AdaptiveManifest $changed } 'expected 1 exact function'
$changed = $s151.Clone(); $p = $image.Offset(($found.cache + 205), 1); $changed[$p] = $changed[$p] -bxor 1
Expect-Error { Get-AdaptiveManifest $changed } 'internal control flow'
$changed = $s151.Clone(); $p = $image.Offset(($found.bypass + $template.links.constructor.refs[0].displacement), 1); $changed[$p] = $changed[$p] -bxor 4
Expect-Error { Get-AdaptiveManifest $changed } 'function relationship'
$changed = $s151.Clone(); $p = $image.Offset(($found.stock + $template.globals.name[0].displacement), 1); $changed[$p] = $changed[$p] -bxor 8
Expect-Error { Get-AdaptiveManifest $changed } 'identity references disagree'
$changed = $s151.Clone(); $pe = [BitConverter]::ToInt32($changed,60); $changed[$pe+4] = 0x4c
Expect-Error { Get-AdaptiveManifest $changed } 'Windows x64'
$changed = $s151.Clone(); $optional = $pe+24
$header = $optional + [BitConverter]::ToUInt16($changed,$pe+20) + 40*[BitConverter]::ToUInt16($changed,$pe+6)
$changed[$header] = 1
Expect-Error { Get-AdaptiveManifest $changed } 'header slot is occupied'

# Duplicate the small initializer into a different, same-sized runtime function.
$changed = $s151.Clone(); $duplicate = -1
for ($p=$image.ExceptionOffset; $p -lt $image.ExceptionOffset+$image.ExceptionSize; $p+=12) {
    $begin = [BitConverter]::ToInt32($s151,$p); $end = [BitConverter]::ToInt32($s151,$p+4)
    if ($end-$begin -eq 19 -and $begin -ne $found.initialize) { $duplicate=$begin; break }
}
Assert-True ($duplicate -ge 0) 'Ambiguous-match fixture could not be prepared.'
[Array]::Copy($s151, $image.Offset($found.initialize,19), $changed, $image.Offset($duplicate,19), 19)
Expect-Error { Get-AdaptiveManifest $changed } 'found 2'

# Mutate an unrelated DOS-stub byte to exercise an unlisted input hash.
$changed = $s152.Clone(); $changed[80] = $changed[80] -bxor 1
$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $temporaryBase ('le-offline-adaptive-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    # Only the in-memory test module ignores the running game. Production has no bypass.
    & $module { function script:Get-Process { param($Name, $ErrorAction) } }
    $dll = Join-Path $testRoot 'GameAssembly.dll'
    [IO.File]::WriteAllBytes($dll,$changed)
    $originalHash = Get-BytesHash $changed
    Assert-True ((Get-FixStatus $testRoot).Status -eq 'adaptive-compatible') 'Unlisted unchanged code was not recognized.'
    Install-OfflineFix $testRoot
    $status = Get-FixStatus $testRoot
    Assert-True ($status.Status -eq 'installed') 'Cached adaptive patch was not recognized.'
    $cachedPath = Join-Path $testRoot ('.le-offline-fixes\patch.'+$status.SHA256+'.json')
    $cached = Get-Content -LiteralPath $cachedPath -Raw | ConvertFrom-Json
    Assert-True ($cached.original_sha256 -eq $originalHash -and $cached.patched_sha256 -eq $status.SHA256) 'Adaptive recovery manifest was not saved correctly.'
    Install-OfflineFix $testRoot
    Restore-OfflineFix $testRoot
    Assert-True ((Get-FileHash -LiteralPath $dll).Hash -eq $originalHash) 'Adaptive rollback failed to restore the exact unlisted original.'
    Restore-OfflineFix $testRoot
    # Use a clearly malformed file to check that fallback refusal performs no write.
    [IO.File]::WriteAllBytes($dll,[byte[]](1,2,3))
    $rejectedHash = (Get-FileHash -LiteralPath $dll).Hash
    Expect-Error { Install-OfflineFix $testRoot } 'Unsupported DLL'
    Assert-True ((Get-FileHash -LiteralPath $dll).Hash -eq $rejectedHash) 'Refused installation changed the DLL.'
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved -ne $testRoot -or -not $resolved.StartsWith($temporaryBase,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^le-offline-adaptive-tests-[0-9a-f]{32}$') { throw 'Unsafe temporary cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "PASS: $passed adaptive matching, refusal, installation and rollback checks." -ForegroundColor Green
