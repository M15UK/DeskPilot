using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;

namespace DeskPilot.Agent;

/// <summary>The one time code in the pairing QR code. Only the newest code works, once, for five minutes.</summary>
public sealed class PairingCodes(TimeProvider time)
{
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(5);

    readonly Lock gate = new();
    string? code;
    DateTimeOffset expires;

    public string New()
    {
        var fresh = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));
        lock (gate)
        {
            code = fresh;
            expires = time.GetUtcNow() + Lifetime;
        }
        return fresh;
    }

    public bool TryUse(string guess)
    {
        lock (gate)
        {
            var valid = code is not null
                && time.GetUtcNow() < expires
                && CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(code), Encoding.UTF8.GetBytes(guess));
            if (valid)
            {
                code = null;
            }
            return valid;
        }
    }
}
