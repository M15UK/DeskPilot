using System.Net;
using System.Net.WebSockets;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;

namespace DeskPilot.Agent;

/// <summary>What keeps strangers out: the agent's certificate, the pairing code and the paired phones.</summary>
public sealed record AgentSecurity(X509Certificate2 Certificate, PairingCodes Codes, PairedPhones Phones);

/// <summary>The result of a phone's first message: whether it may stay, and what to send it.</summary>
public sealed record SignInResult(bool Allowed, IReadOnlyList<string> Replies);

/// <summary>The encrypted WebSocket the phone app connects to. The messages are described in docs/PROTOCOL.md.</summary>
public static class AgentServer
{
    public const int DefaultPort = 8740;
    public const int MaxMessageBytes = 4096;
    public const int ProtocolVersion = 2;
    static readonly TimeSpan SignInTimeout = TimeSpan.FromSeconds(10);

    public static WebApplication Create(int port, AgentSecurity security, Action playPause)
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.ConfigureKestrel(kestrel =>
            kestrel.ListenAnyIP(port, listen => listen.UseHttps(security.Certificate)));
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
            try
            {
                await RunSessionAsync(socket, security, playPause, app.Logger,
                    context.Connection.RemoteIpAddress, context.RequestAborted);
            }
            catch (Exception e) when (e is WebSocketException or OperationCanceledException)
            {
                // The phone left without saying goodbye or never signed in, for example when its Wi-Fi dropped.
            }
        });
        return app;
    }

    /// <summary>Checks a phone's first message: the code from the pairing QR code, or the key it got when it paired.</summary>
    public static SignInResult SignIn(ReadOnlySpan<byte> message, AgentSecurity security)
    {
        var request = ParseObject(message);
        var type = Text(request, "type");
        if (type == "auth" && Text(request, "key") is { } key && security.Phones.IsKnown(key))
        {
            return new(true, [Hello()]);
        }
        if (type == "pair" && Text(request, "code") is { } code && security.Codes.TryUse(code))
        {
            return new(true, [Paired(security.Phones.Add()), Hello()]);
        }
        return new(false, [Error(type == "pair"
            ? "This QR code is used up or too old. Press Enter on the PC for a new one."
            : "This phone is not paired with this PC. Pair it again.")]);
    }

    /// <summary>Runs one message from a signed in phone and returns the reply, or null when there is none.</summary>
    public static string? Handle(ReadOnlySpan<byte> message, Action playPause)
    {
        var request = ParseObject(message);
        if (Text(request, "type") != "media" || Text(request, "action") != "playPause")
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

    static async Task RunSessionAsync(WebSocket socket, AgentSecurity security, Action playPause, ILogger logger,
        IPAddress? address, CancellationToken cancel)
    {
        var buffer = new byte[MaxMessageBytes];
        byte[]? first;
        using (var signInTime = CancellationTokenSource.CreateLinkedTokenSource(cancel))
        {
            signInTime.CancelAfter(SignInTimeout);
            first = await ReceiveAsync(socket, buffer, signInTime.Token);
        }
        if (first is null)
        {
            return;
        }
        var signIn = SignIn(first, security);
        foreach (var reply in signIn.Replies)
        {
            await SendAsync(socket, reply, cancel);
        }
        if (!signIn.Allowed)
        {
            logger.LogWarning("Refused a device at {Address} that is not paired", address);
            await socket.CloseOutputAsync(WebSocketCloseStatus.PolicyViolation, "Not paired", cancel);
            return;
        }

        logger.LogInformation("Phone connected from {Address}", address);
        try
        {
            while (await ReceiveAsync(socket, buffer, cancel) is { } message)
            {
                var reply = HandleSafely(message, playPause, logger);
                if (reply is not null)
                {
                    await SendAsync(socket, reply, cancel);
                }
            }
        }
        finally
        {
            logger.LogInformation("Phone disconnected");
        }
    }

    /// <summary>Reads one message. Returns null after closing, when the phone closed or sent too much.</summary>
    static async Task<byte[]?> ReceiveAsync(WebSocket socket, byte[] buffer, CancellationToken cancel)
    {
        var result = await socket.ReceiveAsync(buffer, cancel);
        if (result.MessageType == WebSocketMessageType.Close)
        {
            await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, cancel);
            return null;
        }
        if (!result.EndOfMessage)
        {
            await socket.CloseOutputAsync(WebSocketCloseStatus.MessageTooBig, "Message too big", cancel);
            return null;
        }
        return buffer[..result.Count];
    }

    static string? HandleSafely(byte[] message, Action playPause, ILogger logger)
    {
        try
        {
            return Handle(message, playPause);
        }
        catch (Exception e)
        {
            logger.LogError(e, "An action from the phone failed");
            return Error("That did not work on the PC. The DeskPilot window shows why.");
        }
    }

    static JsonElement? ParseObject(ReadOnlySpan<byte> message)
    {
        try
        {
            using var document = JsonDocument.Parse(message.ToArray());
            return document.RootElement.ValueKind == JsonValueKind.Object ? document.RootElement.Clone() : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    static string? Text(JsonElement? json, string name) =>
        json is { } value && value.TryGetProperty(name, out var field) && field.ValueKind == JsonValueKind.String
            ? field.GetString()
            : null;

    static string Hello() =>
        JsonSerializer.Serialize(new { type = "hello", name = Environment.MachineName, version = ProtocolVersion });

    static string Paired(string key) => JsonSerializer.Serialize(new { type = "paired", key });

    static string Error(string message) => JsonSerializer.Serialize(new { type = "error", message });

    static Task SendAsync(WebSocket socket, string json, CancellationToken cancel) =>
        socket.SendAsync(Encoding.UTF8.GetBytes(json), WebSocketMessageType.Text, endOfMessage: true, cancel);
}
