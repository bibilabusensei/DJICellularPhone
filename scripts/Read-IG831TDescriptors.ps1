[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [Parameter(Mandatory = $true)]
    [string]$SnapshotPath
)

$ErrorActionPreference = 'Stop'
$privateDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$publicPath = [System.IO.Path]::GetFullPath($SnapshotPath)
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.Directory]::CreateDirectory($privateDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($publicPath)) | Out-Null

function Invoke-PnpRead {
    param([string[]]$Arguments)
    $result = & pnputil.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "PnPUtil read failed ($LASTEXITCODE): $($result -join ' ')"
    }
    return ($result -join "`n")
}

function Read-PropertyValue {
    param([string]$Content, [string]$Name)
    $pattern = '(?m)^\s{4}' + [regex]::Escape($Name) + ' \[[^\]]+\]:\r?\n[ \t]{8}(?<value>[^\r\n]+)'
    $propertyMatch = [regex]::Match($Content, $pattern)
    if (-not $propertyMatch.Success) { throw "Required PnP property missing: $Name" }
    return $propertyMatch.Groups['value'].Value.Trim()
}

$listing = Invoke-PnpRead -Arguments @('/enum-devices', '/connected', '/bus', 'USB')
$parentPattern = '(?im)^[^\r\n]*?\b(?<id>USB\\VID_2CA3&PID_4009\\[^\s]+)[ \t]*$'
$parentIds = @([regex]::Matches($listing, $parentPattern) |
    ForEach-Object { $_.Groups['id'].Value } | Sort-Object -Unique)
if ($parentIds.Count -ne 1) { throw 'Exactly one connected 2CA3:4009 parent is required.' }
$properties = Invoke-PnpRead -Arguments @('/enum-devices', '/instanceid', $parentIds[0], '/properties')
$hubId = Read-PropertyValue -Content $properties -Name 'DEVPKEY_Device_Parent'
$address = Read-PropertyValue -Content $properties -Name 'DEVPKEY_Device_Address'
if ($address -notmatch '^0x(?<port>[0-9A-Fa-f]+)') { throw 'Unrecognized USB port index.' }
$portNumber = [Convert]::ToUInt32($Matches['port'], 16)
if ($portNumber -lt 1 -or $portNumber -gt 255) { throw 'USB port index outside allowed range.' }
$interfaces = Invoke-PnpRead -Arguments @('/enum-devices', '/instanceid', $hubId, '/interfaces')
$hubPattern = '(?im)(?<path>\\\\\?\\[^\r\n]+#\{f18a0e88-c30c-11d0-8815-00a0c906bed8\})[ \t]*$'
$hubPaths = @([regex]::Matches($interfaces, $hubPattern) |
    ForEach-Object { $_.Groups['path'].Value.Trim() } | Sort-Object -Unique)
if ($hubPaths.Count -ne 1) { throw 'Exactly one parent USB hub interface is required.' }
[System.IO.File]::WriteAllText((Join-Path $privateDirectory 'descriptor-topology.txt'),
    "$properties`n$interfaces", $utf8)

if (-not ('IG831T.HubDescriptorReader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace IG831T
{
    public sealed class DescriptorBytes
    {
        public byte[] Device { get; set; }
        public byte[] Configuration { get; set; }
    }

    public static class HubDescriptorReader
    {
        private const uint GetDescriptorIoctl = 0x220410;

        [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle OpenHub(string path, uint access, uint sharing,
            IntPtr security, uint disposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(SafeFileHandle device, uint code,
            byte[] input, uint inputSize, byte[] output, uint outputSize,
            out uint returned, IntPtr overlapped);

        private static byte[] ReadDescriptor(SafeFileHandle hub, uint port, byte descriptorType, ushort length)
        {
            if ((descriptorType != 1 && descriptorType != 2) || length == 0)
                throw new ArgumentException("Only device/configuration GET_DESCRIPTOR is allowed.");
            byte[] request = new byte[12 + length];
            Buffer.BlockCopy(BitConverter.GetBytes(port), 0, request, 0, 4);
            request[4] = 0x80;
            request[5] = 0x06;
            request[7] = descriptorType;
            Buffer.BlockCopy(BitConverter.GetBytes(length), 0, request, 10, 2);
            byte[] response = new byte[request.Length];
            uint returned;
            if (!DeviceIoControl(hub, GetDescriptorIoctl, request, (uint)request.Length,
                response, (uint)response.Length, out returned, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Read-only USB GET_DESCRIPTOR failed");
            if (returned != response.Length)
                throw new InvalidOperationException("USB descriptor response was incomplete.");
            byte[] descriptor = new byte[length];
            Buffer.BlockCopy(response, 12, descriptor, 0, length);
            return descriptor;
        }

        public static DescriptorBytes Read(string hubPath, uint port)
        {
            using (SafeFileHandle hub = OpenHub(hubPath, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
            {
                if (hub.IsInvalid)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open parent hub for metadata reads");
                byte[] device = ReadDescriptor(hub, port, 1, 18);
                if (device[0] != 18 || device[1] != 1 || BitConverter.ToUInt16(device, 8) != 0x2CA3 ||
                    BitConverter.ToUInt16(device, 10) != 0x4009)
                    throw new InvalidOperationException("Port no longer contains the expected 2CA3:4009 device.");
                byte[] header = ReadDescriptor(hub, port, 2, 9);
                if (header[0] != 9 || header[1] != 2)
                    throw new InvalidOperationException("Invalid USB configuration header.");
                ushort totalLength = BitConverter.ToUInt16(header, 2);
                if (totalLength < 9)
                    throw new InvalidOperationException("Invalid USB configuration length.");
                byte[] configuration = ReadDescriptor(hub, port, 2, totalLength);
                for (int offset = 0; offset < header.Length; offset++)
                    if (configuration[offset] != header[offset])
                        throw new InvalidOperationException("USB configuration changed during the read.");
                return new DescriptorBytes { Device = device, Configuration = configuration };
            }
        }
    }
}
'@
}

$descriptors = [IG831T.HubDescriptorReader]::Read($hubPaths[0], $portNumber)
$device = $descriptors.Device
$configuration = $descriptors.Configuration
$interfaceRecords = [System.Collections.Generic.List[object]]::new()
$extraDescriptors = [System.Collections.Generic.List[object]]::new()
$currentInterface = $null
$offset = 0
while ($offset -lt $configuration.Length) {
    if ($offset + 2 -gt $configuration.Length) { throw 'Truncated descriptor header.' }
    $length = [int]$configuration[$offset]
    $type = [int]$configuration[$offset + 1]
    if ($length -lt 2 -or $offset + $length -gt $configuration.Length) { throw 'Invalid descriptor length.' }
    if ($type -eq 4) {
        if ($length -lt 9) { throw 'Truncated interface descriptor.' }
        $currentInterface = [ordered]@{
            number = [int]$configuration[$offset + 2]
            alternateSetting = [int]$configuration[$offset + 3]
            endpointCount = [int]$configuration[$offset + 4]
            class = '{0:X2}' -f $configuration[$offset + 5]
            subclass = '{0:X2}' -f $configuration[$offset + 6]
            protocol = '{0:X2}' -f $configuration[$offset + 7]
            endpoints = [System.Collections.Generic.List[object]]::new()
        }
        $interfaceRecords.Add($currentInterface)
    } elseif ($type -eq 5) {
        if ($length -lt 7 -or $null -eq $currentInterface) { throw 'Invalid endpoint descriptor placement.' }
        $endpointAddress = [int]$configuration[$offset + 2]
        $attributes = [int]$configuration[$offset + 3]
        $transferType = @('Control', 'Isochronous', 'Bulk', 'Interrupt')[$attributes -band 3]
        $currentInterface.endpoints.Add([ordered]@{
            address = '0x{0:X2}' -f $endpointAddress
            direction = if (($endpointAddress -band 0x80) -ne 0) { 'IN' } else { 'OUT' }
            transferType = $transferType
            attributes = '0x{0:X2}' -f $attributes
            maxPacketSize = [int][BitConverter]::ToUInt16($configuration, $offset + 4)
            interval = [int]$configuration[$offset + 6]
        })
    } elseif ($type -ne 2) {
        $extraDescriptors.Add([ordered]@{ type = '0x{0:X2}' -f $type; length = $length })
    }
    $offset += $length
}
foreach ($record in $interfaceRecords) {
    if ($record.endpoints.Count -ne $record.endpointCount) { throw 'Interface endpoint count mismatch.' }
}
$distinctInterfaces = @($interfaceRecords | ForEach-Object { $_.number } | Sort-Object -Unique)
if ($distinctInterfaces.Count -ne $configuration[4]) { throw 'Configuration interface count mismatch.' }
[System.IO.File]::WriteAllBytes((Join-Path $privateDirectory 'device-descriptor.bin'), $device)
[System.IO.File]::WriteAllBytes((Join-Path $privateDirectory 'configuration-descriptor.bin'), $configuration)
$snapshot = [ordered]@{
    schemaVersion = 1
    collectedAtUTC = [DateTime]::UtcNow.ToString('o')
    method = 'Parent hub standard GET_DESCRIPTOR (device and configuration index 0 only)'
    vendorId = '{0:X4}' -f [BitConverter]::ToUInt16($device, 8)
    productId = '{0:X4}' -f [BitConverter]::ToUInt16($device, 10)
    usbBCD = '0x{0:X4}' -f [BitConverter]::ToUInt16($device, 2)
    deviceBCD = '0x{0:X4}' -f [BitConverter]::ToUInt16($device, 12)
    deviceClass = '{0:X2}' -f $device[4]
    deviceSubclass = '{0:X2}' -f $device[5]
    deviceProtocol = '{0:X2}' -f $device[6]
    configurationCount = [int]$device[17]
    configuration = [ordered]@{
        index = 0
        value = [int]$configuration[5]
        totalLength = $configuration.Length
        interfaceCount = [int]$configuration[4]
        attributes = '0x{0:X2}' -f $configuration[7]
        maxPowerField = [int]$configuration[8]
        interfaces = @($interfaceRecords.ToArray())
        extraDescriptorHeaders = @($extraDescriptors.ToArray())
    }
    limitations = @(
        'No strings, serial numbers, SIM identifiers, vendor requests, bulk transfers, AT commands or networking were read or sent.',
        'Descriptors do not establish AT/QMI/MBIM/NDIS protocol compatibility, chipset identity or voice support.',
        'Raw descriptors and hub topology remain private; this snapshot excludes paths and device instance suffixes.',
        'No driver, registry, firmware, USB configuration or endpoint state was changed.'
    )
}
[System.IO.File]::WriteAllText($publicPath, ($snapshot | ConvertTo-Json -Depth 10), $utf8)
Write-Output "Read-only descriptor snapshot saved: $publicPath"
