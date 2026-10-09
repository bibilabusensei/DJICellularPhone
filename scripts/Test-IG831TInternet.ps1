[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)]
    [string]$RegistrationStatusPath,
    [Parameter(Mandatory = $true)]
    [string]$SnapshotPath,
    [switch]$AcknowledgeSmallTrafficTest
)

$ErrorActionPreference = 'Stop'
if (-not $AcknowledgeSmallTrafficTest) { throw 'Explicit small-traffic test acknowledgement is required.' }
$directory = [IO.Path]::GetFullPath($EvidenceDirectory)
$publicPath = [IO.Path]::GetFullPath($SnapshotPath)
[IO.Directory]::CreateDirectory($directory) | Out-Null
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($publicPath)) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$attempts = [Collections.Generic.List[object]]::new()
$privateAttempts = [Collections.Generic.List[object]]::new()
$report = [ordered]@{
    schemaVersion = 1
    collectedAtUTC = [DateTime]::UtcNow.ToString('o')
    target = 'USB\VID_2CA3&PID_4009&MI_04'
    stage = 'Preflight'
    homeRegistrationConfirmed = $false
    socketOutgoingInterfaceEnforced = $false
    applicationProxyUsed = $false
    otherAdapterFallbackAllowed = $false
    activeTrafficTestPerformed = $false
    internetVerified = $false
    attempts = @()
}

function Confirm-TargetRoute([string]$Destination) {
    $route = @(Find-NetRoute -InterfaceIndex $adapter.InterfaceIndex -LocalIPAddress $source -RemoteIPAddress $Destination -ErrorAction Stop)
    if ($route.Count -eq 0 -or @($route | Where-Object { $_.InterfaceIndex -ne $adapter.InterfaceIndex }).Count -ne 0) {
        throw 'The selected route is not exclusively attributed to the target interface.'
    }
}

try {
    $records = Get-Content -LiteralPath $RegistrationStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $status = @($records | Where-Object { $_.command -eq 'AT+CEREG?' })
    if ($status.Count -ne 1 -or $status[0].response -notmatch '\+CEREG:\s*\d+,\s*1(?:\s|,)' -or
        $status[0].response -notmatch '(?m)^OK\s*$') {
        throw 'Recent home-network EPS registration is required; roaming data is not permitted by this tool.'
    }
    $age = ([DateTime]::UtcNow - [DateTime]::Parse($status[0].collectedAtUTC).ToUniversalTime()).TotalSeconds
    if ($age -lt -30 -or $age -gt 300) { throw 'Registration status is stale or future-dated; requery before sending traffic.' }
    $report.homeRegistrationConfirmed = $true
    $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object { $_.PnPDeviceID -like 'USB\VID_2CA3&PID_4009&MI_04\*' })
    if ($adapters.Count -ne 1 -or $adapters[0].Status -ne 'Up') { throw 'One active target module adapter is required.' }
    $adapter = $adapters[0]
    $problem = (Get-PnpDeviceProperty -InstanceId $adapter.PnPDeviceID -KeyName DEVPKEY_Device_ProblemCode -ErrorAction Stop).Data
    $service = (Get-PnpDeviceProperty -InstanceId $adapter.PnPDeviceID -KeyName DEVPKEY_Device_Service -ErrorAction Stop).Data
    if ($problem -ne 0 -or $service -ne 'qcusbwwan') { throw 'Target driver identity or state differs from the verified NDIS binding.' }
    $addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.AddressState -eq 'Preferred' -and -not $_.SkipAsSource -and $_.IPAddress -notmatch '^(127\.|169\.254\.|0\.)' })
    if ($addresses.Count -ne 1) { throw 'Exactly one preferred target IPv4 source is required.' }
    $source = $addresses[0].IPAddress
    $ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop
    if ($ipInterface.WeakHostSend.ToString() -ne 'Disabled' -or $ipInterface.WeakHostReceive.ToString() -ne 'Disabled') {
        throw 'Weak-host mode prevents conservative path attribution; no settings were changed.'
    }
    $servers = @(Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
        ForEach-Object { $_.ServerAddresses } | Select-Object -Unique -First 2)
    if ($servers.Count -eq 0) { throw 'No target-configured IPv4 DNS server is available.' }
    $before = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction Stop
    Add-Type -Path (Join-Path $PSScriptRoot 'IG831TInterfaceProbe.cs')
    foreach ($hostName in @('example.com', 'www.microsoft.com')) {
        foreach ($server in $servers) {
            $attempt = [ordered]@{ host = $hostName; dnsSucceeded = $false; httpsSucceeded = $false; routeMatchesTarget = $false }
            $privateAttempt = [ordered]@{ host = $hostName; source = $source; dnsServer = $server; interfaceIndex = $adapter.InterfaceIndex }
            try {
                Confirm-TargetRoute $server
                $report.activeTrafficTestPerformed = $true
                $dns = [IG831TInterfaceProbe]::Resolve($source, $adapter.InterfaceIndex, $server, $hostName)
                if (-not $dns.SourceAddressMatches -or -not $dns.OutgoingInterfaceMatches) { throw 'DNS socket binding is not attributed to the target.' }
                $report.socketOutgoingInterfaceEnforced = $true
                $attempt.dnsSucceeded = $true
                $attempt.dnsResponseBytes = $dns.ResponseBytes
                $attempt.dnsSocketSourceAndInterfaceVerified = $true
                $privateAttempt.dnsAddresses = $dns.Addresses
                $destination = $dns.Addresses[0]
                Confirm-TargetRoute $destination
                $attempt.routeMatchesTarget = $true
                $https = [IG831TInterfaceProbe]::Head($source, $adapter.InterfaceIndex, $destination, $hostName)
                $privateAttempt.destination = $destination
                $privateAttempt.https = $https
                $attempt.httpStatus = $https.StatusCode
                $attempt.tlsProtocol = $https.TlsProtocol
                $attempt.tlsCertificateAndHostnameValidated = $true
                $attempt.httpsResponseHeaderBytes = $https.HeaderBytes
                $attempt.httpsSocketSourceAndInterfaceVerified = $https.SourceAddressMatches -and $https.OutgoingInterfaceMatches -and $https.RemoteAddressMatches
                $attempt.httpsSucceeded = $attempt.httpsSocketSourceAndInterfaceVerified -and $https.StatusCode -ge 200 -and $https.StatusCode -lt 400
            } catch {
                $attempt.failureType = $_.Exception.GetType().Name
                $privateAttempt.error = $_.Exception.ToString()
            }
            $attempts.Add($attempt)
            $privateAttempts.Add($privateAttempt)
            if ($attempt.httpsSucceeded) { break }
        }
        if (@($attempts.ToArray() | Where-Object { $_.httpsSucceeded }).Count -gt 0) { break }
    }
    $current = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object { $_.PnPDeviceID -eq $adapter.PnPDeviceID })
    if ($current.Count -ne 1 -or $current[0].InterfaceGuid -ne $adapter.InterfaceGuid -or $current[0].Status -ne 'Up') {
        throw 'Target identity or link changed during the test.'
    }
    $after = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction Stop
    $report.targetIdentityAndLinkStable = $true
    $report.targetReceivedBytesDelta = [long]$after.ReceivedBytes - [long]$before.ReceivedBytes
    $report.targetSentBytesDelta = [long]$after.SentBytes - [long]$before.SentBytes
    $report.targetCountersIncreased = $report.targetReceivedBytesDelta -gt 0 -and $report.targetSentBytesDelta -gt 0
    $report.internetVerified = $report.targetCountersIncreased -and @($attempts.ToArray() | Where-Object { $_.dnsSucceeded -and $_.httpsSucceeded -and $_.routeMatchesTarget }).Count -gt 0
    $report.stage = $(if ($report.internetVerified) { 'ModuleBoundDnsAndHttpsVerified' } else { 'TrafficVerificationFailed' })
} catch {
    $report.stage = 'StoppedWithError'
    $report.failureType = $_.Exception.GetType().Name
    $privateAttempts.Add([ordered]@{ preflightError = $_.Exception.ToString() })
}
$report.attempts = @($attempts.ToArray())
$report.completedAtUTC = [DateTime]::UtcNow.ToString('o')
$report.limitations = @(
    'Bound IPv4 UDP DNS and direct TCP/TLS HEAD requests only; no application proxy, default resolver or other adapter fallback.',
    'Only target-configured DNS servers and two fixed public hostnames are considered. No redirects or webpage bodies are downloaded.',
    'No driver, APN, SIM selection, USB mode, route, DNS, proxy, service, security setting or other adapter was changed.',
    'Counters may also include background traffic and are not the sole path proof. Source binding, IP_UNICAST_IF, route attribution and TLS validation are required.',
    'No packet capture, independent audit of third-party system interception, bandwidth benchmark, voice or Apple device test was performed.',
    'Source addresses, interface GUIDs, DNS servers, resolved addresses and exception details remain private. Success is a historical test result, not a guarantee of all sites or future stability.'
)
[IO.File]::WriteAllText((Join-Path $directory 'internet-probe-private.json'), (ConvertTo-Json -InputObject @($privateAttempts.ToArray()) -Depth 8), $utf8)
[IO.File]::WriteAllText($publicPath, ($report | ConvertTo-Json -Depth 9), $utf8)
Write-Output ($report | ConvertTo-Json -Depth 9)
