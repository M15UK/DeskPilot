using System.Collections.Frozen;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DeskPilot.Agent;

/// <summary>What a deck button does. The kinds are described in docs/PROTOCOL.md.</summary>
[JsonPolymorphic(TypeDiscriminatorPropertyName = "kind")]
[JsonDerivedType(typeof(MediaAction), "media")]
[JsonDerivedType(typeof(KeysAction), "keys")]
[JsonDerivedType(typeof(OpenAction), "open")]
[JsonDerivedType(typeof(StatAction), "stat")]
public abstract record ButtonAction;

/// <summary>A media key: playPause, next, previous, volumeUp, volumeDown or mute.</summary>
public sealed record MediaAction(string Media) : ButtonAction;

/// <summary>Key combos pressed one after another, like ["Ctrl+C", "Alt+Tab", "Ctrl+V"].</summary>
public sealed record KeysAction(IReadOnlyList<string> Combos) : ButtonAction;

/// <summary>Opens an app, file, folder or link, the way a double click would.</summary>
public sealed record OpenAction(string Target) : ButtonAction;

/// <summary>A tile that shows a PC reading from <see cref="PcStats"/> as a number, a gauge or a chart.</summary>
public sealed record StatAction(string Stat, string Style) : ButtonAction
{
    public static readonly FrozenSet<string> Styles = new[] { "number", "gauge", "chart" }.ToFrozenSet();
}

public sealed record DeckButton(string Id, string Label, ButtonAction Action);

public sealed record DeckPage(string Name, IReadOnlyList<DeckButton> Buttons);

/// <summary>The pages of buttons every paired phone shows. The PC keeps it and checks every change.</summary>
public sealed record Deck(IReadOnlyList<DeckPage> Pages)
{
    public const int MaxPages = 20;
    public const int MaxButtonsPerPage = 32;
    public const int MaxTextLength = 40;
    public const int MaxIdLength = 64;
    public const int MaxCombos = 20;
    public const int MaxTargetLength = 1000;

    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        // Writes "Ctrl+P", not "Ctrl+P". The stricter default only matters for JSON put inside web pages.
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        AllowOutOfOrderMetadataProperties = true,
        RespectNullableAnnotations = true,
        RespectRequiredConstructorParameters = true,
    };

    public static Deck Default { get; } = new([new DeckPage("Main",
    [
        new DeckButton("previous", "Previous", new MediaAction("previous")),
        new DeckButton("play-pause", "Play / Pause", new MediaAction("playPause")),
        new DeckButton("next", "Next", new MediaAction("next")),
        new DeckButton("volume-down", "Volume down", new MediaAction("volumeDown")),
        new DeckButton("mute", "Mute", new MediaAction("mute")),
        new DeckButton("volume-up", "Volume up", new MediaAction("volumeUp")),
    ]), new DeckPage("PC",
    [
        new DeckButton("cpu-load", "CPU", new StatAction("cpuLoad", "gauge")),
        new DeckButton("gpu-load", "GPU", new StatAction("gpuLoad", "gauge")),
        new DeckButton("gpu-temp", "GPU temperature", new StatAction("gpuTemp", "number")),
        new DeckButton("ram-load", "RAM", new StatAction("ramLoad", "gauge")),
        new DeckButton("cpu-chart", "CPU last minute", new StatAction("cpuLoad", "chart")),
    ])]);

    /// <summary>Reads and checks a deck. Returns null and says why when DeskPilot can't use it.</summary>
    public static Deck? Read(JsonElement json, out string? problem)
    {
        Deck? deck;
        try
        {
            deck = json.Deserialize<Deck>(Json);
        }
        catch (Exception e) when (e is JsonException or NotSupportedException)
        {
            deck = null;
        }
        problem = deck is null ? "That deck could not be read." : deck.Problem();
        return problem is null ? deck : null;
    }

    public DeckButton? Find(string id) =>
        Pages.SelectMany(page => page.Buttons).FirstOrDefault(button => button.Id == id);

    /// <summary>Why this deck can't be used, or null when it is fine.</summary>
    public string? Problem()
    {
        if (Pages.Count is 0 or > MaxPages)
        {
            return $"A deck needs 1 to {MaxPages} pages.";
        }
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var page in Pages)
        {
            if (page is null || !IsShortText(page.Name))
            {
                return $"Every page needs a name of 1 to {MaxTextLength} characters.";
            }
            if (page.Buttons.Count > MaxButtonsPerPage)
            {
                return $"A page can hold up to {MaxButtonsPerPage} buttons.";
            }
            foreach (var button in page.Buttons)
            {
                if (button is null || button.Id.Length is 0 or > MaxIdLength || !ids.Add(button.Id))
                {
                    return "Every button needs its own id.";
                }
                if (!IsShortText(button.Label))
                {
                    return $"Every button needs a label of 1 to {MaxTextLength} characters.";
                }
                if (!CanRun(button.Action))
                {
                    return $"DeskPilot can't run the button \"{button.Label}\". Check its keys or what it opens.";
                }
            }
        }
        return null;
    }

    static bool IsShortText(string text) => !string.IsNullOrWhiteSpace(text) && text.Length <= MaxTextLength;

    static bool CanRun(ButtonAction action) => action switch
    {
        MediaAction media => Media.Knows(media.Media),
        KeysAction keys => keys.Combos.Count is > 0 and <= MaxCombos
            && keys.Combos.All(combo => combo is not null && KeyCombo.Parse(combo) is not null),
        OpenAction open => !string.IsNullOrWhiteSpace(open.Target) && open.Target.Length <= MaxTargetLength,
        StatAction stat => PcStats.Names.Contains(stat.Stat) && StatAction.Styles.Contains(stat.Style),
        _ => false,
    };
}
