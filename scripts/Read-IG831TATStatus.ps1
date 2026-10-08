[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EvidenceDirectory,
    [switch]$AcknowledgeStatusQueries
)

$ErrorActionPreference = 'Stop'
if (-not $AcknowledgeStatusQueries) { throw 'Explicit status-query acknowledgement is required.' }
$targets = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.InstanceId -like 'USB\VID_2CA3&PID_4009&MI_02\*' })
if ($targets.Count -ne 1) { throw 'Expected exactly one IG831T MI_02 serial device.' }
$target = $targets[0]
$key = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\' + $target.InstanceId + '\Device Parameters'
$portName = Get-ItemPropertyValue -LiteralPath $key -Name PortName -ErrorAction Stop
if ($portName -notmatch '^COM[1-9][0-9]*$' -or [IO.Ports.SerialPort]::GetPortNames() -notcontains $portName -or
    $target.FriendlyName -notlike "*($portName)") { throw 'COM identity cannot be verified.' }
$problem = (Get-PnpDeviceProperty -InstanceId $target.InstanceId -KeyName DEVPKEY_Device_ProblemCode -ErrorAction Stop).Data
$service = (Get-PnpDeviceProperty -InstanceId $target.InstanceId -KeyName DEVPKEY_Device_Service -ErrorAction Stop).Data
if ($problem -ne 0 -or $service -ne 'qcusbser') { throw 'Serial driver identity or state is unexpected.' }
$directory = [IO.Path]::GetFullPath($EvidenceDirectory)
[IO.Directory]::CreateDirectory($directory) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$responses = [Collections.Generic.List[object]]::new()
$commands = @('AT', 'AT+CPIN?', 'AT+CFUN?', 'AT+CREG?', 'AT+CGREG?', 'AT+CEREG?', 'AT+CSQ', 'AT+COPS?', 'AT+CGATT?', 'AT+CGACT?', 'AT+CESQ', 'AT+CEER', 'AT+CGDCONT?')
$serial = [IO.Ports.SerialPort]::new($portName, 115200, [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.ReadTimeout = 1000
$serial.WriteTimeout = 1000
$serial.Encoding = [Text.Encoding]::ASCII
try {
    $serial.Open()
    foreach ($command in $commands) {
        $serial.DiscardInBuffer()
        $serial.Write($command + "`r")
        $response = [Text.StringBuilder]::new()
        $timer = [Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Milliseconds 100
            [void]$response.Append($serial.ReadExisting())
            if ($response.Length -gt 8192) { throw 'Unexpected serial response length; stopped.' }
        } while ($timer.ElapsedMilliseconds -lt 3000 -and $response.ToString() -notmatch '(?m)(^|[\r\n])(OK|ERROR|\+CME ERROR:[^\r\n]*)([\r\n]|$)')
        $text = $response.ToString()
        $responses.Add([ordered]@{ command = $command; response = $text; collectedAtUTC = [DateTime]::UtcNow.ToString('o') })
        [IO.File]::WriteAllText((Join-Path $directory 'at-status-private.json'), (ConvertTo-Json -InputObject @($responses.ToArray()) -Depth 5), $utf8)
        $redacted = $text -replace '\b[0-9]{7,22}\b', '[identifier-redacted]'
        if ($command -eq 'AT+CGDCONT?') { $redacted = '[context configuration retained only in the private evidence file]' }
        Write-Output ($command + ': ' + ($redacted -replace '[\r\n]+', ' ').Trim())
        if ($command -eq 'AT' -and $text -notmatch '(?m)(^|[\r\n])OK([\r\n]|$)') {
            throw 'The candidate interface did not confirm AT capability; no further commands sent.'
        }
    }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
