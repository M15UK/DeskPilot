using System.Buffers.Text;
using System.Collections.Immutable;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DeskPilot.Agent;

public sealed record PairedPhone(string KeyHash, DateTimeOffset Paired);

/// <summary>Phones that may control this PC. The file keeps only a hash of each phone's key, never the key.</summary>
public sealed class PairedPhones
{
    readonly string file;
    readonly Lock gate = new();
    ImmutableArray<PairedPhone> phones;

    public PairedPhones(string file)
    {
        this.file = file;
        phones = File.Exists(file) ? Load(file) : [];
    }

    public int Count
    {
        get
        {
            lock (gate)
            {
                return phones.Length;
            }
        }
    }

    /// <summary>Pairs a new phone and returns the key that phone signs in with from now on.</summary>
    public string Add()
    {
        var key = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(32));
        lock (gate)
        {
            phones = phones.Add(new PairedPhone(Hash(key), DateTimeOffset.UtcNow));
            Save();
        }
        return key;
    }

    public bool IsKnown(string key)
    {
        var hash = Hash(key);
        lock (gate)
        {
            return phones.Any(phone => phone.KeyHash == hash);
        }
    }

    public void ForgetAll()
    {
        lock (gate)
        {
            phones = [];
            Save();
        }
    }

    static ImmutableArray<PairedPhone> Load(string file)
    {
        try
        {
            return JsonSerializer.Deserialize<ImmutableArray<PairedPhone>>(File.ReadAllText(file));
        }
        catch (JsonException e)
        {
            throw new InvalidDataException($"{file} is damaged. Delete it, then pair your phones again.", e);
        }
    }

    void Save() => PrivateFile.Write(file, JsonSerializer.SerializeToUtf8Bytes(phones));

    static string Hash(string key) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(key)));
}
