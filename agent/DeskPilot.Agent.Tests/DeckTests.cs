using System.Text.Json;

namespace DeskPilot.Agent.Tests;

public class KeyComboTests
{
    [Fact]
    public void ReadsACombo() =>
        Assert.Equal(new ushort[] { 0x11, 0x10, 'M' }, KeyCombo.Parse("Ctrl+Shift+M"));

    [Fact]
    public void IgnoresCaseAndSpaces() =>
        Assert.Equal(new ushort[] { 0x12, 0x09 }, KeyCombo.Parse(" alt + TAB "));

    [Fact]
    public void KnowsFunctionKeysUpToF24() =>
        Assert.Equal(new ushort[] { 0x7C, 0x87 }, KeyCombo.Parse("F13+F24"));

    [Theory]
    [InlineData("")]
    [InlineData("Ctrl+")]
    [InlineData("Ctrl+Banana")]
    [InlineData("A+B+C+D+E+F+G")]
    public void RefusesUnknownKeys(string combo) => Assert.Null(KeyCombo.Parse(combo));

    [Fact]
    public void PressesKeysDownInOrderAndLetsGoInReverse()
    {
        var expected = new (ushort Key, bool Up)[] { (0x11, false), (0x43, false), (0x43, true), (0x11, true) };

        Assert.Equal(expected, Keyboard.Strokes([0x11, 0x43]));
    }

    [Fact]
    public void TheWindowsInputLayoutHasTheSizeWindowsExpects() =>
        Assert.Equal(Environment.Is64BitProcess ? 40 : 28, Keyboard.InputSize);
}

public class DeckTests
{
    static string Json(Deck deck) => JsonSerializer.Serialize(deck, Deck.Json);

    [Fact]
    public void TheStartingDeckIsValid() => Assert.Null(Deck.Default.Problem());

    [Fact]
    public void TheJsonMatchesWhatThePhoneAppReads()
    {
        // The same text as pcDeck in app/test/deck_test.dart.
        const string expected =
            """{"pages":[{"name":"Main","buttons":[""" +
            """{"id":"previous","label":"Previous","action":{"kind":"media","media":"previous"}},""" +
            """{"id":"play-pause","label":"Play / Pause","action":{"kind":"media","media":"playPause"}},""" +
            """{"id":"pit","label":"Pit","action":{"kind":"keys","combos":["Ctrl+P","Enter"]},"icon":"flag","color":"amber"},""" +
            """{"id":"ac","label":"Assetto Corsa","action":{"kind":"open","target":"steam://rungameid/244210"}},""" +
            """{"id":"cpu","label":"CPU","action":{"kind":"stat","stat":"cpuLoad","style":"gauge"}}""" +
            """]}]}""";
        var deck = new Deck([new DeckPage("Main",
        [
            new DeckButton("previous", "Previous", new MediaAction("previous")),
            new DeckButton("play-pause", "Play / Pause", new MediaAction("playPause")),
            new DeckButton("pit", "Pit", new KeysAction(["Ctrl+P", "Enter"]), Icon: "flag", Color: "amber"),
            new DeckButton("ac", "Assetto Corsa", new OpenAction("steam://rungameid/244210")),
            new DeckButton("cpu", "CPU", new StatAction("cpuLoad", "gauge")),
        ])]);

        Assert.Equal(expected, Json(deck));
    }

    [Fact]
    public void ADeckSurvivesAJsonRoundTrip()
    {
        var json = Json(Deck.Default);

        var back = Deck.Read(JsonDocument.Parse(json).RootElement, out var problem);

        Assert.Null(problem);
        Assert.Equal(json, Json(back!));
        Assert.Contains("\"kind\":\"media\"", json);
    }

    [Theory]
    [InlineData("""{"pages":[]}""")]
    [InlineData("""{"pages":[{"name":"","buttons":[]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"explode"}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"keys","combos":[]}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"keys","combos":["Ctrl+Banana"]}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"open","target":" "}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"next"}},{"id":"a","label":"B","action":{"kind":"media","media":"next"}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"shell","command":"format c:"}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","action":{"kind":"media","media":"next"}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"stat","stat":"cpuSpeed","style":"gauge"}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"stat","stat":"cpuLoad","style":"dial"}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"next"},"color":"rainbow"}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"next"},"icon":"../../x"}]}]}""")]
    [InlineData("""["not","a","deck"]""")]
    public void BadDecksAreRefused(string json)
    {
        var deck = Deck.Read(JsonDocument.Parse(json).RootElement, out var problem);

        Assert.Null(deck);
        Assert.False(string.IsNullOrWhiteSpace(problem));
    }

    [Fact]
    public void APageWithTooManyButtonsIsRefused()
    {
        var buttons = Enumerable.Range(0, Deck.MaxButtonsPerPage + 1)
            .Select(i => new DeckButton($"b{i}", "Next", new MediaAction("next")))
            .ToArray();

        Assert.NotNull(new Deck([new DeckPage("Main", buttons)]).Problem());
    }
}

public class DeckStoreTests
{
    static readonly Deck Racing = new([new DeckPage("Racing", [new DeckButton("pit", "Pit", new KeysAction(["P"]))])]);

    [Fact]
    public void StartsWithTheStartingDeck()
    {
        using var folder = new TempFolder();

        Assert.Same(Deck.Default, new DeckStore(System.IO.Path.Combine(folder.Path, "deck.json")).Current);
    }

    [Fact]
    public void ASavedDeckIsAnnouncedAndKeptAfterARestart()
    {
        using var folder = new TempFolder();
        var file = System.IO.Path.Combine(folder.Path, "deck.json");
        var store = new DeckStore(file);
        Deck? announced = null;
        store.Changed += deck => announced = deck;

        store.Save(Racing);

        Assert.Same(Racing, announced);
        Assert.Equal(JsonSerializer.Serialize(Racing, Deck.Json),
            JsonSerializer.Serialize(new DeckStore(file).Current, Deck.Json));
    }
}
