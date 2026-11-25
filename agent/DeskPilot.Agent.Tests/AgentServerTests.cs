using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;

namespace DeskPilot.Agent.Tests;

public sealed class HandleTests : IDisposable
{
    static readonly Deck Racing = new([new DeckPage("Racing", [new DeckButton("pit", "Pit", new KeysAction(["P"]))])]);

    readonly TempFolder folder = new();
    readonly DeckStore decks;
    readonly List<ButtonAction> ran = [];

    readonly ImageStore images;

    public HandleTests()
    {
        decks = new DeckStore(Path.Combine(folder.Path, "deck.json"));
        images = new ImageStore(Path.Combine(folder.Path, "images"));
    }

    public void Dispose() => folder.Dispose();

    Task<string?> HandleAsync(string message, Func<ButtonAction, Task>? run = null) =>
        AgentServer.HandleAsync(Encoding.UTF8.GetBytes(message), decks, images, run ?? (action =>
        {
            ran.Add(action);
            return Task.CompletedTask;
        }));

    [Fact]
    public async Task PressingAButtonRunsItsAction()
    {
        var reply = await HandleAsync("""{"type":"press","id":"play-pause"}""");

        Assert.Null(reply);
        Assert.Equal(new MediaAction("playPause"), Assert.Single(ran));
    }

    [Fact]
    public async Task AButtonInsideAFolderCanBePressed()
    {
        decks.Save(new Deck([new DeckPage("Main",
            [new DeckButton("f", "Racing", new FolderAction([new DeckButton("pit", "Pit", new KeysAction(["P"]))]))])]));

        Assert.Null(await HandleAsync("""{"type":"press","id":"pit"}"""));
        Assert.Equal(new KeysAction(["P"]), Assert.Single(ran), new ActionComparer());
    }

    [Fact]
    public async Task APhoneKeepsAPictureOnThePcAndGetsItBack()
    {
        byte[] png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 7];
        var id = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(png))[..16];
        var data = Convert.ToBase64String(png);

        Assert.Null(await HandleAsync($$"""{"type":"saveImage","id":"{{id}}","data":"{{data}}"}"""));
        Assert.Equal($$"""{"type":"image","id":"{{id}}","data":"{{data}}"}""",
            await HandleAsync($$"""{"type":"getImage","id":"{{id}}"}"""));
    }

    [Fact]
    public async Task AMissingOrBrokenPictureIsSaidPlainly()
    {
        Assert.Equal("""{"type":"image","id":"0123456789abcdef"}""",
            await HandleAsync("""{"type":"getImage","id":"0123456789abcdef"}"""));
        Assert.Contains("\"error\"", await HandleAsync("""{"type":"saveImage","id":"0123456789abcdef","data":"%%%"}"""));
    }

    [Fact]
    public async Task TheMusicCardPressesMediaKeys()
    {
        Assert.Null(await HandleAsync("""{"type":"mediaKey","media":"next"}"""));
        Assert.Equal(new MediaAction("next"), Assert.Single(ran));
        Assert.Equal("""{"type":"error","message":"Unknown message"}""",
            await HandleAsync("""{"type":"mediaKey","media":"explode"}"""));
    }

    [Fact]
    public async Task PressingAButtonThatIsGoneSaysSo()
    {
        var reply = await HandleAsync("""{"type":"press","id":"gone"}""");

        Assert.Equal("""{"type":"error","message":"That button is not on the deck any more."}""", reply);
        Assert.Empty(ran);
    }

    [Fact]
    public async Task AValidDeckIsSaved()
    {
        var reply = await HandleAsync(JsonSerializer.Serialize(new { type = "saveDeck", deck = Racing }, Deck.Json));

        Assert.Null(reply);
        Assert.Equal("Racing", decks.Current.Pages[0].Name);
    }

    [Fact]
    public async Task ABadDeckIsRefusedAndTheOldOneKept()
    {
        var reply = await HandleAsync("""{"type":"saveDeck","deck":{"pages":[]}}""");

        Assert.StartsWith("""{"type":"error","message":""", reply);
        Assert.Same(Deck.Default, decks.Current);
    }

    [Theory]
    [InlineData("""{"type":"media","action":"playPause"}""")]
    [InlineData("""{"type":"press","id":5}""")]
    [InlineData("""["press","play-pause"]""")]
    [InlineData("not json")]
    [InlineData("")]
    public async Task OtherMessagesAreRefused(string message)
    {
        Assert.Equal("""{"type":"error","message":"Unknown message"}""", await HandleAsync(message));
        Assert.Empty(ran);
    }

    [Fact]
    public async Task AnActionThatOnlyWorksOnWindowsSaysSo()
    {
        var reply = await HandleAsync("""{"type":"press","id":"play-pause"}""",
            _ => throw new PlatformNotSupportedException("Only on Windows"));

        Assert.Equal("""{"type":"error","message":"Only on Windows"}""", reply);
    }
}

public class ServerTests : IAsyncLifetime
{
    readonly Channel<ButtonAction> ran = Channel.CreateUnbounded<ButtonAction>();
    readonly TempFolder folder = new();
    AgentSecurity security = null!;
    DeckStore decks = null!;
    Feed<PcStats> stats = null!;
    Feed<SimTelemetry> telemetry = null!;
    SimTelemetry? car;
    Feed<NowPlaying> media = null!;
    NowPlaying? song;
    WebApplication app = null!;
    Uri uri = null!;

    public async Task InitializeAsync()
    {
        security = new AgentSecurity(
            AgentCertificate.LoadOrCreate(folder.Path),
            new PairingCodes(TimeProvider.System),
            new PairedPhones(Path.Combine(folder.Path, "phones.json")));
        decks = new DeckStore(Path.Combine(folder.Path, "deck.json"));
        stats = new Feed<PcStats>(TimeSpan.FromSeconds(1), () => new PcStats(CpuLoad: 50, GpuLoad: null, GpuTemp: null, RamLoad: 40));
        telemetry = new Feed<SimTelemetry>(TimeSpan.FromMilliseconds(33), () => car);
        media = new Feed<NowPlaying>(TimeSpan.FromSeconds(1), () => song);
        var images = new ImageStore(Path.Combine(folder.Path, "images"));
        app = AgentServer.Create(port: 0, new AgentServices(security, decks, stats, telemetry, media, images, action =>
        {
            ran.Writer.TryWrite(action);
            return Task.CompletedTask;
        }));
        await app.StartAsync();
        var address = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.First();
        uri = new Uri($"wss://127.0.0.1:{new Uri(address).Port}/ws");
    }

    public async Task DisposeAsync()
    {
        await app.DisposeAsync();
        security.Certificate.Dispose();
        folder.Dispose();
    }

    [Fact]
    public async Task APairedPhoneSignsInGetsTheDeckAndPressesButtons()
    {
        string key;
        using (var phone = await ConnectAsync())
        {
            await SendAsync(phone, new { type = "pair", code = security.Codes.New() });
            using var paired = await ReceiveJsonAsync(phone);
            Assert.Equal("paired", Type(paired));
            key = paired.RootElement.GetProperty("key").GetString()!;
            using var hello = await ReceiveJsonAsync(phone);
            Assert.Equal("hello", Type(hello));
            Assert.Equal(Environment.MachineName, hello.RootElement.GetProperty("name").GetString());
            Assert.Equal(5, hello.RootElement.GetProperty("version").GetInt32());
            using var deck = await ReceiveJsonAsync(phone);
            Assert.Equal("deck", Type(deck));
        }
        Assert.Equal(1, security.Phones.Count);

        using var later = await ConnectAsync();
        await SendAsync(later, new { type = "auth", key });
        using var welcome = await ReceiveJsonAsync(later);
        Assert.Equal("hello", Type(welcome));
        using var deckAgain = await ReceiveJsonAsync(later);
        Assert.Equal("Main", PageName(deckAgain));
        await SendAsync(later, new { type = "press", id = "play-pause" });
        Assert.Equal(new MediaAction("playPause"), await ran.Reader.ReadAsync(Timeout()));
    }

    [Fact]
    public async Task ASavedDeckReachesEveryConnectedPhone()
    {
        using var first = await SignedInPhoneAsync();
        using var second = await SignedInPhoneAsync();
        var racing = new Deck([new DeckPage("Racing", [new DeckButton("pit", "Pit", new KeysAction(["P"]))])]);

        await SendAsync(first, new { type = "saveDeck", deck = racing });

        foreach (var phone in new[] { first, second })
        {
            using var update = await ReceiveJsonAsync(phone);
            Assert.Equal("deck", Type(update));
            Assert.Equal("Racing", PageName(update));
        }
    }

    [Fact]
    public async Task ASignedInPhoneGetsStatsEverySecond()
    {
        using var phone = await SignedInPhoneAsync();

        stats.Tick();
        using var update = await ReceiveJsonAsync(phone);

        Assert.Equal("stats", Type(update));
        Assert.Equal(50, update.RootElement.GetProperty("stats").GetProperty("cpuLoad").GetDouble());
        Assert.False(update.RootElement.GetProperty("stats").TryGetProperty("gpuLoad", out _));
    }

    [Fact]
    public async Task ASignedInPhoneGetsTelemetryOnlyWhileDriving()
    {
        using var phone = await SignedInPhoneAsync();

        telemetry.Tick(); // not driving: nothing is sent
        car = new SimTelemetry(Speed: 182, Rpm: 7350, RpmMax: 8500, Gear: 3, Fuel: 41.5, FuelMax: 65, Lap: 5,
            Position: 2, LapTime: 31.25, LastLap: 103.9, BestLap: null, TyreFlTemp: 85, TyreFrTemp: 87,
            TyreRlTemp: 79, TyreRrTemp: 80);
        telemetry.Tick();
        using var update = await ReceiveJsonAsync(phone);

        Assert.Equal("telemetry", Type(update));
        Assert.Equal(7350, update.RootElement.GetProperty("telemetry").GetProperty("rpm").GetDouble());
    }

    [Fact]
    public async Task ThePhoneGetsTheSongWithItsCoverOnceThenOnlyChanges()
    {
        using var phone = await SignedInPhoneAsync();
        var now = DateTimeOffset.UtcNow;
        song = NowPlaying.From("Neon Highway", "The Midnight Drive", "Spotify.exe", playing: true,
            TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(240), updated: now, now: now, cover: [1, 2, 3]);

        media.Tick();
        media.Tick(); // nothing changed: nothing is sent
        song = song with { Playing = false };
        media.Tick();
        using var first = await ReceiveJsonAsync(phone);
        using var second = await ReceiveJsonAsync(phone);

        var playing = first.RootElement.GetProperty("media");
        Assert.Equal("media", Type(first));
        Assert.Equal("Neon Highway", playing.GetProperty("title").GetString());
        Assert.Equal("Spotify", playing.GetProperty("app").GetString());
        Assert.Equal("AQID", playing.GetProperty("cover").GetString());
        var paused = second.RootElement.GetProperty("media");
        Assert.False(paused.GetProperty("playing").GetBoolean());
        Assert.False(paused.TryGetProperty("cover", out _)); // the phone already has it
        Assert.Equal(playing.GetProperty("coverId").GetString(), paused.GetProperty("coverId").GetString());
    }

    [Theory]
    [InlineData("""{"type":"pair","code":"wrong"}""")]
    [InlineData("""{"type":"auth","key":"unknown"}""")]
    [InlineData("""{"type":"press","id":"play-pause"}""")]
    [InlineData("not json")]
    public async Task StrangersAreRefusedAndDisconnected(string firstMessage)
    {
        security.Codes.New();
        using var phone = await ConnectAsync();

        await phone.SendAsync(Encoding.UTF8.GetBytes(firstMessage), WebSocketMessageType.Text,
            endOfMessage: true, Timeout());
        using var error = await ReceiveJsonAsync(phone);
        var close = await phone.ReceiveAsync(new byte[256], Timeout());

        Assert.Equal("error", Type(error));
        Assert.Equal(WebSocketMessageType.Close, close.MessageType);
        Assert.Equal(WebSocketCloseStatus.PolicyViolation, phone.CloseStatus);
        Assert.False(ran.Reader.TryRead(out _));
        Assert.Equal(0, security.Phones.Count);
    }

    [Fact]
    public async Task AnOversizedFirstMessageClosesTheConnection()
    {
        using var phone = await ConnectAsync();

        // Just over the limit: a much bigger message can still be sending when the PC hangs up,
        // and Windows then fails the send instead of showing the close.
        await phone.SendAsync(new byte[AgentServer.MaxSignInBytes + 1], WebSocketMessageType.Text,
            endOfMessage: true, Timeout());
        var result = await phone.ReceiveAsync(new byte[256], Timeout());

        Assert.Equal(WebSocketMessageType.Close, result.MessageType);
        Assert.Equal(WebSocketCloseStatus.MessageTooBig, phone.CloseStatus);
        Assert.False(ran.Reader.TryRead(out _));
    }

    /// <summary>Connects like the phone app: trusting only the agent's own certificate.</summary>
    async Task<ClientWebSocket> ConnectAsync()
    {
        var fingerprint = AgentCertificate.Fingerprint(security.Certificate);
        var phone = new ClientWebSocket();
        phone.Options.RemoteCertificateValidationCallback = (_, certificate, _, _) =>
            certificate is not null && AgentCertificate.Fingerprint(certificate) == fingerprint;
        await phone.ConnectAsync(uri, Timeout());
        return phone;
    }

    /// <summary>Pairs a new phone and reads its paired, hello and deck messages.</summary>
    async Task<ClientWebSocket> SignedInPhoneAsync()
    {
        var phone = await ConnectAsync();
        await SendAsync(phone, new { type = "pair", code = security.Codes.New() });
        for (var i = 0; i < 3; i++)
        {
            (await ReceiveJsonAsync(phone)).Dispose();
        }
        return phone;
    }

    static Task SendAsync(WebSocket socket, object message) =>
        socket.SendAsync(JsonSerializer.SerializeToUtf8Bytes(message, Deck.Json), WebSocketMessageType.Text,
            endOfMessage: true, Timeout());

    static async Task<JsonDocument> ReceiveJsonAsync(WebSocket socket)
    {
        var buffer = new byte[AgentServer.MaxMessageBytes * 4];
        var result = await socket.ReceiveAsync(buffer, Timeout());
        Assert.Equal(WebSocketMessageType.Text, result.MessageType);
        Assert.True(result.EndOfMessage);
        return JsonDocument.Parse(buffer.AsMemory(0, result.Count));
    }

    static string? Type(JsonDocument message) => message.RootElement.GetProperty("type").GetString();

    static string? PageName(JsonDocument deckMessage) =>
        deckMessage.RootElement.GetProperty("deck").GetProperty("pages")[0].GetProperty("name").GetString();

    static CancellationToken Timeout() => new CancellationTokenSource(TimeSpan.FromSeconds(5)).Token;
}

/// Records compare lists by reference; this compares key buttons by their combos.
sealed class ActionComparer : IEqualityComparer<ButtonAction>
{
    public bool Equals(ButtonAction? x, ButtonAction? y) =>
        x is KeysAction a && y is KeysAction b ? a.Combos.SequenceEqual(b.Combos) : object.Equals(x, y);

    public int GetHashCode(ButtonAction action) => 0;
}
