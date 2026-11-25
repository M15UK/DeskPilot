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
[JsonDerivedType(typeof(FolderAction), "folder")]
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

/// <summary>
/// A button on a page. <paramref name="Icon"/> names an icon the phone app knows, and <paramref name="Color"/> is one
/// of <see cref="Colors"/>. Left out, the phone picks both from what the button does. <paramref name="Size"/> is one
/// of <see cref="Sizes"/>: two places wide, two tall, or both. Left out, the button takes one place.
/// <paramref name="Style"/> is one of <see cref="Styles"/> (left out: tinted), and <paramref name="Show"/> one of
/// <see cref="Shows"/> (left out: icon and label). <paramref name="Image"/> is the id of a picture in the
/// <see cref="ImageStore"/>, shown instead of the icon.
/// </summary>
/// <summary>A button that opens more buttons on the phone, with a way back. Folders don't hold folders.</summary>
public sealed record FolderAction(IReadOnlyList<DeckButton> Buttons) : ButtonAction;

public sealed record DeckButton(
    string Id,
    string Label,
    ButtonAction Action,
    string? Icon = null,
    string? Color = null,
    string? Size = null,
    string? Style = null,
    string? Show = null,
    string? Image = null)
{
    public static readonly FrozenSet<string> Styles = new[] { "solid", "outline" }.ToFrozenSet();

    public static readonly FrozenSet<string> Shows = new[] { "icon", "name" }.ToFrozenSet();

    public static readonly FrozenSet<string> Colors =
        new[] { "red", "amber", "green", "teal", "blue", "purple", "pink", "gray" }.ToFrozenSet();

    public static readonly FrozenSet<string> Sizes = new[] { "wide", "tall", "big" }.ToFrozenSet();
}

/// <summary>
/// A page of buttons. <paramref name="Size"/> is one of <see cref="Sizes"/> (left out: medium). <paramref name="Icon"/>
/// is the page's icon in the phone's page rail, and <paramref name="Background"/> one of
/// <see cref="DeckButton.Colors"/>. <paramref name="Wallpaper"/> is the id of a picture behind the buttons.
/// </summary>
public sealed record DeckPage(
    string Name,
    IReadOnlyList<DeckButton> Buttons,
    string? Size = null,
    string? Icon = null,
    string? Background = null,
    string? Wallpaper = null)
{
    public static readonly FrozenSet<string> Sizes = new[] { "small", "medium", "large", "huge" }.ToFrozenSet();
}

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
        // A button without its own icon or color leaves them out instead of writing null.
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
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
        new DeckButton("cpu-chart", "CPU last minute", new StatAction("cpuLoad", "chart"), Size: "wide"),
    ]), new DeckPage("Racing",
    [
        new DeckButton("sim-gear", "Gear", new StatAction("gear", "number")),
        new DeckButton("sim-speed", "Speed km/h", new StatAction("speed", "number")),
        new DeckButton("sim-rpm", "RPM", new StatAction("rpm", "gauge")),
        new DeckButton("sim-lap-time", "Lap time", new StatAction("lapTime", "number")),
        new DeckButton("sim-best-lap", "Best lap", new StatAction("bestLap", "number")),
        new DeckButton("sim-position", "Position", new StatAction("position", "number")),
        new DeckButton("sim-fuel", "Fuel", new StatAction("fuel", "gauge")),
        new DeckButton("sim-tyre-fl", "Front left tyre", new StatAction("tyreFlTemp", "number")),
        new DeckButton("sim-tyre-fr", "Front right tyre", new StatAction("tyreFrTemp", "number")),
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

    /// <summary>The button with this id, on a page or inside a folder.</summary>
    public DeckButton? Find(string id) =>
        Pages.SelectMany(page => page.Buttons)
            .SelectMany(button => button.Action is FolderAction folder ? folder.Buttons.Prepend(button) : [button])
            .FirstOrDefault(button => button.Id == id);

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
            if (page.Size is not null && !DeckPage.Sizes.Contains(page.Size)
                || page.Icon is not null && !IsIconName(page.Icon)
                || page.Background is not null && !DeckButton.Colors.Contains(page.Background)
                || page.Wallpaper is not null && !ImageStore.IsId(page.Wallpaper))
            {
                return $"The page \"{page.Name}\" has a size, icon or background DeskPilot doesn't know.";
            }
            if (page.Buttons.Count > MaxButtonsPerPage)
            {
                return $"A page can hold up to {MaxButtonsPerPage} buttons.";
            }
            if (ButtonsProblem(page.Buttons, ids, inFolder: false) is { } problem)
            {
                return problem;
            }
        }
        return null;
    }

    /// <summary>Why one of these buttons can't be used, looking inside folders too. Ids must be unique deck wide.</summary>
    static string? ButtonsProblem(IReadOnlyList<DeckButton> buttons, HashSet<string> ids, bool inFolder)
    {
        foreach (var button in buttons)
        {
            if (button is null || button.Id.Length is 0 or > MaxIdLength || !ids.Add(button.Id))
            {
                return "Every button needs its own id.";
            }
            if (!IsShortText(button.Label))
            {
                return $"Every button needs a label of 1 to {MaxTextLength} characters.";
            }
            if (button.Icon is not null && !IsIconName(button.Icon)
                || button.Color is not null && !DeckButton.Colors.Contains(button.Color)
                || button.Size is not null && !DeckButton.Sizes.Contains(button.Size)
                || button.Style is not null && !DeckButton.Styles.Contains(button.Style)
                || button.Show is not null && !DeckButton.Shows.Contains(button.Show)
                || button.Image is not null && !ImageStore.IsId(button.Image))
            {
                return $"The button \"{button.Label}\" has a look DeskPilot doesn't know.";
            }
            if (button.Action is FolderAction folder)
            {
                if (inFolder)
                {
                    return $"The folder \"{button.Label}\" is inside another folder. Folders hold buttons only.";
                }
                if (folder.Buttons.Count > MaxButtonsPerPage)
                {
                    return $"A folder can hold up to {MaxButtonsPerPage} buttons.";
                }
                if (ButtonsProblem(folder.Buttons, ids, inFolder: true) is { } problem)
                {
                    return problem;
                }
            }
            else if (!CanRun(button.Action))
            {
                return $"DeskPilot can't run the button \"{button.Label}\". Check its keys or what it opens.";
            }
        }
        return null;
    }

    static bool IsShortText(string text) => !string.IsNullOrWhiteSpace(text) && text.Length <= MaxTextLength;

    static bool IsIconName(string icon) =>
        icon.Length is > 0 and <= MaxTextLength && icon.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '_');

    static bool CanRun(ButtonAction action) => action switch
    {
        MediaAction media => Media.Knows(media.Media),
        KeysAction keys => keys.Combos.Count is > 0 and <= MaxCombos
            && keys.Combos.All(combo => combo is not null && KeyCombo.Parse(combo) is not null),
        OpenAction open => !string.IsNullOrWhiteSpace(open.Target) && open.Target.Length <= MaxTargetLength,
        StatAction stat => (PcStats.Names.Contains(stat.Stat) || SimTelemetry.Names.Contains(stat.Stat))
            && StatAction.Styles.Contains(stat.Style),
        _ => false,
    };
}
