using System.Runtime.InteropServices;

namespace DeskPilot.Agent;

/// <summary>Music controls. Pressing the media key works with any player that Windows lists as playing.</summary>
public static class Media
{
    const byte VkMediaPlayPause = 0xB3;
    const uint KeyEventExtendedKey = 0x0001;
    const uint KeyEventKeyUp = 0x0002;

    public static void PlayPause()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Play/Pause works on Windows for now.");
        }
        keybd_event(VkMediaPlayPause, 0, KeyEventExtendedKey, 0);
        keybd_event(VkMediaPlayPause, 0, KeyEventExtendedKey | KeyEventKeyUp, 0);
    }

    [DllImport("user32.dll")]
    static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, nuint extraInfo);
}
