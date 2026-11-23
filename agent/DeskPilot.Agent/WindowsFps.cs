using System.Runtime.InteropServices;

namespace DeskPilot.Agent;

/// <summary>
/// The FPS of the app in front, from Windows' own frame events. It needs the Windows user in the
/// Performance Log Users group, or DeskPilot run as administrator. Until then the reading is null and
/// the PC window shows one hint.
/// </summary>
public sealed class WindowsFps(Action<string> hint) : IDisposable
{
    // The group's built in id works on Windows in any language, where its name is translated.
    const string AccessHint =
        "For FPS, add your Windows user to the Performance Log Users group: open PowerShell as administrator, "
        + "run Add-LocalGroupMember -SID S-1-5-32-559 -Member $env:USERNAME, then sign out and back in.";
    static readonly TimeSpan RetryAfter = TimeSpan.FromMinutes(1);

    readonly FrameCounter counter = new();
    readonly Lock gate = new();
    readonly string sessionName = $"DeskPilot-{Environment.UserName}";
    bool started;
    DateTime nextTry = DateTime.MinValue;
    string? lastHint;

    public double? Read()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }
        EnsureListening();
        var window = GetForegroundWindow();
        if (window == 0 || GetWindowThreadProcessId(window, out var process) == 0)
        {
            return null;
        }
        return counter.Fps((int)process);
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (started)
            {
                EtwFrames.Stop(sessionName);
                started = false;
            }
        }
    }

    void EnsureListening()
    {
        lock (gate)
        {
            if ((started && EtwFrames.IsListening) || DateTime.UtcNow < nextTry)
            {
                return;
            }
            nextTry = DateTime.UtcNow + RetryAfter;
            var error = EtwFrames.Start(sessionName, counter);
            started = error == 0;
            if (!started)
            {
                Hint(error == EtwFrames.AccessDenied ? AccessHint : $"FPS could not start: Windows error {error}.");
            }
        }
    }

    void Hint(string message)
    {
        if (Interlocked.Exchange(ref lastHint, message) != message)
        {
            hint(message);
        }
    }

    [DllImport("user32.dll")]
    static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(nint window, out uint processId);
}
