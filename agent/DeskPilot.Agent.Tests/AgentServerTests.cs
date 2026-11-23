using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;

namespace DeskPilot.Agent.Tests;

public class HandleTests
{
    const string PlayPause = """{"type":"media","action":"playPause"}""";

    static byte[] Utf8(string text) => Encoding.UTF8.GetBytes(text);

    [Fact]
    public void PlayPauseMessageRunsTheAction()
    {
        var calls = 0;

        var reply = AgentServer.Handle(Utf8(PlayPause), () => calls++);

        Assert.Equal(1, calls);
        Assert.Null(reply);
    }

    [Theory]
    [InlineData("""{"type":"media","action":"stop"}""")]
    [InlineData("""{"type":"key","keys":"F1"}""")]
    [InlineData("""{"type":1,"action":"playPause"}""")]
    [InlineData("""["media","playPause"]""")]
    [InlineData("not json")]
    [InlineData("")]
    public void OtherMessagesAreRefusedWithoutRunningTheAction(string message)
    {
        var calls = 0;

        var reply = AgentServer.Handle(Utf8(message), () => calls++);

        Assert.Equal(0, calls);
        Assert.Equal("""{"type":"error","message":"Unknown message"}""", reply);
    }

    [Fact]
    public void AFailingActionIsReportedToThePhone()
    {
        var reply = AgentServer.Handle(Utf8(PlayPause), () => throw new PlatformNotSupportedException("Only on Windows"));

        Assert.Equal("""{"type":"error","message":"Only on Windows"}""", reply);
    }
}

public class ServerTests : IAsyncLifetime
{
    readonly TaskCompletionSource playPause = new(TaskCreationOptions.RunContinuationsAsynchronously);
    readonly TempFolder folder = new();
    AgentSecurity security = null!;
    WebApplication app = null!;
    Uri uri = null!;

    public async Task InitializeAsync()
    {
        security = new AgentSecurity(
            AgentCertificate.LoadOrCreate(folder.Path),
            new PairingCodes(TimeProvider.System),
            new PairedPhones(Path.Combine(folder.Path, "phones.json")));
        app = AgentServer.Create(port: 0, security, () => playPause.TrySetResult());
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
    public async Task APairedPhoneSignsInWithItsKeyAndCanPlayPause()
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
            Assert.Equal(2, hello.RootElement.GetProperty("version").GetInt32());
        }
        Assert.Equal(1, security.Phones.Count);

        using var later = await ConnectAsync();
        await SendAsync(later, new { type = "auth", key });
        using var welcome = await ReceiveJsonAsync(later);
        Assert.Equal("hello", Type(welcome));
        await SendAsync(later, new { type = "media", action = "playPause" });
        await playPause.Task.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Theory]
    [InlineData("""{"type":"pair","code":"wrong"}""")]
    [InlineData("""{"type":"auth","key":"unknown"}""")]
    [InlineData("""{"type":"media","action":"playPause"}""")]
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
        Assert.False(playPause.Task.IsCompleted);
        Assert.Equal(0, security.Phones.Count);
    }

    [Fact]
    public async Task OversizedMessageClosesTheConnection()
    {
        using var phone = await ConnectAsync();

        await phone.SendAsync(new byte[AgentServer.MaxMessageBytes + 1], WebSocketMessageType.Text,
            endOfMessage: true, Timeout());
        var result = await phone.ReceiveAsync(new byte[256], Timeout());

        Assert.Equal(WebSocketMessageType.Close, result.MessageType);
        Assert.Equal(WebSocketCloseStatus.MessageTooBig, phone.CloseStatus);
        Assert.False(playPause.Task.IsCompleted);
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

    static Task SendAsync(WebSocket socket, object message) =>
        socket.SendAsync(JsonSerializer.SerializeToUtf8Bytes(message), WebSocketMessageType.Text,
            endOfMessage: true, Timeout());

    static async Task<JsonDocument> ReceiveJsonAsync(WebSocket socket)
    {
        var buffer = new byte[4096];
        var result = await socket.ReceiveAsync(buffer, Timeout());
        Assert.Equal(WebSocketMessageType.Text, result.MessageType);
        return JsonDocument.Parse(buffer.AsMemory(0, result.Count));
    }

    static string? Type(JsonDocument message) => message.RootElement.GetProperty("type").GetString();

    static CancellationToken Timeout() => new CancellationTokenSource(TimeSpan.FromSeconds(5)).Token;
}
