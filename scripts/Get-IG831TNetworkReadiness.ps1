[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [Parameter(Mandatory = $true)]
    [string]$SnapshotPath
)

$ErrorActionPreference = 'Stop'
$targetPattern = 'USB\VID_2CA3&PID_4009*'
$limitations = [Collections.Generic.List[string]]::new()
$nodes = [Collections.Generic.List[object]]::new()
$adapters = [Collections.Generic.List[object]]::new()
$deviceReadSucceeded = $false
$adapterReadSucceeded = $false
$privatePath = [IO.Path]::GetFullPath($OutputDirectory)
$publicPath = [IO.Path]::GetFullPath($SnapshotPath)
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.Directory]::CreateDirectory($privatePath) | Out-Null
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($publicPath)) | Out-Null

try {
    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.InstanceId -like $targetPattern })
    $deviceReadSucceeded = $true
    foreach ($device in $devices) {
        $interface = if ($device.InstanceId -match '&MI_([0-9A-F]{2})') { $Matches[1] } else { 'parent' }
        $problemCode = $null
        try {
            $problemCode = [int](Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_ProblemCode -ErrorAction Stop).Data
        } catch {
            $limitations.Add("Problem code unavailable for interface ${interface}.")
        }
        $nodes.Add([ordered]@{ interface = $interface; class = $device.Class; status = $device.Status; problemCode = $problemCode })
    }
} catch {
    $limitations.Add('PnP metadata read failed. A blocked query is not proof that the module is absent.')
}

try {
    $targetAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop |
        Where-Object { $_.PnPDeviceID -like $targetPattern })
    $adapterReadSucceeded = $true
    $privateAdapters = [Collections.Generic.List[object]]::new()
    foreach ($adapter in $targetAdapters) {
        $interface = if ($adapter.PnPDeviceID -match '&MI_([0-9A-F]{2})') { $Matches[1] } else { 'parent' }
        $configuration = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex -ErrorAction Stop
        $ipv4 = @(Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notmatch '^(127\.|169\.254\.|0\.)' })
        $gateways = @($configuration.IPv4DefaultGateway | Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' })
        $dnsServers = @($configuration.DNSServer | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
        $adapters.Add([ordered]@{
            interface = $interface
            status = $adapter.Status.ToString()
            hasPreferredIPv4 = $ipv4.Count -gt 0
            hasIPv4Gateway = $gateways.Count -gt 0
            hasConfiguredDns = $dnsServers.Count -gt 0
        })
        $privateAdapters.Add([ordered]@{
            pnpDeviceId = $adapter.PnPDeviceID
            alias = $adapter.Name
            interfaceIndex = $adapter.InterfaceIndex
            interfaceGuid = $adapter.InterfaceGuid.ToString()
            ipv4Addresses = @($ipv4 | ForEach-Object { $_.IPAddress })
            gateways = @($gateways | ForEach-Object { $_.NextHop })
            dnsServers = $dnsServers
        })
    }
    [IO.File]::WriteAllText((Join-Path $privatePath 'target-network-private.json'),
        (ConvertTo-Json -InputObject @($privateAdapters.ToArray()) -Depth 6), $utf8)
} catch {
    $adapterReadSucceeded = $false
    $limitations.Add('Target network metadata was not completely readable; readiness is unverified.')
}

$stage = if (-not $deviceReadSucceeded -or -not $adapterReadSucceeded) {
    'MetadataUnavailable'
} elseif ($nodes.Count -eq 0) {
    'DeviceNotFound'
} elseif ($adapters.Count -eq 0) {
    'NoTargetNetworkAdapter'
} elseif ($adapters.Count -ne 1) {
    'AmbiguousTargetAdapters'
} elseif ($adapters[0].status -ne 'Up' -or -not $adapters[0].hasPreferredIPv4 -or
    -not $adapters[0].hasIPv4Gateway -or -not $adapters[0].hasConfiguredDns) {
    'TargetNetworkNotReady'
} else {
    'ReadyForSeparateTrafficTest'
}
$report = [ordered]@{
    schemaVersion = 1
    collectedAtUTC = [DateTime]::UtcNow.ToString('o')
    target = 'USB\VID_2CA3&PID_4009'
    stage = $stage
    deviceMetadataReadSucceeded = $deviceReadSucceeded
    networkMetadataReadSucceeded = $adapterReadSucceeded
    nodes = @($nodes.ToArray())
    targetAdapters = @($adapters.ToArray())
    activeTrafficTestPerformed = $false
    internetVerified = $false
    limitations = @($limitations.ToArray()) + @(
        'Only current device and target adapter metadata were read. No driver, network setting, SIM or module operation was changed.',
        'No AT command, DNS query, ping, TCP/HTTPS request, connection activation or APN change was issued.',
        'Addresses, adapter GUIDs and instance suffixes stay private. No unrelated Wi-Fi, Ethernet or VPN adapter is used as a fallback.',
        'Link/IP/gateway/DNS configuration alone is not proof of cellular registration, a data bearer or Internet access.',
        'A separate traffic test requires SIM/antenna readiness and source-interface/route attribution.'
    )
}
[IO.File]::WriteAllText($publicPath, ($report | ConvertTo-Json -Depth 8), $utf8)
Write-Output "Network readiness: $stage; Internet not verified. Snapshot: $publicPath"
