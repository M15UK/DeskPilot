using System.Security.Cryptography;

namespace DeskPilot.Agent;

/// <summary>
/// The song the PC is playing, for the phone's music card. Times are in seconds and are null when the app doesn't
/// say how long the song is. <see cref="Cover"/> is the album art as base64 (JPEG or PNG, as the app gave it), and
/// <see cref="CoverId"/> changes whenever the picture does, so the phone only gets each picture once.
/// </summary>
public sealed record NowPlaying(
    string Title,
    string Artist,
    string App,
    bool Playing,
    double? Position,
    double? Duration,
    string? CoverId,
    string? Cover)
{
    /// <summary>Album art bigger than this is left out rather than slowing the phone's connection.</summary>
    public const int MaxCoverBytes = 512 * 1024;

    /// <summary>Nothing is playing: the phone hides its music card.</summary>
    public static NowPlaying Nothing { get; } = new("", "", "", false, null, null, null, null);

    /// <summary>
    /// Builds the card from what Windows' media session says. Windows only updates the position now and then, so a
    /// playing song's position moves on by the time since <paramref name="updated"/>.
    /// </summary>
    public static NowPlaying From(string title, string artist, string appId, bool playing, TimeSpan position,
        TimeSpan length, DateTimeOffset updated, DateTimeOffset now, byte[]? cover)
    {
        double? duration = length > TimeSpan.Zero ? Math.Round(length.TotalSeconds, 1) : null;
        var at = position + (playing && now > updated ? now - updated : TimeSpan.Zero);
        double? where = duration is { } end ? Math.Round(Math.Clamp(at.TotalSeconds, 0, end), 1) : null;
        var picture = cover is { Length: > 0 and <= MaxCoverBytes } ? cover : null;
        return new(title, artist, AppName(appId), playing, where, duration,
            picture is null ? null : Convert.ToHexStringLower(SHA256.HashData(picture))[..16],
            picture is null ? null : Convert.ToBase64String(picture));
    }

    /// <summary>A short name from Windows' app id: "Spotify.exe" and "SpotifyAB.SpotifyMusic_x!Spotify" are "Spotify".</summary>
    public static string AppName(string appId)
    {
        var name = appId[(appId.LastIndexOf('!') + 1)..];
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
        {
            name = name[..^4];
        }
        return name[(name.LastIndexOf('.') + 1)..];
    }
}

/// <summary>Reads what's playing from Windows' media session (Spotify, browsers, most players). Elsewhere it reads nothing.</summary>
public sealed partial class NowPlayingReader(TimeProvider time)
{
    readonly TimeProvider time = time;

    public NowPlaying? Read() => OperatingSystem.IsWindows() ? ReadWindows() : null;
}
