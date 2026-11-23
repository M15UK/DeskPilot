using System.Text.Json;
using QRCoder;

namespace DeskPilot.Agent;

/// <summary>The QR code a phone scans to pair. Its text is described in docs/PROTOCOL.md.</summary>
public static class PairingQr
{
    const int PixelsPerModule = 10;

    public static string Text(string name, IReadOnlyList<string> hosts, int port, string fingerprint, string code) =>
        JsonSerializer.Serialize(new { deskpilot = AgentServer.ProtocolVersion, name, hosts, port, fingerprint, code });

    public static byte[] Png(string text) =>
        PngByteQRCodeHelper.GetQRCode(text, QRCodeGenerator.ECCLevel.M, PixelsPerModule);
}
