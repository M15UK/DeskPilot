using System.Text.Json;
using QRCoder;

namespace DeskPilot.Agent;

/// <summary>The QR code a phone scans to pair. Its text is described in docs/PROTOCOL.md.</summary>
public static class PairingQr
{
    const int PixelsPerModule = 10;

    /// <summary>The pairing format's version; phones refuse a QR code with another.</summary>
    public const int Version = 5;

    public static string Text(string name, IReadOnlyList<string> hosts, int port, string fingerprint, string code) =>
        JsonSerializer.Serialize(new { deskpilot = Version, name, hosts, port, fingerprint, code });

    public static byte[] Png(string text) =>
        PngByteQRCodeHelper.GetQRCode(text, QRCodeGenerator.ECCLevel.M, PixelsPerModule);
}
