[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
foreach ($file in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw ($errors | Out-String) }
    Write-Output ('PASS PowerShell syntax: ' + $file.Name)
}
foreach ($file in @('IG831TPackage.cs','IG831TDeviceInstall.cs')) {
    Add-Type -Path (Join-Path $PSScriptRoot $file)
    Write-Output ('PASS C# compile: ' + $file)
}
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'DriverPackage.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.files.Count -ne 8 -or $manifest.native4009InfMatch -or $manifest.binaryRedistributionPermissionConfirmed) { throw 'Unexpected manifest claims.' }
$paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $manifest.files) {
    if ($entry.sha256 -notmatch '^[0-9a-f]{64}$' -or -not $paths.Add($entry.path) -or
        $entry.path -notmatch '^(qc(?:wwan|ser)\.(?:inf|cat)|ndis/6\.2/(?:amd64|i386)/qcusbwwan\.sys|serial/(?:amd64|i386)/qcusbser\.sys)$') {
        throw 'Invalid or duplicate allowlisted driver file.'
    }
}
Write-Output 'PASS eight-file package manifest'
$rejected = $false
try { [IG831TPackage]::DecodeMsi([byte[]]@(77,90,0,0)) | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'An unaudited container was accepted.' }
Write-Output 'PASS reject unaudited setup container'
$rejected = $false
try { [IG831TDeviceInstall]::Probe('USB\VID_0000&PID_0000\fixture', 'qcwwan.inf') | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'An unrelated device identity was accepted.' }
Write-Output 'PASS reject unrelated device before native access'
$temporary = Join-Path $env:TEMP ('ig831t-validation-' + [Guid]::NewGuid().ToString('N'))
foreach ($tool in @('Get-IG831TDriverPackage.ps1','Install-IG831TDriver.ps1')) {
    $rejected = $false
    try {
        if ($tool -eq 'Get-IG831TDriverPackage.ps1') {
            & (Join-Path $PSScriptRoot $tool) -Destination $temporary -DownloadFromOfficialSource | Out-Null
        } else {
            & (Join-Path $PSScriptRoot $tool) -Mode Install -DriverDirectory $temporary | Out-Null
        }
    } catch { $rejected = $true }
    if (-not $rejected -or (Test-Path -LiteralPath $temporary)) { throw ('Consent guard failed: ' + $tool) }
    Write-Output ('PASS explicit consent guard: ' + $tool)
}
$rejected = $false
try {
    & (Join-Path $PSScriptRoot 'Get-IG831TDriverPackage.ps1') -Destination $temporary -ArchivePath 'fixture.zip' -DownloadFromOfficialSource -AcknowledgeVendorTerms | Out-Null
} catch { $rejected = $true }
if (-not $rejected -or (Test-Path -LiteralPath $temporary)) { throw 'Ambiguous source guard failed.' }
Write-Output 'PASS reject ambiguous download/local sources'
Write-Output 'Validation complete. No download, driver installation, hardware query, AT command or Internet probe was performed.'
