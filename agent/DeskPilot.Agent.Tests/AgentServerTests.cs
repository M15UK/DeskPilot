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
    WebApplication app = null!;
    Uri uri = null!;

    public async Task InitializeAsync()
    {
        app = AgentServer.Create(port: 0, () => playPause.TrySetResult());
        await app.StartAsync();
        var address = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.First();
        uri = new Uri($"ws://127.0.0.1:{new Uri(address).Port}/ws");
    }

    public async Task DisposeAsync() => await app.DisposeAsync();

    [Fact]
    public async Task PhoneGetsHelloThenPlayPauseReachesThePc()
    {
        using var phone = new ClientWebSocket();
        await phone.ConnectAsync(uri, Timeout());

        using var hello = JsonDocument.Parse(await ReceiveText(phone));
        Assert.Equal("hello", hello.RootElement.GetProperty("type").GetString());
        Assert.Equal(Environment.MachineName, hello.RootElement.GetProperty("name").GetString());
        Assert.Equal(1, hello.RootElement.GetProperty("version").GetInt32());

        await phone.SendAsync(Encoding.UTF8.GetBytes("""{"type":"media","action":"playPause"}"""),
            WebSocketMessageType.Text, endOfMessage: true, Timeout());
        await playPause.Task.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task OversizedMessageClosesTheConnection()
    {
        using var phone = new ClientWebSocket();
        await phone.ConnectAsync(uri, Timeout());
        await ReceiveText(phone); // hello

        await phone.SendAsync(new byte[AgentServer.MaxMessageBytes + 1], WebSocketMessageType.Text,
            endOfMessage: true, Timeout());
        var result = await phone.ReceiveAsync(new byte[256], Timeout());

        Assert.Equal(WebSocketMessageType.Close, result.MessageType);
        Assert.Equal(WebSocketCloseStatus.MessageTooBig, phone.CloseStatus);
        Assert.False(playPause.Task.IsCompleted);
    }

    static async Task<string> ReceiveText(WebSocket socket)
    {
        var buffer = new byte[4096];
        var result = await socket.ReceiveAsync(buffer, Timeout());
        Assert.Equal(WebSocketMessageType.Text, result.MessageType);
        return Encoding.UTF8.GetString(buffer, 0, result.Count);
    }

    static CancellationToken Timeout() => new CancellationTokenSource(TimeSpan.FromSeconds(5)).Token;
}
