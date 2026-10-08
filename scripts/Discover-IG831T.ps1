[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [Parameter(Mandatory = $true)]
    [string]$SnapshotPath,
    [ValidatePattern('^[0-9A-Fa-f]{4}$')]
    [string]$VendorId = '2CA3',
    [ValidatePattern('^[0-9A-Fa-f]{4}$')]
    [string]$ProductId = '4009'
)

$ErrorActionPreference = 'Stop'
$VendorId = $VendorId.ToUpperInvariant()
$ProductId = $ProductId.ToUpperInvariant()
$targetPattern = "USB\VID_$VendorId&PID_$ProductId"
$limitations = [System.Collections.Generic.List[string]]::new()
$privateDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$publicPath = [System.IO.Path]::GetFullPath($SnapshotPath)
[System.IO.Directory]::CreateDirectory($privateDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($publicPath)) | Out-Null
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Write-PrivateResult {
    param([string]$Name, [string]$Content)
    [System.IO.File]::WriteAllText((Join-Path $privateDirectory $Name), $Content, $utf8)
}

function Invoke-PnpEnumeration {
    param([string[]]$Arguments)
    $result = & pnputil.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "PnPUtil enumeration failed ($LASTEXITCODE): $($result -join ' ')"
    }
    return ($result -join "`n")
}

function Read-DeviceProperty {
    param([string]$Content, [string]$Name)
    $propertyPattern = '(?m)^\s{4}' + [regex]::Escape($Name) + ' \[[^\]]+\]:\r?\n(?<values>(?:[ \t]{8}[^\r\n]+(?:\r?\n|$))+)'
    $propertyMatch = [regex]::Match($Content, $propertyPattern)
    if (-not $propertyMatch.Success) {
        return @()
    }
    return @($propertyMatch.Groups['values'].Value.TrimEnd() -split '\r?\n' | ForEach-Object { $_.Trim() })
}

function Read-UnsignedProperty {
    param([string]$Content, [string]$Name)
    $value = @(Read-DeviceProperty -Content $Content -Name $Name)
    if ($value.Count -eq 0) { return $null }
    if ($value[0] -match '^0x([0-9a-fA-F]+)') {
        return [Convert]::ToUInt32($Matches[1], 16)
    }
    if ($value[0] -match '^\d+$') { return [uint32]$value[0] }
    return $null
}

function Read-FirstProperty {
    param([string]$Content, [string]$Name)
    $values = @(Read-DeviceProperty -Content $Content -Name $Name)
    if ($values.Count -gt 0) { return $values[0] }
    return $null
}

function Protect-InstanceId {
    param([string]$InstanceId)
    return ($InstanceId -replace '\\[^\\]+$', '\<redacted>')
}

try {
    $pnpDevices = Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object { $_.InstanceId -like "$targetPattern*" } |
        Select-Object Status, Class, FriendlyName, InstanceId
    Write-PrivateResult -Name 'get-pnpdevice.json' -Content (ConvertTo-Json -InputObject @($pnpDevices) -Depth 5)
} catch {
    $limitations.Add("Get-PnpDevice unavailable: $($_.Exception.Message)")
}

foreach ($className in @('Win32_PnPEntity', 'Win32_SerialPort')) {
    try {
        $cimDevices = Get-CimInstance -ClassName $className -ErrorAction Stop |
            Where-Object { $_.PNPDeviceID -like "$targetPattern*" } |
            Select-Object Name, DeviceID, PNPDeviceID, Status, ConfigManagerErrorCode, Service
        Write-PrivateResult -Name "$className.json" -Content (ConvertTo-Json -InputObject @($cimDevices) -Depth 5)
    } catch {
        $limitations.Add("${className} unavailable: $($_.Exception.Message)")
    }
}

$listing = Invoke-PnpEnumeration -Arguments @('/enum-devices', '/connected', '/bus', 'USB', '/deviceids', '/services')
$instancePattern = '(?im)^[^\r\n]*?\b(?<id>USB\\VID_' + $VendorId + '&PID_' + $ProductId + '(?:&MI_[0-9A-F]{2})?\\[^\s]+)[ \t]*$'
$instanceIds = @([regex]::Matches($listing, $instancePattern) |
    ForEach-Object { $_.Groups['id'].Value } | Sort-Object -Unique)
if ($instanceIds.Count -eq 0) {
    throw 'No matching connected USB device was found. No snapshot was written.'
}

$parentIds = @($instanceIds | Where-Object { $_ -notmatch '&MI_' })
if ($parentIds.Count -ne 1) {
    throw 'Expected exactly one matching USB parent. Disconnect other matching devices before retrying.'
}

$deviceRecords = @()
foreach ($instanceId in $instanceIds) {
    $raw = Invoke-PnpEnumeration -Arguments @('/enum-devices', '/instanceid', $instanceId, '/deviceids', '/services', '/properties', '/relations', '/drivers', '/interfaces')
    $interfaceNumber = if ($instanceId -match '&MI_([0-9A-Fa-f]{2})') { $Matches[1].ToUpperInvariant() } else { 'parent' }
    Write-PrivateResult -Name "device-$interfaceNumber.txt" -Content $raw
    $problemCode = Read-UnsignedProperty -Content $raw -Name 'DEVPKEY_Device_ProblemCode'
    $devNodeStatus = Read-UnsignedProperty -Content $raw -Name 'DEVPKEY_Device_DevNodeStatus'
    $status = if ($null -eq $problemCode) { 'Unknown' } elseif ($problemCode -ne 0) { 'Problem' } elseif ($null -ne $devNodeStatus -and ($devNodeStatus -band 8)) { 'Started' } else { 'Present' }
    $compatibleIds = @(Read-DeviceProperty -Content $raw -Name 'DEVPKEY_Device_CompatibleIds')
    $classCode = $null
    $subclassCode = $null
    $protocolCode = $null
    foreach ($compatibleId in $compatibleIds) {
        if ($compatibleId -match '^USB\\Class_([0-9A-Fa-f]{2})&SubClass_([0-9A-Fa-f]{2})&Prot_([0-9A-Fa-f]{2})$') {
            $classCode = $Matches[1].ToUpperInvariant()
            $subclassCode = $Matches[2].ToUpperInvariant()
            $protocolCode = $Matches[3].ToUpperInvariant()
            break
        }
    }
    $deviceRecords += [pscustomobject][ordered]@{
        number = $interfaceNumber
        instanceId = Protect-InstanceId -InstanceId $instanceId
        description = Read-FirstProperty -Content $raw -Name 'DEVPKEY_Device_DeviceDesc'
        busReportedDescription = Read-FirstProperty -Content $raw -Name 'DEVPKEY_Device_BusReportedDeviceDesc'
        hardwareIds = @(Read-DeviceProperty -Content $raw -Name 'DEVPKEY_Device_HardwareIds')
        compatibleIds = $compatibleIds
        classCode = $classCode
        subclassCode = $subclassCode
        protocolCode = $protocolCode
        status = $status
        problemCode = $problemCode
        problemStatus = Read-FirstProperty -Content $raw -Name 'DEVPKEY_Device_ProblemStatus'
        driverService = Read-FirstProperty -Content $raw -Name 'DEVPKEY_Device_Service'
        driverInf = Read-FirstProperty -Content $raw -Name 'DEVPKEY_Device_DriverInfPath'
    }
}

$serialApiNames = @([System.IO.Ports.SerialPort]::GetPortNames())
$portListing = Invoke-PnpEnumeration -Arguments @('/enum-devices', '/connected', '/class', 'Ports', '/deviceids')
$modemListing = Invoke-PnpEnumeration -Arguments @('/enum-devices', '/connected', '/class', 'Modem', '/deviceids')
Write-PrivateResult -Name 'ports-and-modems.txt' -Content (($serialApiNames -join "`n") + "`n" + $portListing + "`n" + $modemListing)
$targetPortBlocks = @((($portListing + "`n`n" + $modemListing) -split '(?:\r?\n){2,}') |
    Where-Object { $_ -match [regex]::Escape($targetPattern) })
$targetPortNames = @([regex]::Matches(($targetPortBlocks -join "`n"), '\bCOM\d+\b') |
    ForEach-Object { $_.Value } | Sort-Object -Unique)
$serialAssessment = if ($serialApiNames.Count -eq 0 -and $targetPortBlocks.Count -eq 0) {
    'No COM names from .NET and no matching connected Ports/Modem nodes; no accessible target serial port identified.'
} else {
    'Only names associated with matching Ports/Modem nodes are listed. No ports were opened; accessibility and protocol are unverified.'
}

$parent = $deviceRecords | Where-Object { $_.number -eq 'parent' }
$interfaces = @($deviceRecords | Where-Object { $_.number -ne 'parent' } | Sort-Object number)
if ($parent.hardwareIds.Count -eq 0 -or $interfaces.Count -eq 0 -or
    @($interfaces | Where-Object { $_.hardwareIds.Count -eq 0 -or $null -eq $_.classCode -or $null -eq $_.problemCode }).Count -gt 0) {
    throw 'PnP properties could not be parsed completely. Inspect private raw results; no snapshot was written.'
}
$revision = $null
foreach ($hardwareId in $parent.hardwareIds) {
    if ($hardwareId -match '&REV_([0-9A-Fa-f]{4})') { $revision = $Matches[1].ToUpperInvariant(); break }
}
$limitations.Add('PnP compatible IDs are not complete USB descriptors; endpoints, alternate settings and functional descriptors were not read.')
$limitations.Add('No unplug/replug baseline was taken; the target is associated with the user-reported IG831T, not a verified chip identity.')
$limitations.Add('Vendor-specific class does not prove AT, QMI, MBIM, RNDIS, voice or data support. No device handles or serial ports were opened.')
$snapshot = [ordered]@{
    schemaVersion = 1
    capturedAt = [DateTimeOffset]::UtcNow.ToString('o')
    source = 'Windows PnPUtil read-only enumeration'
    vendorId = $VendorId
    productId = $ProductId
    bcdDevice = $revision
    identityAssessment = 'User-reported IG831T candidate; Windows bus description is not a chip identification.'
    device = $parent
    interfaces = $interfaces
    serialPortNames = $targetPortNames
    serialPortAssessment = $serialAssessment
    limitations = @($limitations)
}
[System.IO.File]::WriteAllText($publicPath, (ConvertTo-Json -InputObject $snapshot -Depth 8), $utf8)
Write-Output "Read-only enumeration complete: $VendorId`:$ProductId; $($interfaces.Count) interface nodes; $($targetPortNames.Count) associated COM names."
Write-Output "Sanitized snapshot: $publicPath"
Write-Output "Private raw evidence (do not publish): $privateDirectory"
