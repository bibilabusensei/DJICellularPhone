[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DriverRoot,
    [Parameter(Mandatory = $true)]
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $DriverRoot).Path.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'DriverRoot must be a directory.' }
$reports = [System.Collections.Generic.List[object]]::new()

function Remove-InfComment {
    param([string]$Line)
    $quoted = $false
    for ($offset = 0; $offset -lt $Line.Length; $offset++) {
        if ($Line[$offset] -eq '"') { $quoted = -not $quoted }
        if ($Line[$offset] -eq ';' -and -not $quoted) { return $Line.Substring(0, $offset).Trim() }
    }
    return $Line.Trim()
}

foreach ($inf in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.inf') {
    $sections = @{}
    $section = ''
    $lineNumber = 0
    foreach ($rawLine in [System.IO.File]::ReadAllLines($inf.FullName)) {
        $lineNumber++
        $line = Remove-InfComment -Line $rawLine
        if ($line -match '^\[(?<section>[^\]]+)\]$') {
            $section = $Matches['section']
            if (-not $sections.ContainsKey($section)) {
                $sections[$section] = [System.Collections.Generic.List[object]]::new()
            }
        } elseif ($line -and $section) {
            $sections[$section].Add([pscustomobject]@{ number = $lineNumber; content = $line })
        }
    }
    $modelSections = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($manufacturer in $sections['Manufacturer']) {
        if ($manufacturer.content -notmatch '^[^=]+=(?<value>.+)$') { continue }
        $parts = @($Matches['value'].Split(',') | ForEach-Object { $_.Trim() })
        if ($parts.Count -eq 1) {
            $modelSections.Add($parts[0]) | Out-Null
        } else {
            foreach ($decoration in $parts[1..($parts.Count - 1)]) {
                $modelSections.Add("$($parts[0]).$decoration") | Out-Null
            }
        }
    }
    $models = [System.Collections.Generic.List[object]]::new()
    foreach ($modelSection in $modelSections) {
        foreach ($model in $sections[$modelSection]) {
            if ($model.content -notmatch '^[^=]+=(?<value>.+)$') { continue }
            $parts = @($Matches['value'].Split(',') | ForEach-Object { $_.Trim() })
            if ($parts.Count -lt 2) { continue }
            foreach ($identifier in $parts[1..($parts.Count - 1)]) {
                if ($identifier -notmatch '^USB\\VID_2CA3&PID_[0-9A-Fa-f]{4}(?:&[^\s,]+)*$') { continue }
                $models.Add([ordered]@{
                    section = $modelSection
                    line = $model.number
                    installSection = $parts[0]
                    identifier = $identifier.ToUpperInvariant()
                    targetIdCandidate = $identifier -match '^USB\\VID_2CA3&PID_4009(?:&|$)'
                })
            }
        }
    }
    $version = @{}
    foreach ($entry in $sections['Version']) {
        if ($entry.content -match '^(?<key>[^=]+)=(?<value>.+)$') {
            $version[$Matches['key'].Trim()] = $Matches['value'].Trim().Trim('"')
        }
    }
    $catalogs = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @($version.Keys | Where-Object { $_ -match '^CatalogFile(?:\.|$)' } | Sort-Object)) {
        $name = $version[$key]
        if ([System.IO.Path]::GetFileName($name) -ne $name) { throw 'CatalogFile must be a plain filename.' }
        $catalogPath = Join-Path $inf.DirectoryName $name
        $signature = $null
        $exists = Test-Path -LiteralPath $catalogPath -PathType Leaf
        if ($exists) { $signature = Get-AuthenticodeSignature -LiteralPath $catalogPath }
        $catalogs.Add([ordered]@{
            directive = $key
            name = $name
            present = $exists
            authenticodeStatus = if ($signature) { $signature.Status.ToString() } else { 'Missing' }
            signer = if ($signature -and $signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
            catalogMembershipVerified = $false
        })
    }
    $reports.Add([ordered]@{
        relativePath = $inf.FullName.Substring($root.Length + 1).Replace('\', '/')
        sha256 = (Get-FileHash -LiteralPath $inf.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        class = $version['Class']
        driverVersion = $version['DriverVer']
        modelSections = @($modelSections | Sort-Object)
        usbModels = @($models.ToArray())
        targetIdCandidates = @($models | Where-Object { $_.targetIdCandidate })
        catalogs = @($catalogs.ToArray())
    })
}
if ($reports.Count -eq 0) { throw 'No INF files found; no report written.' }
$report = [ordered]@{
    schemaVersion = 1
    collectedAtUTC = [DateTime]::UtcNow.ToString('o')
    target = 'USB\VID_2CA3&PID_4009'
    infCount = $reports.Count
    targetCandidateInfCount = @($reports | Where-Object { $_.targetIdCandidates.Count -gt 0 }).Count
    packages = @($reports.ToArray())
    limitations = @(
        'Read-only file audit; no installer, driver binding, device communication, registry change or network connection.',
        'Only vendor 2CA3 active USB identifiers in model sections explicitly declared by Manufacturer are reported. This is not a complete Windows INF evaluator.',
        'A matching identifier is only a candidate; OS decorations, installation sections, protocol compatibility and catalog membership still require verification.',
        'Authenticode status alone does not establish that an INF or SYS belongs to the catalog; use SignTool separately.',
        'No package root, device serial, instance suffix, SIM identifier or user account path is included.'
    )
}
$path = [System.IO.Path]::GetFullPath($ReportPath)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path)) | Out-Null
[System.IO.File]::WriteAllText($path, ($report | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
Write-Output "Audited $($reports.Count) INF files; target ID candidates: $($report.targetCandidateInfCount). Report: $path"
