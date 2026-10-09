using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

public static class IG831TInterfaceProbe
{
    public sealed class DnsResult
    {
        public string[] Addresses;
        public bool SourceAddressMatches;
        public bool OutgoingInterfaceMatches;
        public int ResponseBytes;
    }

    public sealed class HttpsResult
    {
        public int StatusCode;
        public int HeaderBytes;
        public string TlsProtocol;
        public bool SourceAddressMatches;
        public bool OutgoingInterfaceMatches;
        public bool RemoteAddressMatches;
    }

    private static void CheckHost(string host)
    {
        if (host != "example.com" && host != "www.microsoft.com")
            throw new InvalidOperationException("Only the two public probe hosts are allowed.");
    }

    private static Socket BoundSocket(string source, int interfaceIndex, SocketType type, ProtocolType protocol)
    {
        IPAddress address = IPAddress.Parse(source);
        if (address.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(address) ||
            address.Equals(IPAddress.Any) || interfaceIndex <= 0 || interfaceIndex >= 16777216)
            throw new InvalidOperationException("A concrete IPv4 source and interface index are required.");
        Socket socket = new Socket(AddressFamily.InterNetwork, type, protocol);
        try
        {
            socket.ReceiveTimeout = 8000;
            socket.SendTimeout = 8000;
            socket.SetSocketOption(SocketOptionLevel.IP, (SocketOptionName)31, IPAddress.HostToNetworkOrder(interfaceIndex));
            socket.Bind(new IPEndPoint(address, 0));
            if ((int)socket.GetSocketOption(SocketOptionLevel.IP, (SocketOptionName)31) != interfaceIndex)
                throw new InvalidOperationException("Outgoing interface verification failed.");
            return socket;
        }
        catch { socket.Dispose(); throw; }
    }

    private static ushort Read16(byte[] data, int offset)
    {
        if (offset < 0 || offset + 2 > data.Length) throw new InvalidDataException("Short DNS field.");
        return (ushort)((data[offset] << 8) | data[offset + 1]);
    }

    private static string ReadName(byte[] data, ref int offset)
    {
        int cursor = offset;
        bool jumped = false;
        List<string> labels = new List<string>();
        for (int steps = 0; steps < 128; steps++)
        {
            if (cursor >= data.Length) throw new InvalidDataException("Short DNS name.");
            int length = data[cursor++];
            if (length == 0)
            {
                if (!jumped) offset = cursor;
                return string.Join(".", labels.ToArray());
            }
            if ((length & 192) == 192)
            {
                if (cursor >= data.Length) throw new InvalidDataException("Short DNS pointer.");
                int destination = ((length & 63) << 8) | data[cursor++];
                if (!jumped) offset = cursor;
                cursor = destination;
                jumped = true;
                continue;
            }
            if (length > 63 || cursor + length > data.Length) throw new InvalidDataException("Invalid DNS label.");
            labels.Add(Encoding.ASCII.GetString(data, cursor, length));
            cursor += length;
        }
        throw new InvalidDataException("DNS name pointer limit exceeded.");
    }

    public static bool IsPublicIPv4(string value)
    {
        IPAddress address;
        if (!IPAddress.TryParse(value, out address) || address.AddressFamily != AddressFamily.InterNetwork) return false;
        byte[] octets = address.GetAddressBytes();
        if (octets[0] == 0 || octets[0] == 10 || octets[0] == 127 || octets[0] >= 224 ||
            (octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127) ||
            (octets[0] == 169 && octets[1] == 254) ||
            (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 192 && octets[1] == 0 && (octets[2] == 0 || octets[2] == 2)) ||
            (octets[0] == 198 && (octets[1] == 18 || octets[1] == 19)) ||
            (octets[0] == 198 && octets[1] == 51 && octets[2] == 100) ||
            (octets[0] == 203 && octets[1] == 0 && octets[2] == 113)) return false;
        return true;
    }

    public static string[] ParseDns(byte[] response, ushort identifier, string host)
    {
        CheckHost(host);
        if (response.Length < 12 || Read16(response, 0) != identifier ||
            (Read16(response, 2) & 32768) == 0 || (Read16(response, 2) & 512) != 0 ||
            (Read16(response, 2) & 15) != 0 || Read16(response, 4) != 1)
            throw new InvalidDataException("DNS reply ID, flags, or question count failed validation.");
        int offset = 12;
        string question = ReadName(response, ref offset);
        if (!string.Equals(question, host, StringComparison.OrdinalIgnoreCase) ||
            Read16(response, offset) != 1 || Read16(response, offset + 2) != 1)
            throw new InvalidDataException("DNS question differs from the requested host.");
        offset += 4;
        int answerCount = Read16(response, 6);
        if (answerCount > 128) throw new InvalidDataException("DNS answer count exceeds limit.");
        List<string> addresses = new List<string>();
        for (int answer = 0; answer < answerCount; answer++)
        {
            ReadName(response, ref offset);
            ushort type = Read16(response, offset);
            ushort recordClass = Read16(response, offset + 2);
            ushort length = Read16(response, offset + 8);
            offset += 10;
            if (offset + length > response.Length) throw new InvalidDataException("Short DNS answer.");
            if (type == 1 && recordClass == 1 && length == 4)
            {
                byte[] bytes = new byte[4];
                Array.Copy(response, offset, bytes, 0, 4);
                string address = new IPAddress(bytes).ToString();
                if (IsPublicIPv4(address) && !addresses.Contains(address)) addresses.Add(address);
            }
            offset += length;
        }
        if (addresses.Count == 0) throw new InvalidDataException("No public IPv4 DNS answer; refusing private or proxy fake-IP destinations.");
        return addresses.ToArray();
    }

    public static DnsResult Resolve(string source, int interfaceIndex, string server, string host)
    {
        CheckHost(host);
        IPAddress dnsAddress = IPAddress.Parse(server);
        if (dnsAddress.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(dnsAddress) || dnsAddress.Equals(IPAddress.Any))
            throw new InvalidOperationException("DNS server must be an explicit non-loopback IPv4 address from the module configuration.");
        byte[] random = new byte[2];
        using (RandomNumberGenerator generator = RandomNumberGenerator.Create()) generator.GetBytes(random);
        ushort identifier = (ushort)((random[0] << 8) | random[1]);
        byte[] query;
        using (MemoryStream stream = new MemoryStream())
        {
            byte[] header = new byte[] { random[0], random[1], 1, 0, 0, 1, 0, 0, 0, 0, 0, 0 };
            stream.Write(header, 0, header.Length);
            foreach (string label in host.Split('.'))
            {
                byte[] bytes = Encoding.ASCII.GetBytes(label);
                stream.WriteByte((byte)bytes.Length);
                stream.Write(bytes, 0, bytes.Length);
            }
            byte[] tail = new byte[] { 0, 0, 1, 0, 1 };
            stream.Write(tail, 0, tail.Length);
            query = stream.ToArray();
        }
        using (Socket socket = BoundSocket(source, interfaceIndex, SocketType.Dgram, ProtocolType.Udp))
        {
            socket.Connect(new IPEndPoint(dnsAddress, 53));
            if (socket.Send(query) != query.Length) throw new IOException("Short DNS send.");
            byte[] buffer = new byte[4096];
            int count = socket.Receive(buffer);
            byte[] response = new byte[count];
            Array.Copy(buffer, response, count);
            return new DnsResult {
                Addresses = ParseDns(response, identifier, host), ResponseBytes = count,
                SourceAddressMatches = ((IPEndPoint)socket.LocalEndPoint).Address.Equals(IPAddress.Parse(source)),
                OutgoingInterfaceMatches = (int)socket.GetSocketOption(SocketOptionLevel.IP, (SocketOptionName)31) == interfaceIndex
            };
        }
    }

    public static HttpsResult Head(string source, int interfaceIndex, string destination, string host)
    {
        CheckHost(host);
        if (!IsPublicIPv4(destination)) throw new InvalidOperationException("HTTPS destination is not a public IPv4 address.");
        using (Socket socket = BoundSocket(source, interfaceIndex, SocketType.Stream, ProtocolType.Tcp))
        {
            IAsyncResult connection = socket.BeginConnect(new IPEndPoint(IPAddress.Parse(destination), 443), null, null);
            using (System.Threading.WaitHandle handle = connection.AsyncWaitHandle)
            {
                if (!handle.WaitOne(8000)) throw new TimeoutException("Module-bound TCP connection timed out.");
                socket.EndConnect(connection);
            }
            using (NetworkStream network = new NetworkStream(socket, false))
            using (SslStream tls = new SslStream(network, false))
            {
                tls.ReadTimeout = 8000;
                tls.WriteTimeout = 8000;
                tls.AuthenticateAsClient(host, null, SslProtocols.Tls12, false);
                if (!tls.IsAuthenticated || !tls.IsEncrypted) throw new AuthenticationException("TLS was not authenticated and encrypted.");
                byte[] request = Encoding.ASCII.GetBytes("HEAD / HTTP/1.1\r\nHost: " + host + "\r\nUser-Agent: DJICellularPhone-ConnectivityProbe/1.0\r\nConnection: close\r\n\r\n");
                tls.Write(request, 0, request.Length);
                tls.Flush();
                byte[] buffer = new byte[1024];
                using (MemoryStream headers = new MemoryStream())
                {
                    string text = "";
                    while (headers.Length < 16384 && !text.Contains("\r\n\r\n"))
                    {
                        int count = tls.Read(buffer, 0, buffer.Length);
                        if (count == 0) break;
                        headers.Write(buffer, 0, count);
                        text = Encoding.ASCII.GetString(headers.ToArray());
                    }
                    Match status = Regex.Match(text, "^HTTP/1\\.[01] ([0-9]{3}) ");
                    if (!status.Success || !text.Contains("\r\n\r\n")) throw new InvalidDataException("A complete HTTP response header was not received.");
                    return new HttpsResult {
                        StatusCode = int.Parse(status.Groups[1].Value), HeaderBytes = (int)headers.Length,
                        TlsProtocol = tls.SslProtocol.ToString(),
                        SourceAddressMatches = ((IPEndPoint)socket.LocalEndPoint).Address.Equals(IPAddress.Parse(source)),
                        OutgoingInterfaceMatches = (int)socket.GetSocketOption(SocketOptionLevel.IP, (SocketOptionName)31) == interfaceIndex,
                        RemoteAddressMatches = ((IPEndPoint)socket.RemoteEndPoint).Address.Equals(IPAddress.Parse(destination))
                    };
                }
            }
        }
    }
}
