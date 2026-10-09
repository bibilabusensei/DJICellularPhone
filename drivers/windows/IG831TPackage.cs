using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

public static class IG831TPackage
{
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidDataException(message);
    }

    private static uint Read32(byte[] content, int offset)
    {
        Require(offset >= 0 && offset <= content.Length - 4, "Truncated container field.");
        return BitConverter.ToUInt32(content, offset);
    }

    private static ushort Read16(byte[] content, int offset)
    {
        Require(offset >= 0 && offset <= content.Length - 2, "Truncated container field.");
        return BitConverter.ToUInt16(content, offset);
    }

    public static string Hash(byte[] content)
    {
        using (SHA256 algorithm = SHA256.Create())
            return BitConverter.ToString(algorithm.ComputeHash(content)).Replace("-", "").ToLowerInvariant();
    }

    public static byte[] DecodeMsi(byte[] content)
    {
        Require(content.Length == 9462612 && Hash(content) == "60fb07777f63849cbaae56a248a5f452fa64a837095412515dfada7ad5e88a1b", "Setup container differs from the audited version.");
        Require(content[0] == 77 && content[1] == 90, "Expected PE container.");
        int peOffset = checked((int)Read32(content, 60));
        Require(Read32(content, peOffset) == 17744, "Invalid PE signature.");
        int count = Read16(content, peOffset + 6);
        int sectionOffset = peOffset + 24 + Read16(content, peOffset + 20);
        Require(count > 0 && count <= 96 && sectionOffset <= content.Length - count * 40, "Invalid section table.");
        int overlay = 0;
        for (int section = 0; section < count; section++)
        {
            long end = (long)Read32(content, sectionOffset + section * 40 + 16) + Read32(content, sectionOffset + section * 40 + 20);
            Require(end <= content.Length, "PE section exceeds container.");
            overlay = Math.Max(overlay, (int)end);
        }
        Require(overlay <= content.Length - 46 && Encoding.ASCII.GetString(content, overlay, 14) == "ISSetupStream\0" &&
            Read16(content, overlay + 14) == 4 && Read32(content, overlay + 16) == 4, "Unexpected InstallShield container.");
        HashSet<string> names = new HashSet<string>(new string[] { "ISSetup.dll", "0x0409.ini", "Quectel_Windows_USB_Driver(Q)_NDIS.msi", "Setup.ini" });
        int cursor = overlay + 46;
        byte[] decoded = null;
        for (int member = 0; member < 4; member++)
        {
            Require(cursor <= content.Length - 48, "Truncated member header.");
            int nameLength = checked((int)Read32(content, cursor));
            int compressedLength = checked((int)Read32(content, cursor + 10));
            Require(nameLength > 0 && nameLength < 520 && nameLength % 2 == 0 && Read32(content, cursor + 4) == 6 &&
                Read16(content, cursor + 22) == 1, "Unsupported member encoding.");
            cursor += 48;
            Require((long)cursor + nameLength + compressedLength <= content.Length, "Truncated member.");
            string name = Encoding.Unicode.GetString(content, cursor, nameLength).TrimEnd('\0');
            Require(names.Remove(name), "Unknown or duplicate container member.");
            cursor += nameLength;
            if (name.EndsWith(".msi", StringComparison.Ordinal))
            {
                byte[] seed = Encoding.UTF8.GetBytes(name);
                byte[] mask = new byte[] { 19, 53, 134, 7 };
                for (int index = 0; index < seed.Length; index++) seed[index] ^= mask[index % 4];
                byte[] compressed = new byte[compressedLength];
                for (int index = 0; index < compressedLength; index++)
                {
                    byte value = content[cursor + index];
                    compressed[index] = (byte)((~(((value << 4) & 240) | (value >> 4)) & 255) ^ seed[(index % 1024) % seed.Length]);
                }
                Require(compressedLength >= 6 && (compressed[0] & 15) == 8 &&
                    ((compressed[0] << 8) | compressed[1]) % 31 == 0 && (compressed[1] & 32) == 0, "Invalid zlib header.");
                using (MemoryStream input = new MemoryStream(compressed, 2, compressed.Length - 6))
                using (DeflateStream inflater = new DeflateStream(input, CompressionMode.Decompress))
                using (MemoryStream output = new MemoryStream())
                {
                    byte[] buffer = new byte[65536];
                    int bytes;
                    while ((bytes = inflater.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        Require(output.Length + bytes <= 7097856, "Decoded MSI exceeds audited size.");
                        output.Write(buffer, 0, bytes);
                    }
                    decoded = output.ToArray();
                }
                Require(decoded.Length == 7097856 && Hash(decoded) == "b55d3507943cd0e807a92dc9a770c20cb13bef9a586aeded9451fb032c274582", "Decoded MSI failed integrity check.");
            }
            cursor += compressedLength;
        }
        Require(names.Count == 0 && cursor == content.Length && decoded != null, "Incomplete container or trailing data.");
        return decoded;
    }

    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    private static extern uint MsiOpenDatabaseW(string path, IntPtr mode, out uint database);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    private static extern uint MsiDatabaseOpenViewW(uint database, string query, out uint view);
    [DllImport("msi.dll")]
    private static extern uint MsiViewExecute(uint view, uint record);
    [DllImport("msi.dll")]
    private static extern uint MsiViewFetch(uint view, out uint record);
    [DllImport("msi.dll")]
    private static extern uint MsiRecordReadStream(uint record, uint field, byte[] buffer, ref uint length);
    [DllImport("msi.dll")]
    private static extern uint MsiCloseHandle(uint handle);

    private static void Check(uint result)
    {
        if (result != 0) throw new InvalidOperationException("Read-only MSI query failed: " + result);
    }

    public static void ExtractCabinet(string input, string output)
    {
        uint database = 0, view = 0, record = 0;
        try
        {
            Check(MsiOpenDatabaseW(input, IntPtr.Zero, out database));
            Check(MsiDatabaseOpenViewW(database, "SELECT `Data` FROM `_Streams` WHERE `Name` = 'Data1.cab'", out view));
            Check(MsiViewExecute(view, 0));
            Check(MsiViewFetch(view, out record));
            using (FileStream destination = new FileStream(output, FileMode.CreateNew, FileAccess.Write))
            {
                byte[] buffer = new byte[65536];
                while (true)
                {
                    uint bytes = (uint)buffer.Length;
                    Check(MsiRecordReadStream(record, 1, buffer, ref bytes));
                    if (bytes == 0) break;
                    Require(destination.Length + bytes <= 5233397, "Cabinet exceeds audited size.");
                    destination.Write(buffer, 0, (int)bytes);
                }
            }
        }
        finally
        {
            if (record != 0) MsiCloseHandle(record);
            if (view != 0) MsiCloseHandle(view);
            if (database != 0) MsiCloseHandle(database);
        }
    }
}
