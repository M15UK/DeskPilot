using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace DeskPilot.Agent;

/// <summary>
/// The FPS of the app in front, from Intel's PresentMon running in the background. PresentMon comes from
/// "winget install Intel.PresentMon.Console" and needs the user in the Performance Log Users group, or
/// DeskPilot running as administrator. Until then the reading is null and the PC window shows one hint.
/// </summary>
public sealed class PresentMonFps(Action<string> hint) : IDisposable
{
    const string InstallHint =
        "For FPS, install PresentMon: winget install Intel.PresentMon.Console. Then start DeskPilot again.";
    const string AccessHint =
        "For FPS, PresentMon needs your Windows user in the Performance Log Users group, or DeskPilot run as "
        + "administrator. The README shows how.";
    static readonly TimeSpan RetryAfter = TimeSpan.FromMinutes(1);
    static readonly string[] Arguments =
    [
        "--output_stdout", "--no_console_stats", "--session_name", "DeskPilot", "--stop_existing_session",
        // Only frame times are needed, so skip the heavier display, GPU and input tracking.
        "--no_track_display", "--no_track_gpu", "--no_track_input",
    ];

    readonly FrameCounter counter = new();
    readonly Lock gate = new();
    Process? presentMon;
    DateTime nextTry = DateTime.MinValue;
    string? lastHint;

    public double? Read()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }
        EnsureRunning();
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
            try
            {
                presentMon?.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
                // It had already stopped.
            }
            presentMon?.Dispose();
        }
    }

    void EnsureRunning()
    {
        lock (gate)
        {
            if (presentMon is { HasExited: false } || DateTime.UtcNow < nextTry)
            {
                return;
            }
            nextTry = DateTime.UtcNow + RetryAfter;
            presentMon?.Dispose();
            presentMon = null;
            try
            {
                presentMon = Start();
            }
            catch (Win32Exception)
            {
                Hint(InstallHint);
            }
        }
    }

    Process Start()
    {
        var start = new ProcessStartInfo("presentmon")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var argument in Arguments)
        {
            start.ArgumentList.Add(argument);
        }
        var process = new Process { StartInfo = start };
        process.OutputDataReceived += (_, line) => OnLine(line.Data);
        process.ErrorDataReceived += (_, line) => OnLine(line.Data);
        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        return process;
    }

    void OnLine(string? line)
    {
        if (line is null)
        {
            return;
        }
        if (line.Contains("access denied", StringComparison.OrdinalIgnoreCase))
        {
            Hint(AccessHint);
            return;
        }
        counter.Add(line);
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
