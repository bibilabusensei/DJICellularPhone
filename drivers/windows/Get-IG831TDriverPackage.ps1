[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [string]$ArchivePath,
    [switch]$DownloadFromOfficialSource,
    [switch]$AcknowledgeVendorTerms
)

$ErrorActionPreference = 'Stop'
if (-not $AcknowledgeVendorTerms) { throw 'Review the vendor terms and explicitly acknowledge lawful personal use before obtaining the package.' }
if ([bool]$ArchivePath -eq [bool]$DownloadFromOfficialSource) { throw 'Choose one local audited ZIP or the explicit official-download switch.' }
if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess -or
    [Environment]::OSVersion.Version.Major -lt 10 -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'This tool only supports 64-bit PowerShell on Windows 10/11 x64. ARM64 and x86 installations are not validated.'
}
$destinationPath = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destinationPath) { throw 'Destination already exists; no files will be overwritten.' }
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'DriverPackage.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.files.Count -ne 8) { throw 'Unexpected package manifest.' }
$parent = [IO.Path]::GetDirectoryName($destinationPath)
if (-not $parent -or $destinationPath.Length -gt 160) { throw 'Choose a short, non-root destination path.' }
[IO.Directory]::CreateDirectory($parent) | Out-Null
$cache = Join-Path $parent ('ig831t-cache-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($cache) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)

function Confirm-Hash([string]$Path, [string]$Expected) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
        throw ('Original package hash differs: ' + [IO.Path]::GetFileName($Path))
    }
}

try {
    if ($DownloadFromOfficialSource) {
        $archive = Join-Path $cache 'official-driver.zip'
        $uri = [Uri]$manifest.source
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'www.quectel.com') { throw 'Only the pinned HTTPS vendor source is allowed.' }
        $oldProtocols = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $oldProtocols -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $uri.AbsoluteUri -OutFile $archive -UseBasicParsing -MaximumRedirection 3 -TimeoutSec 120
        } finally { [Net.ServicePointManager]::SecurityProtocol = $oldProtocols }
    } else { $archive = [IO.Path]::GetFullPath($ArchivePath) }
    if ((Get-Item -LiteralPath $archive).Length -ne $manifest.archiveBytes) { throw 'ZIP size differs from the audited release.' }
    Confirm-Hash $archive $manifest.archiveSha256
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not ('IG831TPackage' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'IG831TPackage.cs') }
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $members = @($zip.Entries | Where-Object { $_.FullName -ceq 'setup.exe' })
        if ($members.Count -ne 1 -or $members[0].Length -ne 9462612) { throw 'Unexpected setup container member.' }
        $stream = $members[0].Open()
        $buffer = [IO.MemoryStream]::new()
        try { $stream.CopyTo($buffer); $setup = $buffer.ToArray() }
        finally { $stream.Dispose(); $buffer.Dispose() }
    } finally { $zip.Dispose() }
    $msi = Join-Path $cache 'original.msi'
    [IO.File]::WriteAllBytes($msi, [IG831TPackage]::DecodeMsi($setup))
    Confirm-Hash $msi $manifest.msiSha256
    $cabinet = Join-Path $cache 'Data1.cab'
    [IG831TPackage]::ExtractCabinet($msi, $cabinet)
    Confirm-Hash $cabinet $manifest.cabinetSha256
    $raw = Join-Path $cache 'cabinet-files'
    $package = Join-Path $cache 'package'
    [IO.Directory]::CreateDirectory($raw) | Out-Null
    [IO.Directory]::CreateDirectory($package) | Out-Null
    foreach ($entry in $manifest.files) {
        if ($entry.cabinetKey -notmatch '^qc(?:wwan|ser)\.(?:inf|cat)$|^qcusb(?:wwan|ser)\.sys1?$') { throw 'Unexpected cabinet key.' }
        $output = & "$env:SystemRoot\System32\expand.exe" ('-F:' + $entry.cabinetKey) $cabinet $raw 2>&1
        if ($LASTEXITCODE -ne 0) { throw ('Windows cabinet extraction failed: ' + $entry.cabinetKey) }
        $sourceFile = Join-Path $raw $entry.cabinetKey
        Confirm-Hash $sourceFile $entry.sha256
        $relative = $entry.path.Replace('/', '\')
        $target = [IO.Path]::GetFullPath((Join-Path $package $relative))
        if (-not $target.StartsWith($package + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe destination path.' }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.File]::Copy($sourceFile, $target, $false)
    }
    foreach ($name in @('qcwwan.cat','qcser.cat')) {
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $package $name)
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Windows Hardware Compatibility Publisher(?:,|$)') {
            throw ('Original catalog trust check failed: ' + $name)
        }
    }
    $receipt = [ordered]@{
        schemaVersion = 1
        extractedAtUTC = [DateTime]::UtcNow.ToString('o')
        originalArchiveSha256 = $manifest.archiveSha256
        originalFiles = @($manifest.files | Select-Object path,sha256)
        vendorExecutablesOrMsiActionsRun = $false
        driversInstalled = $false
        binaryRedistributionPermissionConfirmed = $false
    }
    [IO.File]::WriteAllText((Join-Path $package 'Extraction.json'), ($receipt | ConvertTo-Json -Depth 6), $utf8)
    [IO.Directory]::Move($package, $destinationPath)
    Write-Output 'Extracted eight original signed driver files. No driver, firmware, SIM or system configuration was changed.'
    Write-Output 'Private extraction cache is retained beside the destination; do not publish vendor binaries without permission.'
} catch {
    Write-Error ('Extraction stopped without installing anything. Private cache: ' + $cache + '. ' + $_.Exception.Message)
    exit 1
}
