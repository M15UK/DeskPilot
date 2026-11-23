using System.Collections.Frozen;
using System.Runtime.InteropServices;

namespace DeskPilot.Agent;

/// <summary>Media keys. They work with any player that Windows lists as playing.</summary>
public static class Media
{
    const uint KeyEventExtendedKey = 0x0001;
    const uint KeyEventKeyUp = 0x0002;

    static readonly FrozenDictionary<string, byte> Keys = new Dictionary<string, byte>
    {
        ["playPause"] = 0xB3,
        ["next"] = 0xB0,
        ["previous"] = 0xB1,
        ["volumeUp"] = 0xAF,
        ["volumeDown"] = 0xAE,
        ["mute"] = 0xAD,
    }.ToFrozenDictionary();

    public static bool Knows(string media) => Keys.ContainsKey(media);

    public static void Press(string media)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Media buttons work on Windows for now.");
        }
        var key = Keys[media];
        keybd_event(key, 0, KeyEventExtendedKey, 0);
        keybd_event(key, 0, KeyEventExtendedKey | KeyEventKeyUp, 0);
    }

    [DllImport("user32.dll")]
    static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, nuint extraInfo);
}
