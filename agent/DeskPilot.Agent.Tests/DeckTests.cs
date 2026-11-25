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
            """{"id":"pit","label":"Pit","action":{"kind":"keys","combos":["Ctrl+P","Enter"]},"icon":"flag","color":"amber","show":"icon","image":"0123456789abcdef"},""" +
            """{"id":"ac","label":"Assetto Corsa","action":{"kind":"open","target":"steam://rungameid/244210"}},""" +
            """{"id":"cpu","label":"CPU","action":{"kind":"stat","stat":"cpuLoad","style":"gauge"},"size":"wide","style":"outline"}""" +
            """],"size":"large","icon":"home","background":"blue","wallpaper":"fedcba9876543210"}]}""";
        var deck = new Deck([new DeckPage("Main",
        [
            new DeckButton("previous", "Previous", new MediaAction("previous")),
            new DeckButton("play-pause", "Play / Pause", new MediaAction("playPause")),
            new DeckButton("pit", "Pit", new KeysAction(["Ctrl+P", "Enter"]), Icon: "flag", Color: "amber", Show: "icon",
                Image: "0123456789abcdef"),
            new DeckButton("ac", "Assetto Corsa", new OpenAction("steam://rungameid/244210")),
            new DeckButton("cpu", "CPU", new StatAction("cpuLoad", "gauge"), Size: "wide", Style: "outline"),
        ], Size: "large", Icon: "home", Background: "blue",
            Wallpaper: "fedcba9876543210")]);

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
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"next"},"size":"1x9"}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[],"size":"gigantic"}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[],"background":"plaid"}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"next"},"style":"glitter"}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"next"},"show":"nothing"}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"f","label":"Streaming","action":{"kind":"folder","buttons":[{"id":"inner","label":"Inner","action":{"kind":"folder","buttons":[]}}]}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"f","label":"Streaming","action":{"kind":"folder","buttons":[{"id":"f","label":"Same id","action":{"kind":"media","media":"next"}}]}}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"next"},"image":"../x"}]}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[],"wallpaper":"C:\\Windows"}]}""")]
    [InlineData("""{"pages":[{"name":"Main","buttons":[{"id":"p","label":"P","action":{"kind":"photos","pictures":["../../etc"]}}]}]}""")]
    [InlineData("""["not","a","deck"]""")]
    public void BadDecksAreRefused(string json)
    {
        var deck = Deck.Read(JsonDocument.Parse(json).RootElement, out var problem);

        Assert.Null(deck);
        Assert.False(string.IsNullOrWhiteSpace(problem));
    }

    [Fact]
    public void AFolderKeepsItsButtons()
    {
        const string json = """{"pages":[{"name":"Main","buttons":[{"id":"f","label":"Streaming","action":{"kind":"folder","buttons":[{"id":"obs","label":"OBS","action":{"kind":"open","target":"obs64.exe"}}]}}]}]}""";

        var deck = Deck.Read(JsonDocument.Parse(json).RootElement, out var problem);

        Assert.Null(problem);
        Assert.Equal(json, Json(deck!));
        Assert.Equal(new OpenAction("obs64.exe"), deck!.Find("obs")!.Action);
    }

    [Fact]
    public void MusicClockAndPhotoWidgetsAreButtonsToo()
    {
        const string json =
            """{"pages":[{"name":"Home","buttons":[""" +
            """{"id":"m","label":"Music","action":{"kind":"music"},"size":"wider"},""" +
            """{"id":"c","label":"Clock","action":{"kind":"clock"},"size":"huge"},""" +
            """{"id":"p","label":"Photos","action":{"kind":"photos","pictures":["0123456789abcdef"]},"size":"big"},""" +
            """{"id":"t","label":"Tyres","action":{"kind":"tyres"}}""" +
            """]}]}""";

        var deck = Deck.Read(JsonDocument.Parse(json).RootElement, out var problem);

        Assert.Null(problem);
        Assert.Equal(json, Json(deck!));
        Assert.IsType<MusicAction>(deck!.Find("m")!.Action);
    }

    [Fact]
    public void AButtonCanSitAnywhereAtAnySize()
    {
        const string json =
            """{"pages":[{"name":"Home","buttons":[""" +
            """{"id":"m","label":"Music","action":{"kind":"music"},"x":2,"y":3,"w":4,"h":2}""" +
            """]}]}""";

        var deck = Deck.Read(JsonDocument.Parse(json).RootElement, out var problem);

        Assert.Null(problem);
        Assert.Equal(json, Json(deck!));
    }

    [Fact]
    public void AButtonCanHaveAnySizeInEighthsOfACell()
    {
        const string json =
            """{"pages":[{"name":"Home","buttons":[""" +
            """{"id":"c","label":"Clock","action":{"kind":"clock"},"left":3,"top":20,"width":21,"height":10}""" +
            """]}]}""";

        var deck = Deck.Read(JsonDocument.Parse(json).RootElement, out var problem);

        Assert.Null(problem);
        Assert.Equal(json, Json(deck!));
    }

    [Theory]
    [InlineData("\"left\":-1,\"top\":0")]
    [InlineData("\"width\":2,\"height\":8")]
    [InlineData("\"width\":97,\"height\":8")]
    [InlineData("\"left\":100,\"width\":40")]
    public void AFinePlaceOffTheGridIsRefused(string place)
    {
        var json = $$"""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"next"},{{place}}}]}]}""";

        Assert.Null(Deck.Read(JsonDocument.Parse(json).RootElement, out _));
    }

    [Theory]
    [InlineData("\"x\":-1,\"y\":0")]
    [InlineData("\"x\":0,\"y\":500")]
    [InlineData("\"w\":0,\"h\":1")]
    [InlineData("\"w\":20,\"h\":1")]
    [InlineData("\"x\":10,\"w\":8")]
    public void APlaceOffTheGridIsRefused(string place)
    {
        var json = $$"""{"pages":[{"name":"Main","buttons":[{"id":"a","label":"A","action":{"kind":"media","media":"next"},{{place}}}]}]}""";

        Assert.Null(Deck.Read(JsonDocument.Parse(json).RootElement, out _));
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
