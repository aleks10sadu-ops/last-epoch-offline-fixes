function Get-AdaptiveManifest([byte[]]$Source) {
    if (-not ('LastEpochOfflineFix.PortableImage' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'AdaptivePatch.cs')
    }
    $template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'adaptive-template.json') -Raw | ConvertFrom-Json
    if ($template.schema -ne 1 -or $template.architecture -ne 'windows-x64-il2cpp') { throw 'Unsupported adaptive template.' }
    $image = New-Object LastEpochOfflineFix.PortableImage -ArgumentList (,$Source)
    $found = @{}
    foreach ($function in $template.functions) {
        $rva = $image.FindFunction($function.name, $function.length,
            (ConvertFrom-Hex $function.anchor), $function.anchor_offset,
            [int[]]$function.mask_ranges, $function.normalized_sha256)
        $found[$function.name] = $rva
        foreach ($reference in $function.internal_refs) {
            if ($image.Relative($rva, $reference.displacement, $reference.width, $reference.next) -ne
                $rva + $reference.target_offset) { throw "Changed internal control flow in $($function.name)." }
        }
    }
    if ($found.Count -ne 5 -or @($found.Values | Select-Object -Unique).Count -ne 5) { throw 'Invalid adaptive function set.' }
    foreach ($property in $template.links.PSObject.Properties) {
        $link = $property.Value
        foreach ($reference in $link.refs) {
            if ($image.Relative($found[$link.function], $reference.displacement, $reference.width, $reference.next) -ne
                $found[$link.target_function]) { throw "Changed function relationship: $($property.Name)." }
        }
    }
    $targets = @{ constructor = $found.constructor; initialize = $found.initialize; string_new = $image.Export('il2cpp_string_new') }
    foreach ($property in $template.globals.PSObject.Properties) {
        $slot = -1
        foreach ($reference in $property.Value) {
            $value = $image.Relative($found.stock, $reference.displacement, $reference.width, $reference.next)
            if ($slot -ge 0 -and $slot -ne $value) { throw "Stock identity references disagree: $($property.Name)." }
            $image.WritableSlot($value)
            $slot = $value
        }
        $targets[$property.Name] = $slot
    }
    if (@($targets.name, $targets.title, $targets.platform | Select-Object -Unique).Count -ne 3) { throw 'Stock identity slots overlap.' }
    [byte[]]$prefix = ConvertFrom-Hex $template.wrapper_prefix_hex
    $sectionRva = $image.SectionRva()
    foreach ($reference in $template.wrapper_refs) {
        $image.SetRelative($prefix, $reference.displacement, $reference.next, $sectionRva, $targets[$reference.target])
    }
    [int[]]$branches = @($template.cache_branches | ForEach-Object { $found.cache + $_ })
    foreach ($branch in $branches) { $image.Branch($branch, ($found.cache + $template.cache_throw_offset)) }
    $callSite = $found.bypass + $template.links.constructor.refs[0].displacement - 1
    $generated = $image.Build($prefix, $callSite, $branches, ($found.cache + $template.cache_empty_offset),
        $template.wrapper_code_size, $template.wrapper_unwind_offset)
    # Convert CLR fields into the same manifest shape used by the fixed builder.
    $manifest = $generated | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $known = Get-FixManifest $manifest.original_sha256
    if ($known) { $manifest.game_version = $known.game_version; $manifest.build = $known.build }
    [byte[]]$verified = New-PatchedBytes $Source $manifest
    $null = $verified
    return $manifest
}

function Get-ResolvedManifest([string]$GameDirectory, [string]$SHA256) {
    $manifest = Get-FixManifest $SHA256
    if ($manifest) { return $manifest }
    $path = Join-Path $GameDirectory ('.le-offline-fixes\patch.' + $SHA256 + '.json')
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $cached = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($cached.schema -ne 1 -or -not $cached.adaptive -or $cached.patched_sha256 -ne $SHA256) { throw 'Invalid locally saved adaptive manifest.' }
        return $cached
    }
    return $null
}

function Save-AdaptiveManifest([string]$GameDirectory, $Manifest) {
    if (-not $Manifest.PSObject.Properties['adaptive'] -or -not $Manifest.adaptive) { return }
    $path = Join-Path $GameDirectory ('.le-offline-fixes\patch.' + $Manifest.patched_sha256 + '.json')
    if (-not (Test-Path -LiteralPath $path)) {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Manifest | ConvertTo-Json -Depth 12))
        $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
    $cached = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $source = [IO.File]::ReadAllBytes((Get-BackupPath $GameDirectory $Manifest))
    [byte[]]$check = New-PatchedBytes $source $cached
    if ((Get-BytesHash $check) -ne $Manifest.patched_sha256) { throw 'Cached adaptive patch verification failed.' }
}
