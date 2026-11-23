#if WINDOWS
using System.Runtime.InteropServices;
using Windows.Media.Control;
using Windows.Storage.Streams;
#endif

namespace DeskPilot.Agent;

public sealed partial class NowPlayingReader
{
#if WINDOWS
    GlobalSystemMediaTransportControlsSessionManager? manager;
    // The album art is read once per song, not every second.
    string? coverFor;
    byte[]? cover;

    NowPlaying? ReadWindows()
    {
        try
        {
            manager ??= GlobalSystemMediaTransportControlsSessionManager.RequestAsync().AsTask().GetAwaiter().GetResult();
            if (manager.GetCurrentSession() is not { } session)
            {
                return NowPlaying.Nothing;
            }
            var song = session.TryGetMediaPropertiesAsync().AsTask().GetAwaiter().GetResult();
            if (song is null || string.IsNullOrWhiteSpace(song.Title))
            {
                return NowPlaying.Nothing;
            }
            var key = $"{session.SourceAppUserModelId}\n{song.Title}\n{song.Artist}";
            if (key != coverFor)
            {
                cover = ReadCover(song.Thumbnail);
                coverFor = key;
            }
            var timeline = session.GetTimelineProperties();
            var playing = session.GetPlaybackInfo().PlaybackStatus
                == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            return NowPlaying.From(song.Title, song.Artist, session.SourceAppUserModelId, playing,
                timeline.Position - timeline.StartTime, timeline.EndTime - timeline.StartTime,
                timeline.LastUpdatedTime, time.GetUtcNow(), cover);
        }
        catch (COMException)
        {
            // The media session can be busy or gone for a moment, for example while a player closes. Ask again next time.
            manager = null;
            return null;
        }
    }

    static byte[]? ReadCover(IRandomAccessStreamReference? thumbnail)
    {
        if (thumbnail is null)
        {
            return null;
        }
        try
        {
            using var stream = thumbnail.OpenReadAsync().AsTask().GetAwaiter().GetResult();
            if (stream.Size is 0 or > NowPlaying.MaxCoverBytes)
            {
                return null;
            }
            using var read = stream.AsStreamForRead();
            using var bytes = new MemoryStream();
            read.CopyTo(bytes);
            return bytes.ToArray();
        }
        catch (Exception e) when (e is COMException or IOException)
        {
            // The player gave a picture it can't hand over. Show the song without it rather than not at all.
            return null;
        }
    }
#else
    static NowPlaying? ReadWindows() => null;
#endif
}
