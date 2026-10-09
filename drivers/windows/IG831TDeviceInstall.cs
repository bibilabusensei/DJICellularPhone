using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

public static class IG831TDeviceInstall
{
    [StructLayout(LayoutKind.Sequential)]
    public struct DeviceInfo
    {
        public uint Size;
        public Guid ClassGuid;
        public uint DevInst;
        public UIntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct InstallParameters
    {
        public uint Size;
        public uint Flags;
        public uint FlagsEx;
        public IntPtr Parent;
        public IntPtr MessageHandler;
        public IntPtr MessageContext;
        public IntPtr FileQueue;
        public UIntPtr ClassReserved;
        public uint Reserved;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string DriverPath;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DriverInfo
    {
        public uint Size;
        public uint DriverType;
        public UIntPtr Reserved;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Description;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Manufacturer;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Provider;
        public System.Runtime.InteropServices.ComTypes.FILETIME Date;
        public ulong Version;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DriverDetail
    {
        public uint Size;
        public System.Runtime.InteropServices.ComTypes.FILETIME Date;
        public uint CompatibleOffset;
        public uint CompatibleLength;
        public UIntPtr Reserved;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Section;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string InfPath;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Description;
        public char HardwareId;
    }

    public sealed class Candidate
    {
        public uint Index;
        public string HardwareId;
        public string Section;
        public string Description;
        public string Provider;
        public string InfPath;
        public ulong Version;
    }

    public sealed class BindResult
    {
        public bool DriverSelected;
        public bool Success;
        public bool NeedReboot;
        public int Error;
    }

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern IntPtr SetupDiCreateDeviceInfoList(IntPtr classGuid, IntPtr parent);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiOpenDeviceInfoW(IntPtr set, string instanceId, IntPtr parent, uint flags, ref DeviceInfo device);
    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDeviceInstallParamsW(IntPtr set, ref DeviceInfo device, ref InstallParameters parameters);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiSetDeviceInstallParamsW(IntPtr set, ref DeviceInfo device, ref InstallParameters parameters);
    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiBuildDriverInfoList(IntPtr set, ref DeviceInfo device, uint driverType);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiEnumDriverInfoW(IntPtr set, ref DeviceInfo device, uint driverType, uint index, ref DriverInfo driver);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDriverInfoDetailW(IntPtr set, ref DeviceInfo device, ref DriverInfo driver, IntPtr detail, uint bufferSize, out uint requiredSize);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiSetSelectedDriverW(IntPtr set, ref DeviceInfo device, ref DriverInfo driver);
    [DllImport("newdev.dll", EntryPoint = "DiInstallDevice", SetLastError = true)]
    private static extern bool InstallDriver(IntPtr parent, IntPtr set, ref DeviceInfo device, ref DriverInfo driver, uint flags, out bool needReboot);

    private static void Require(bool success, string operation)
    {
        if (!success) throw new Win32Exception(Marshal.GetLastWin32Error(), operation);
    }

    private static IntPtr Open(string instanceId, out DeviceInfo device)
    {
        if (instanceId == null || (!instanceId.StartsWith("USB\\VID_2CA3&PID_4009&MI_04\\", StringComparison.OrdinalIgnoreCase) &&
            !instanceId.StartsWith("USB\\VID_2CA3&PID_4009&MI_02\\", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("Only IG831T MI_02 or MI_04 is permitted.");
        IntPtr set = SetupDiCreateDeviceInfoList(IntPtr.Zero, IntPtr.Zero);
        if (set == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Create device set");
        device = new DeviceInfo { Size = (uint)Marshal.SizeOf(typeof(DeviceInfo)) };
        try
        {
            Require(SetupDiOpenDeviceInfoW(set, instanceId, IntPtr.Zero, 0, ref device), "Open target interface");
            return set;
        }
        catch
        {
            SetupDiDestroyDeviceInfoList(set);
            throw;
        }
    }

    private static void Build(IntPtr set, ref DeviceInfo device, string infPath)
    {
        if (!File.Exists(infPath) || (!string.Equals(Path.GetFileName(infPath), "qcwwan.inf", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(Path.GetFileName(infPath), "qcser.inf", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("An original allowlisted INF is required.");
        InstallParameters parameters = new InstallParameters { Size = (uint)Marshal.SizeOf(typeof(InstallParameters)) };
        Require(SetupDiGetDeviceInstallParamsW(set, ref device, ref parameters), "Read install parameters");
        parameters.Flags |= 0x00010000;
        parameters.FlagsEx |= 0x00000800 | 0x08000000;
        parameters.DriverPath = Path.GetFullPath(infPath);
        if (parameters.DriverPath.Length >= 260) throw new InvalidOperationException("INF path exceeds Windows limit.");
        Require(SetupDiSetDeviceInstallParamsW(set, ref device, ref parameters), "Set in-memory driver search parameters");
        Require(SetupDiBuildDriverInfoList(set, ref device, 1), "Enumerate class driver candidates");
    }

    private static Candidate Detail(IntPtr set, ref DeviceInfo device, ref DriverInfo driver, uint index)
    {
        const uint capacity = 32768;
        IntPtr buffer = Marshal.AllocHGlobal((int)capacity);
        try
        {
            Marshal.WriteInt32(buffer, Marshal.SizeOf(typeof(DriverDetail)));
            uint required;
            Require(SetupDiGetDriverInfoDetailW(set, ref device, ref driver, buffer, capacity, out required), "Read driver candidate detail");
            DriverDetail detail = (DriverDetail)Marshal.PtrToStructure(buffer, typeof(DriverDetail));
            int offset = (int)Marshal.OffsetOf(typeof(DriverDetail), "HardwareId");
            if (required > capacity || offset >= capacity) throw new InvalidOperationException("Invalid driver detail length.");
            string identifiers = Marshal.PtrToStringUni(IntPtr.Add(buffer, offset), ((int)capacity - offset) / 2);
            int terminator = identifiers.IndexOf('\0');
            if (terminator < 0) throw new InvalidOperationException("Driver identifier lacks terminator.");
            return new Candidate { Index = index, HardwareId = identifiers.Substring(0, terminator), Section = detail.Section,
                Description = driver.Description, Provider = driver.Provider, InfPath = detail.InfPath, Version = driver.Version };
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public static Candidate[] Probe(string instanceId, string infPath)
    {
        CheckPair(instanceId, infPath);
        DeviceInfo device;
        IntPtr set = Open(instanceId, out device);
        try
        {
            Build(set, ref device, infPath);
            List<Candidate> candidates = new List<Candidate>();
            for (uint index = 0; index < 256; index++)
            {
                DriverInfo driver = new DriverInfo { Size = (uint)Marshal.SizeOf(typeof(DriverInfo)) };
                if (!SetupDiEnumDriverInfoW(set, ref device, 1, index, ref driver))
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 259) return candidates.ToArray();
                    throw new Win32Exception(error, "Enumerate driver candidate");
                }
                candidates.Add(Detail(set, ref device, ref driver, index));
            }
            throw new InvalidOperationException("Driver candidate limit exceeded.");
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
    }

    public static BindResult Bind(string instanceId, string infPath)
    {
        bool serial = CheckPair(instanceId, infPath);
        string expectedId = serial ? "USB\\VID_2CA3&PID_4006&MI_02" : "USB\\VID_2CA3&PID_4006&MI_04";
        string expectedSection = serial ? "QportInstall00" : "qcwwan.ndi";
        string expectedProvider = serial ? "Quectel Incorporated" : "Quectel";
        ulong expectedVersion = serial ? ((30UL << 48) | (72UL << 16) | 25UL) : 5629499538931733UL;
        DeviceInfo device;
        IntPtr set = Open(instanceId, out device);
        try
        {
            Build(set, ref device, infPath);
            DriverInfo selected = new DriverInfo();
            int matches = 0;
            for (uint index = 0; index < 256; index++)
            {
                DriverInfo driver = new DriverInfo { Size = (uint)Marshal.SizeOf(typeof(DriverInfo)) };
                if (!SetupDiEnumDriverInfoW(set, ref device, 1, index, ref driver))
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 259) break;
                    throw new Win32Exception(error, "Enumerate binding candidate");
                }
                Candidate detail = Detail(set, ref device, ref driver, index);
                if (string.Equals(detail.HardwareId, expectedId, StringComparison.OrdinalIgnoreCase))
                {
                    if (detail.Section != expectedSection || detail.Provider != expectedProvider || detail.Version != expectedVersion)
                        throw new InvalidOperationException("Unexpected model or version.");
                    selected = driver;
                    matches++;
                }
            }
            if (matches != 1) throw new InvalidOperationException("Expected exactly one allowlisted Baiwang driver candidate.");
            BindResult result = new BindResult();
            result.DriverSelected = SetupDiSetSelectedDriverW(set, ref device, ref selected);
            if (!result.DriverSelected)
            {
                result.Error = Marshal.GetLastWin32Error();
                return result;
            }
            bool reboot;
            result.Success = InstallDriver(IntPtr.Zero, set, ref device, ref selected, 0, out reboot);
            result.Error = result.Success ? 0 : Marshal.GetLastWin32Error();
            result.NeedReboot = reboot;
            return result;
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
    }

    private static bool CheckPair(string instanceId, string infPath)
    {
        bool serial = string.Equals(Path.GetFileName(infPath), "qcser.inf", StringComparison.OrdinalIgnoreCase);
        string interfaceId = serial ? "02" : "04";
        string expectedFile = serial ? "qcser.inf" : "qcwwan.inf";
        if (instanceId == null || !string.Equals(Path.GetFileName(infPath), expectedFile, StringComparison.OrdinalIgnoreCase) ||
            !instanceId.StartsWith("USB\\VID_2CA3&PID_4009&MI_" + interfaceId + "\\", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Interface and INF pair is outside the experiment scope.");
        return serial;
    }
}
