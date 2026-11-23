using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace DeskPilot.Agent;

/// <summary>
/// The agent's own encryption certificate. Phones trust it only by the fingerprint in the pairing QR code,
/// so it is made once and kept.
/// </summary>
public static class AgentCertificate
{
    const string FileName = "certificate.pfx";

    public static X509Certificate2 LoadOrCreate(string folder)
    {
        var path = Path.Combine(folder, FileName);
        if (!File.Exists(path))
        {
            using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var request = new CertificateRequest("CN=DeskPilot", key, HashAlgorithmName.SHA256);
            using var created = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(20));
            PrivateFile.Write(path, created.Export(X509ContentType.Pfx));
        }
        return X509CertificateLoader.LoadPkcs12FromFile(path, password: null);
    }

    /// <summary>SHA-256 of the certificate, as 64 lowercase hex characters.</summary>
    public static string Fingerprint(X509Certificate certificate) =>
        Convert.ToHexStringLower(SHA256.HashData(certificate.GetRawCertData()));
}
