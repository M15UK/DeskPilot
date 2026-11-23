using System.Diagnostics;

namespace DeskPilot.Agent;

/// <summary>Runs what a deck button does, on this PC.</summary>
public static class Actions
{
    public static Task RunAsync(ButtonAction action)
    {
        switch (action)
        {
            case MediaAction media:
                Media.Press(media.Media);
                return Task.CompletedTask;
            case KeysAction keys:
                return Keyboard.PressAsync(keys.Combos);
            case OpenAction open:
                // The system picks the program, as a double click would: apps, files, folders and links all work.
                Process.Start(new ProcessStartInfo(open.Target) { UseShellExecute = true })?.Dispose();
                return Task.CompletedTask;
            default:
                throw new ArgumentOutOfRangeException(nameof(action), action, "Unknown button action");
        }
    }
}
