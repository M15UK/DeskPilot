using System.Diagnostics;
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
        return ForegroundProcess() is { } process ? counter.Fps(process) : null;
    }

    /// <summary>What FPS sees right now: the app in front and every app drawing. For the fps command.</summary>
    public string Describe()
    {
        if (!OperatingSystem.IsWindows())
        {
            return "FPS works on Windows only.";
        }
        EnsureListening();
        if (!started || !EtwFrames.IsListening)
        {
            return $"FPS: not listening for frames. {lastHint}";
        }
        var front = ForegroundProcess();
        var inFront = front is { } process
            ? $"{Name(process)}, {counter.Fps(process)?.ToString("0") ?? "no frames"}"
            : "nothing";
        var drawing = counter.AllFps()
            .OrderByDescending(app => app.Value)
            .Take(6)
            .Select(app => $"{Name(app.Key)} {app.Value:0}")
            .ToArray();
        return $"FPS: app in front: {inFront}. Apps drawing: {(drawing.Length == 0 ? "none" : string.Join(", ", drawing))}.";
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
            var error = EtwFrames.Start(sessionName, counter, Hint);
            started = error == 0;
            Hint(started
                ? "FPS: listening for frames. Type fps here to see what it measures."
                : error == EtwFrames.AccessDenied ? AccessHint : $"FPS could not start: Windows error {error}.");
        }
    }

    static int? ForegroundProcess()
    {
        var window = GetForegroundWindow();
        return window != 0 && GetWindowThreadProcessId(window, out var process) != 0 ? (int)process : null;
    }

    static string Name(int process)
    {
        try
        {
            using var running = Process.GetProcessById(process);
            return $"{running.ProcessName} ({process})";
        }
        catch (ArgumentException)
        {
            return $"process {process}";
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
