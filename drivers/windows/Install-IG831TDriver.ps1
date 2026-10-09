[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Probe','Install')][string]$Mode = 'Probe',
    [ValidateSet('Network','Control')][string]$Interface = 'Network',
    [Parameter(Mandatory = $true)][string]$DriverDirectory,
    [string]$EvidenceDirectory,
    [switch]$AcknowledgeExperimentalBinding
)

$ErrorActionPreference = 'Stop'
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $PSScriptRoot 'diagnostics-private' }
if ($Mode -eq 'Install' -and -not $AcknowledgeExperimentalBinding) { throw 'Explicit experimental single-interface binding acknowledgement is required.' }
if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess -or
    [Environment]::OSVersion.Version.Major -lt 10 -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'Only 64-bit PowerShell on Windows 10/11 x64 is supported by this tool.'
}
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'DriverPackage.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$driver = [IO.Path]::GetFullPath($DriverDirectory)
if ($driver.Length -gt 200) { throw 'Move the extracted driver to a shorter path.' }
foreach ($entry in $manifest.files) {
    $file = [IO.Path]::GetFullPath((Join-Path $driver $entry.path))
    if (-not $file.StartsWith($driver + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) {
        throw ('An original package file changed or is missing: ' + $entry.path)
    }
}
$isControl = $Interface -eq 'Control'
$interfaceId = $(if ($isControl) { '02' } else { '04' })
$infName = $(if ($isControl) { 'qcser.inf' } else { 'qcwwan.inf' })
$serviceName = $(if ($isControl) { 'qcusbser' } else { 'qcusbwwan' })
$binaryPath = $(if ($isControl) { 'serial/amd64/qcusbser.sys' } else { 'ndis/6.2/amd64/qcusbwwan.sys' })
$expectedBinary = @($manifest.files | Where-Object { $_.path -eq $binaryPath })[0].sha256
$expectedInf = @($manifest.files | Where-Object { $_.path -eq $infName })[0].sha256
$signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $driver $infName.Replace('.inf','.cat'))
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Windows Hardware Compatibility Publisher(?:,|$)') {
    throw 'Original catalog trust verification failed. No security settings will be changed.'
}

function Read-TargetState {
    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.InstanceId -match '^USB\\VID_2CA3&PID_4009(?:&MI_[0-9A-F]{2})?\\' })
    foreach ($device in $devices) {
        $properties = @{}
        foreach ($property in @(Get-PnpDeviceProperty -InstanceId $device.InstanceId -ErrorAction Stop)) { $properties[$property.KeyName] = $property.Data }
        [pscustomobject][ordered]@{
            instanceId = $device.InstanceId
            interface = $(if ($device.InstanceId -match '&MI_([0-9A-F]{2})') { $Matches[1] } else { 'parent' })
            problemCode = $properties['DEVPKEY_Device_ProblemCode']
            driverInf = $properties['DEVPKEY_Device_DriverInfPath']
            service = $properties['DEVPKEY_Device_Service']
            class = $device.Class
            hardwareIds = @($properties['DEVPKEY_Device_HardwareIds'])
        }
    }
}

$before = @(Read-TargetState)
$parents = @($before | Where-Object { $_.interface -eq 'parent' })
$targets = @($before | Where-Object { $_.interface -eq $interfaceId })
if ($parents.Count -ne 1 -or $targets.Count -ne 1 -or $before.Count -ne 6 -or
    $parents[0].service -ne 'usbccgp' -or $parents[0].problemCode -ne 0 -or
    $targets[0].hardwareIds -notcontains ('USB\VID_2CA3&PID_4009&MI_' + $interfaceId)) {
    throw 'Expected one IG831T, a healthy unchanged USB parent and exactly five function interfaces; no changes were made.'
}
$target = $targets[0]
$installedBinary = Join-Path $env:SystemRoot ('System32/drivers/' + $serviceName + '.sys')
$existingService = @(Get-CimInstance Win32_SystemDriver -Filter ("Name='" + $serviceName + "'") -ErrorAction Stop)
if ($existingService.Count -gt 0 -and (-not (Test-Path -LiteralPath $installedBinary) -or
    (Get-FileHash -LiteralPath $installedBinary).Hash.ToLowerInvariant() -ne $expectedBinary)) {
    throw 'Another version of this shared driver service exists; refusing to replace it.'
}
$report = [ordered]@{ mode=$Mode; interface=$interfaceId; collectedAtUTC=[DateTime]::UtcNow.ToString('o'); stage='Preflight'; deviceChanged=$false; internetVerified=$false }
if ($target.problemCode -eq 0 -and $target.service -eq $serviceName) {
    if ($target.driverInf -notmatch '^oem\d+\.inf$' -or
        (Get-FileHash -LiteralPath (Join-Path $env:SystemRoot ('INF/' + $target.driverInf))).Hash.ToLowerInvariant() -ne $expectedInf -or
        (Get-FileHash -LiteralPath $installedBinary).Hash.ToLowerInvariant() -ne $expectedBinary) { throw 'Installed driver content differs from the audited original package.' }
    $report.stage = 'AlreadyInstalledOriginalDriverNoChange'
    Write-Output ($report | ConvertTo-Json)
    return
}
if ($target.problemCode -ne 28 -or $target.service) { throw 'The selected interface is not unbound Code 28; refusing to replace an existing driver.' }
if (-not ('IG831TDeviceInstall' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'IG831TDeviceInstall.cs') }
$inf = Join-Path $driver $infName
$candidates = @([IG831TDeviceInstall]::Probe($target.instanceId, $inf) | Where-Object { $_.HardwareId -ieq ('USB\VID_2CA3&PID_4006&MI_' + $interfaceId) })
if ($candidates.Count -ne 1) { throw 'Expected one allowlisted signed-driver model; installation was not attempted.' }
$report.candidate = @($candidates | Select-Object HardwareId,Section,Description,Provider,Version)
if ($Mode -eq 'Probe') {
    $report.stage = 'ReadOnlyCandidateProbeComplete'
    Write-Output ($report | ConvertTo-Json -Depth 5)
    return
}
if (-not $PSCmdlet.ShouldProcess(('IG831T MI_' + $interfaceId), 'Stage one original signed INF and bind its old 4006 model to this 4009 interface only')) {
    $report.stage = 'InstallNotRequestedOrWhatIf'
    Write-Output ($report | ConvertTo-Json -Depth 5)
    return
}
$administrator = ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $administrator) { throw 'Open 64-bit Windows PowerShell as Administrator, then repeat the reviewed command. This tool does not auto-elevate.' }
$evidence = [IO.Path]::GetFullPath($EvidenceDirectory)
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$receiptPath = Join-Path $evidence ('install-MI' + $interfaceId + '-private.json')
if (Test-Path -LiteralPath $receiptPath) { throw 'A prior installation receipt exists; review it instead of repeating a failed or interrupted operation.' }
$utf8 = [Text.UTF8Encoding]::new($false)
$receipt = [ordered]@{ targetInstanceId=$target.instanceId; original=$before; originalArchiveSha256=$manifest.archiveSha256; stage='AboutToStage'; createdAtUTC=[DateTime]::UtcNow.ToString('o') }
function Save-Receipt { [IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 8), $utf8) }
try {
    $fresh = @(Read-TargetState)
    if (($fresh | Sort-Object instanceId | ConvertTo-Json -Depth 5 -Compress) -ne ($before | Sort-Object instanceId | ConvertTo-Json -Depth 5 -Compress)) {
        throw 'Device state changed during review; no driver was staged.'
    }
    Save-Receipt
    $staging = & "$env:SystemRoot\System32\pnputil.exe" /add-driver $inf 2>&1
    [IO.File]::WriteAllText((Join-Path $evidence ('staging-MI' + $interfaceId + '-private.txt')), ($staging | Out-String), $utf8)
    if ($LASTEXITCODE -ne 0) { throw ('Driver Store staging stopped: ' + $LASTEXITCODE) }
    $receipt.stage = 'AboutToBindOneInterface'
    Save-Receipt
    $binding = [IG831TDeviceInstall]::Bind($target.instanceId, $inf)
    $receipt.binding = $binding
    $receipt.stage = 'BindingReturned'
    Save-Receipt
    $report.deviceChanged = $true
    $report.binding = $binding
    if (-not $binding.Success) { throw ('Scoped driver binding failed: ' + $binding.Error) }
    $after = @(Read-TargetState)
    $receipt.after = $after
    $othersBefore = @($before | Where-Object { $_.interface -ne $interfaceId } | Sort-Object instanceId | Select-Object instanceId,driverInf,service,class)
    $othersAfter = @($after | Where-Object { $_.interface -ne $interfaceId } | Sort-Object instanceId | Select-Object instanceId,driverInf,service,class)
    $report.otherInterfaceBindingsUnchanged = (ConvertTo-Json -InputObject $othersBefore -Compress) -eq (ConvertTo-Json -InputObject $othersAfter -Compress)
    if (-not $report.otherInterfaceBindingsUnchanged) { throw 'Another interface binding changed; stop and review the private receipt.' }
    if ($binding.NeedReboot) { $report.stage = 'RestartRequiredNoAutomaticRestart'; $receipt.stage=$report.stage; Save-Receipt; Write-Output ($report | ConvertTo-Json -Depth 5); return }
    $verified = @($after | Where-Object { $_.instanceId -eq $target.instanceId })
    if ($verified.Count -ne 1 -or $verified[0].problemCode -ne 0 -or $verified[0].service -ne $serviceName -or
        $verified[0].driverInf -notmatch '^oem\d+\.inf$' -or
        (Get-FileHash -LiteralPath (Join-Path $env:SystemRoot ('INF/' + $verified[0].driverInf))).Hash.ToLowerInvariant() -ne $expectedInf -or
        (Get-FileHash -LiteralPath $installedBinary).Hash.ToLowerInvariant() -ne $expectedBinary) {
        throw 'Installation returned success but the target driver was not independently verified.'
    }
    $report.stage = 'OriginalDriverStartedNotInternetProof'
    $receipt.stage = $report.stage
    Save-Receipt
    Write-Output ($report | ConvertTo-Json -Depth 5)
} catch {
    $receipt.stage = 'StoppedWithErrorReviewBeforeRetry'
    $receipt.error = $_.Exception.ToString()
    Save-Receipt
    throw
}
