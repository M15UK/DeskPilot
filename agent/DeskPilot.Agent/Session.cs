using System.Net;
using System.Net.WebSockets;
using System.Text;

namespace DeskPilot.Agent;

/// <summary>
/// One phone's connection: signing in, then its messages, plus deck changes made on other phones
/// and the PC stats each second.
/// </summary>
sealed class Session(WebSocket socket, AgentServices services, ILogger logger, CancellationToken cancel)
{
    static readonly TimeSpan SignInTimeout = TimeSpan.FromSeconds(10);

    readonly byte[] buffer = new byte[AgentServer.MaxMessageBytes];
    // A WebSocket allows one send at a time, and deck changes and stats arrive while the phone is talking.
    readonly SemaphoreSlim sendLock = new(1, 1);
    // Telemetry arrives 30 times a second; on a slow link, drop a reading rather than queue them up.
    int sendingTelemetry;
    // The music card changes rarely and its cover is big: send only changes, and each cover once.
    string? sentMedia;
    string? sentCoverId;

    public async Task RunAsync(IPAddress? address)
    {
        byte[]? first;
        using (var signInTime = CancellationTokenSource.CreateLinkedTokenSource(cancel))
        {
            signInTime.CancelAfter(SignInTimeout);
            first = await ReceiveAsync(AgentServer.MaxSignInBytes, signInTime.Token);
        }
        if (first is null)
        {
            return;
        }
        var signIn = AgentServer.SignIn(first, services.Security);
        foreach (var reply in signIn.Replies)
        {
            await SendAsync(reply);
        }
        if (!signIn.Allowed)
        {
            logger.LogWarning("Refused a device at {Address} that is not paired", address);
            await CloseAsync(WebSocketCloseStatus.PolicyViolation, "Not paired");
            return;
        }

        logger.LogInformation("Phone connected from {Address}", address);
        services.Decks.Changed += OnDeckChanged;
        services.Stats.Updated += OnStats;
        services.Telemetry.Updated += OnTelemetry;
        services.Media.Updated += OnMedia;
        try
        {
            await SendAsync(AgentServer.DeckMessage(services.Decks.Current));
            while (await ReceiveAsync(AgentServer.MaxMessageBytes, cancel) is { } message)
            {
                if (await HandleSafelyAsync(message) is { } reply)
                {
                    await SendAsync(reply);
                }
            }
        }
        finally
        {
            services.Media.Updated -= OnMedia;
            services.Telemetry.Updated -= OnTelemetry;
            services.Stats.Updated -= OnStats;
            services.Decks.Changed -= OnDeckChanged;
            logger.LogInformation("Phone disconnected");
        }
    }

    void OnDeckChanged(Deck deck) => _ = SendQuietlyAsync(AgentServer.DeckMessage(deck));

    void OnStats(PcStats stats) => _ = SendQuietlyAsync(AgentServer.StatsMessage(stats));

    void OnTelemetry(SimTelemetry telemetry)
    {
        if (Interlocked.Exchange(ref sendingTelemetry, 1) == 1)
        {
            return;
        }
        _ = SendTelemetryAsync(AgentServer.TelemetryMessage(telemetry));
    }

    void OnMedia(NowPlaying media)
    {
        // The media feed calls this once a second from one timer, never twice at the same time.
        var withoutCover = AgentServer.MediaMessage(media, withCover: false);
        if (withoutCover == sentMedia)
        {
            return;
        }
        var newCover = media.CoverId != sentCoverId;
        sentMedia = withoutCover;
        sentCoverId = media.CoverId;
        _ = SendQuietlyAsync(newCover ? AgentServer.MediaMessage(media, withCover: true) : withoutCover);
    }

    async Task SendTelemetryAsync(string json)
    {
        try
        {
            await SendQuietlyAsync(json);
        }
        finally
        {
            Volatile.Write(ref sendingTelemetry, 0);
        }
    }

    async Task SendQuietlyAsync(string json)
    {
        try
        {
            await SendAsync(json);
        }
        catch (Exception e) when (e is WebSocketException or OperationCanceledException or ObjectDisposedException)
        {
            // This phone is leaving, and its session ends on its own.
        }
    }

    async Task<string?> HandleSafelyAsync(byte[] message)
    {
        try
        {
            return await AgentServer.HandleAsync(message, services.Decks, services.Images, services.Run);
        }
        catch (Exception e)
        {
            logger.LogError(e, "A button from the phone failed");
            return AgentServer.Error("That did not work on the PC. The DeskPilot window shows why.");
        }
    }

    /// <summary>Reads one whole message of up to <paramref name="limit"/> bytes. Returns null after closing.</summary>
    async Task<byte[]?> ReceiveAsync(int limit, CancellationToken token)
    {
        var count = 0;
        while (count < limit)
        {
            var result = await socket.ReceiveAsync(buffer.AsMemory(count, limit - count), token);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                await CloseAsync(WebSocketCloseStatus.NormalClosure, null);
                return null;
            }
            count += result.Count;
            if (result.EndOfMessage)
            {
                return buffer[..count];
            }
        }
        await CloseAsync(WebSocketCloseStatus.MessageTooBig, "Message too big");
        return null;
    }

    async Task SendAsync(string json)
    {
        await sendLock.WaitAsync(cancel);
        try
        {
            await socket.SendAsync(Encoding.UTF8.GetBytes(json), WebSocketMessageType.Text, endOfMessage: true, cancel);
        }
        finally
        {
            sendLock.Release();
        }
    }

    async Task CloseAsync(WebSocketCloseStatus status, string? reason)
    {
        await sendLock.WaitAsync(cancel);
        try
        {
            await socket.CloseOutputAsync(status, reason, cancel);
        }
        finally
        {
            sendLock.Release();
        }
    }
}
