using System.Text.Json;

namespace DeskPilot.Agent.Tests;

public sealed class FakeTime : TimeProvider
{
    public DateTimeOffset Now { get; set; } = new(2026, 11, 23, 12, 0, 0, TimeSpan.Zero);

    public override DateTimeOffset GetUtcNow() => Now;
}

public sealed class TempFolder : IDisposable
{
    public string Path { get; } = Directory.CreateTempSubdirectory("deskpilot-tests-").FullName;

    public void Dispose() => Directory.Delete(Path, recursive: true);
}

public class CertificateTests
{
    [Fact]
    public void TheSameCertificateIsUsedAfterARestart()
    {
        using var folder = new TempFolder();

        using var first = AgentCertificate.LoadOrCreate(folder.Path);
        using var second = AgentCertificate.LoadOrCreate(folder.Path);

        Assert.True(first.HasPrivateKey);
        Assert.Matches("^[0-9a-f]{64}$", AgentCertificate.Fingerprint(first));
        Assert.Equal(AgentCertificate.Fingerprint(first), AgentCertificate.Fingerprint(second));
    }
}

public class PairingCodesTests
{
    [Fact]
    public void ACodeWorksOnce()
    {
        var codes = new PairingCodes(new FakeTime());
        var code = codes.New();

        Assert.True(codes.TryUse(code));
        Assert.False(codes.TryUse(code));
    }

    [Fact]
    public void ACodeExpiresAfterFiveMinutes()
    {
        var time = new FakeTime();
        var codes = new PairingCodes(time);
        var code = codes.New();

        time.Now += PairingCodes.Lifetime + TimeSpan.FromSeconds(1);

        Assert.False(codes.TryUse(code));
    }

    [Fact]
    public void ANewCodeReplacesTheOldOne()
    {
        var codes = new PairingCodes(new FakeTime());
        var old = codes.New();
        var fresh = codes.New();

        Assert.False(codes.TryUse(old));
        Assert.True(codes.TryUse(fresh));
    }

    [Theory]
    [InlineData("")]
    [InlineData("wrong")]
    public void WrongCodesAreRefused(string guess)
    {
        var codes = new PairingCodes(new FakeTime());
        codes.New();

        Assert.False(codes.TryUse(guess));
    }

    [Fact]
    public void NothingWorksBeforeTheFirstCode()
    {
        Assert.False(new PairingCodes(new FakeTime()).TryUse("anything"));
    }
}

public class PairedPhonesTests
{
    [Fact]
    public void APairedPhoneIsStillKnownAfterARestart()
    {
        using var folder = new TempFolder();
        var file = System.IO.Path.Combine(folder.Path, "phones.json");

        var key = new PairedPhones(file).Add();
        var afterRestart = new PairedPhones(file);

        Assert.True(afterRestart.IsKnown(key));
        Assert.Equal(1, afterRestart.Count);
    }

    [Theory]
    [InlineData("")]
    [InlineData("not a key")]
    public void UnknownKeysAreRefused(string key)
    {
        using var folder = new TempFolder();
        var phones = new PairedPhones(System.IO.Path.Combine(folder.Path, "phones.json"));
        phones.Add();

        Assert.False(phones.IsKnown(key));
    }

    [Fact]
    public void TheFileKeepsNoKeys()
    {
        using var folder = new TempFolder();
        var file = System.IO.Path.Combine(folder.Path, "phones.json");

        var key = new PairedPhones(file).Add();

        Assert.DoesNotContain(key, File.ReadAllText(file));
    }

    [Fact]
    public void ForgetAllUnpairsEveryPhone()
    {
        using var folder = new TempFolder();
        var file = System.IO.Path.Combine(folder.Path, "phones.json");
        var phones = new PairedPhones(file);
        var key = phones.Add();

        phones.ForgetAll();

        Assert.False(phones.IsKnown(key));
        Assert.False(new PairedPhones(file).IsKnown(key));
    }
}

public class PairingQrTests
{
    [Fact]
    public void TheQrCodeHoldsWhatThePhoneNeeds()
    {
        var text = PairingQr.Text("GAMING-PC", ["192.168.1.50", "10.0.0.7"], 8740, new string('a', 64), "code123");

        using var json = JsonDocument.Parse(text);
        var root = json.RootElement;
        Assert.Equal(4, root.GetProperty("deskpilot").GetInt32());
        Assert.Equal("GAMING-PC", root.GetProperty("name").GetString());
        Assert.Equal(["192.168.1.50", "10.0.0.7"], root.GetProperty("hosts").EnumerateArray().Select(h => h.GetString()));
        Assert.Equal(8740, root.GetProperty("port").GetInt32());
        Assert.Equal(new string('a', 64), root.GetProperty("fingerprint").GetString());
        Assert.Equal("code123", root.GetProperty("code").GetString());
    }
}
