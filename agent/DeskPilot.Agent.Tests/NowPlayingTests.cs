namespace DeskPilot.Agent.Tests;

public class NowPlayingTests
{
    static readonly DateTimeOffset Now = new(2026, 11, 23, 21, 42, 0, TimeSpan.Zero);

    static NowPlaying Song(bool playing = true, double position = 30, double length = 240, double secondsAgo = 5,
        byte[]? cover = null) =>
        NowPlaying.From("Neon Highway", "The Midnight Drive", "Spotify.exe", playing,
            TimeSpan.FromSeconds(position), TimeSpan.FromSeconds(length), Now.AddSeconds(-secondsAgo), Now, cover);

    [Theory]
    [InlineData("Spotify.exe", "Spotify")]
    [InlineData("SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", "Spotify")]
    [InlineData("Chrome", "Chrome")]
    [InlineData("Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic", "ZuneMusic")]
    public void NamesTheAppPlaying(string appId, string name) => Assert.Equal(name, NowPlaying.AppName(appId));

    [Fact]
    public void APlayingSongKeepsMovingBetweenWindowsUpdates()
    {
        var song = Song();

        Assert.Equal(35, song.Position);
        Assert.Equal(240, song.Duration);
    }

    [Fact]
    public void APausedSongStaysWhereItStopped() => Assert.Equal(30, Song(playing: false).Position);

    [Fact]
    public void ThePositionNeverPassesTheEnd() => Assert.Equal(240, Song(position: 239, secondsAgo: 10).Position);

    [Fact]
    public void WithoutALengthThereIsNoProgress()
    {
        var song = Song(length: 0);

        Assert.Null(song.Position);
        Assert.Null(song.Duration);
    }

    [Fact]
    public void TheCoverIsSentAsTextWithAnIdThatChangesWithThePicture()
    {
        var first = Song(cover: [1, 2, 3]);
        var other = Song(cover: [1, 2, 4]);

        Assert.Equal("AQID", first.Cover);
        Assert.NotNull(first.CoverId);
        Assert.NotEqual(first.CoverId, other.CoverId);
    }

    [Fact]
    public void AHugeCoverIsLeftOut()
    {
        var song = Song(cover: new byte[NowPlaying.MaxCoverBytes + 1]);

        Assert.Null(song.Cover);
        Assert.Null(song.CoverId);
    }

    [Fact]
    public void NothingPlayingClearsTheMusicCard() =>
        Assert.Equal("""{"type":"media"}""", AgentServer.MediaMessage(NowPlaying.Nothing, withCover: true));
}
