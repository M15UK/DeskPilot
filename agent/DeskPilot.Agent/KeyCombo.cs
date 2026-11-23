using System.Collections.Frozen;

namespace DeskPilot.Agent;

/// <summary>Reads key combos like "Ctrl+Shift+M" into Windows virtual key codes.</summary>
public static class KeyCombo
{
    public const int MaxKeys = 6;

    static readonly FrozenDictionary<string, ushort> Keys = BuildKeys();

    /// <summary>The keys of a combo in order, or null when a key is unknown.</summary>
    public static IReadOnlyList<ushort>? Parse(string combo)
    {
        var names = combo.Split('+', StringSplitOptions.TrimEntries);
        if (names.Length > MaxKeys)
        {
            return null;
        }
        var codes = new List<ushort>(names.Length);
        foreach (var name in names)
        {
            if (!Keys.TryGetValue(name, out var code))
            {
                return null;
            }
            codes.Add(code);
        }
        return codes;
    }

    static FrozenDictionary<string, ushort> BuildKeys()
    {
        var keys = new Dictionary<string, ushort>(StringComparer.OrdinalIgnoreCase)
        {
            ["Ctrl"] = 0x11, ["Control"] = 0x11, ["Shift"] = 0x10, ["Alt"] = 0x12, ["Win"] = 0x5B,
            ["Enter"] = 0x0D, ["Esc"] = 0x1B, ["Escape"] = 0x1B, ["Tab"] = 0x09, ["Space"] = 0x20,
            ["Backspace"] = 0x08, ["Delete"] = 0x2E, ["Insert"] = 0x2D, ["Home"] = 0x24, ["End"] = 0x23,
            ["PageUp"] = 0x21, ["PageDown"] = 0x22, ["Up"] = 0x26, ["Down"] = 0x28, ["Left"] = 0x25,
            ["Right"] = 0x27, ["PrintScreen"] = 0x2C,
        };
        for (var letter = 'A'; letter <= 'Z'; letter++)
        {
            keys[letter.ToString()] = letter;
        }
        for (var digit = '0'; digit <= '9'; digit++)
        {
            keys[digit.ToString()] = digit;
        }
        for (var function = 1; function <= 24; function++)
        {
            keys[$"F{function}"] = (ushort)(0x70 + function - 1);
        }
        return keys.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);
    }
}
