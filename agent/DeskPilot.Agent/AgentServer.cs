using System.Net.WebSockets;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

namespace DeskPilot.Agent;

/// <summary>What keeps strangers out: the agent's certificate, the pairing code and the paired phones.</summary>
public sealed record AgentSecurity(X509Certificate2 Certificate, PairingCodes Codes, PairedPhones Phones);

/// <summary>Everything a phone's session works with.</summary>
public sealed record AgentServices(AgentSecurity Security, DeckStore Decks, StatsFeed Stats, Func<ButtonAction, Task> Run);

/// <summary>The result of a phone's first message: whether it may stay, and what to send it.</summary>
public sealed record SignInResult(bool Allowed, IReadOnlyList<string> Replies);

/// <summary>The encrypted WebSocket the phone app connects to. The messages are described in docs/PROTOCOL.md.</summary>
public static class AgentServer
{
    public const int DefaultPort = 8740;
    public const int MaxSignInBytes = 4096;
    public const int MaxMessageBytes = 1024 * 1024;
    public const int ProtocolVersion = 4;

    public static WebApplication Create(int port, AgentServices services)
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.ConfigureKestrel(kestrel =>
            kestrel.ListenAnyIP(port, listen => listen.UseHttps(services.Security.Certificate)));
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
            var session = new Session(socket, services, app.Logger, context.RequestAborted);
            try
            {
                await session.RunAsync(context.Connection.RemoteIpAddress);
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
    public static async Task<string?> HandleAsync(ReadOnlyMemory<byte> message, DeckStore decks, Func<ButtonAction, Task> run)
    {
        var request = ParseObject(message.Span);
        switch (Text(request, "type"))
        {
            case "press" when Text(request, "id") is { } id:
                if (decks.Current.Find(id) is not { } button)
                {
                    return Error("That button is not on the deck any more.");
                }
                try
                {
                    await run(button.Action);
                    return null;
                }
                catch (PlatformNotSupportedException e)
                {
                    return Error(e.Message);
                }
            case "saveDeck" when request is { } body && body.TryGetProperty("deck", out var json):
                if (Deck.Read(json, out var problem) is not { } deck)
                {
                    return Error(problem!);
                }
                decks.Save(deck);
                return null;
            default:
                return Error("Unknown message");
        }
    }

    internal static string DeckMessage(Deck deck) => JsonSerializer.Serialize(new { type = "deck", deck }, Deck.Json);

    public static string StatsMessage(PcStats stats) =>
        JsonSerializer.Serialize(new { type = "stats", stats }, PcStats.Json);

    internal static string Error(string message) => JsonSerializer.Serialize(new { type = "error", message });

    static string Hello() =>
        JsonSerializer.Serialize(new { type = "hello", name = Environment.MachineName, version = ProtocolVersion });

    static string Paired(string key) => JsonSerializer.Serialize(new { type = "paired", key });

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
}
