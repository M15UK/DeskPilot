using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace DeskPilot.Agent;

/// <summary>The WebSocket the phone app connects to. The messages are described in docs/PROTOCOL.md.</summary>
public static class AgentServer
{
    public const int DefaultPort = 8740;
    public const int MaxMessageBytes = 4096;
    const int ProtocolVersion = 1;

    // shortcut: no pairing or encryption, so anyone on the network can send Play/Pause. Phase 2 adds QR pairing and TLS.
    public static WebApplication Create(int port, Action playPause)
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.ConfigureKestrel(kestrel => kestrel.ListenAnyIP(port));
        builder.Logging.AddFilter("Microsoft", LogLevel.Warning);
        var app = builder.Build();
        app.UseWebSockets();
        app.Map("/ws", async context =>
        {
            if (!context.WebSockets.IsWebSocketRequest)
            {
                context.Response.StatusCode = StatusCodes.Status400BadRequest;
                return;
            }
            using var socket = await context.WebSockets.AcceptWebSocketAsync();
            app.Logger.LogInformation("Phone connected from {Address}", context.Connection.RemoteIpAddress);
            try
            {
                await RunSessionAsync(socket, playPause, app.Logger, context.RequestAborted);
            }
            catch (Exception e) when (e is WebSocketException or OperationCanceledException)
            {
                // The phone left without saying goodbye, for example when its Wi-Fi dropped.
            }
            app.Logger.LogInformation("Phone disconnected");
        });
        return app;
    }

    /// <summary>Runs one message from the phone and returns the reply to send back, or null when there is none.</summary>
    public static string? Handle(ReadOnlySpan<byte> message, Action playPause)
    {
        if (!IsPlayPause(message))
        {
            return Error("Unknown message");
        }
        try
        {
            playPause();
            return null;
        }
        catch (PlatformNotSupportedException e)
        {
            return Error(e.Message);
        }
    }

    static async Task RunSessionAsync(WebSocket socket, Action playPause, ILogger logger, CancellationToken cancel)
    {
        await SendAsync(socket, Hello(), cancel);
        var buffer = new byte[MaxMessageBytes];
        while (true)
        {
            var result = await socket.ReceiveAsync(buffer, cancel);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, cancel);
                return;
            }
            if (!result.EndOfMessage)
            {
                await socket.CloseOutputAsync(WebSocketCloseStatus.MessageTooBig, "Message too big", cancel);
                return;
            }
            string? reply;
            try
            {
                reply = Handle(buffer.AsSpan(0, result.Count), playPause);
            }
            catch (Exception e)
            {
                logger.LogError(e, "An action from the phone failed");
                reply = Error("That did not work on the PC. The DeskPilot window shows why.");
            }
            if (reply is not null)
            {
                await SendAsync(socket, reply, cancel);
            }
        }
    }

    static bool IsPlayPause(ReadOnlySpan<byte> message)
    {
        try
        {
            using var document = JsonDocument.Parse(message.ToArray());
            var root = document.RootElement;
            return root.ValueKind == JsonValueKind.Object
                && HasString(root, "type", "media")
                && HasString(root, "action", "playPause");
        }
        catch (JsonException)
        {
            return false;
        }
    }

    static bool HasString(JsonElement json, string name, string expected) =>
        json.TryGetProperty(name, out var value)
        && value.ValueKind == JsonValueKind.String
        && value.ValueEquals(expected);

    static string Hello() =>
        JsonSerializer.Serialize(new { type = "hello", name = Environment.MachineName, version = ProtocolVersion });

    static string Error(string message) => JsonSerializer.Serialize(new { type = "error", message });

    static Task SendAsync(WebSocket socket, string json, CancellationToken cancel) =>
        socket.SendAsync(Encoding.UTF8.GetBytes(json), WebSocketMessageType.Text, endOfMessage: true, cancel);
}
