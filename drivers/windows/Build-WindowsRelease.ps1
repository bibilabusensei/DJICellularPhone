[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$OutputDirectory, [string]$Commit = 'local-validation')

$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Release output already exists; refusing to overwrite.' }
[IO.Directory]::CreateDirectory($output) | Out-Null
$stage = Join-Path $output 'staging'
[IO.Directory]::CreateDirectory($stage) | Out-Null
$toolFiles = @('Get-IG831TDriverPackage.ps1','Install-IG831TDriver.ps1','IG831TPackage.cs','IG831TDeviceInstall.cs','DriverPackage.json','Validate-WindowsTools.ps1','RELEASE-NOTES.md')
foreach ($file in $toolFiles) { [IO.File]::Copy((Join-Path $PSScriptRoot $file), (Join-Path $stage $file), $false) }
[IO.File]::Copy((Join-Path $PSScriptRoot 'COMPATIBILITY.md'), (Join-Path $stage 'README.md'), $false)
$diagnostics = Join-Path $stage 'diagnostics'
[IO.Directory]::CreateDirectory($diagnostics) | Out-Null
foreach ($file in @('Get-IG831TNetworkReadiness.ps1','Read-IG831TATStatus.ps1','Test-IG831TInternet.ps1','IG831TInterfaceProbe.cs')) {
    [IO.File]::Copy((Join-Path $repository ('scripts/' + $file)), (Join-Path $diagnostics $file), $false)
}
$manifest = [ordered]@{
    version = '0.1.0'
    commit = $Commit
    builtAtUTC = [DateTime]::UtcNow.ToString('o')
    platform = 'Windows 10/11 x64 only'
    experimental = $true
    nativeDriverRebuilt = $false
    vendorBinariesIncluded = $false
    officialVendorDownloadRequired = $true
    native4009InfMatch = $false
    testedOnOneWindowsPC = $true
    appleOrVoiceImplemented = $false
}
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $stage 'ReleaseManifest.json'), ($manifest | ConvertTo-Json -Depth 4), $utf8)
$zipName = 'DJICellularPhone-IG831T-Windows-Compatibility-Installer-v0.1.0.zip'
$zipPath = Join-Path $output $zipName
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName)) {
        $name = $file.FullName.Substring($stage.Length + 1).Replace('\','/')
        $entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
        $source = [IO.File]::OpenRead($file.FullName)
        $stream = $entry.Open()
        try { $source.CopyTo($stream) } finally { $source.Dispose(); $stream.Dispose() }
    }
} finally { $archive.Dispose() }
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    if (@($zip.Entries | Where-Object { $_.FullName -match '\.(sys|inf|cat|msi|exe|dll|cab)$' }).Count -gt 0) { throw 'Unexpected vendor/native binary in public Release.' }
    if (-not $zip.GetEntry('README.md') -or -not $zip.GetEntry('Install-IG831TDriver.ps1') -or
        -not $zip.GetEntry('Get-IG831TDriverPackage.ps1') -or -not $zip.GetEntry('ReleaseManifest.json') -or
        -not $zip.GetEntry('diagnostics/IG831TInterfaceProbe.cs')) { throw 'Release ZIP is missing required standalone files.' }
} finally { $zip.Dispose() }
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'), ($hash + '  ' + $zipName + "`n"), $utf8)
[IO.File]::Copy((Join-Path $PSScriptRoot 'RELEASE-NOTES.md'), (Join-Path $output 'RELEASE-NOTES.md'), $false)
Write-Output ('Public compatibility installer ZIP verified: ' + $zipName)
Write-Output ('SHA256: ' + $hash)
