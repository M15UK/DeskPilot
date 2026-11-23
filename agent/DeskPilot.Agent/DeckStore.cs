using System.Text.Json;

namespace DeskPilot.Agent;

/// <summary>Keeps the deck in deck.json and tells connected phones when it changes.</summary>
public sealed class DeckStore
{
    readonly string file;
    readonly Lock gate = new();
    Deck deck;

    public DeckStore(string file)
    {
        this.file = file;
        deck = File.Exists(file) ? Load(file) : Deck.Default;
    }

    public event Action<Deck>? Changed;

    public Deck Current
    {
        get
        {
            lock (gate)
            {
                return deck;
            }
        }
    }

    /// <summary>Keeps a deck that already passed <see cref="Deck.Read"/>.</summary>
    public void Save(Deck fresh)
    {
        lock (gate)
        {
            PrivateFile.Write(file, JsonSerializer.SerializeToUtf8Bytes(fresh, Deck.Json));
            deck = fresh;
        }
        Changed?.Invoke(fresh);
    }

    static Deck Load(string file)
    {
        using var json = JsonDocument.Parse(File.ReadAllBytes(file));
        return Deck.Read(json.RootElement, out var problem)
            ?? throw new InvalidDataException($"{file} is damaged ({problem}). Delete it to start with the default deck.");
    }
}
