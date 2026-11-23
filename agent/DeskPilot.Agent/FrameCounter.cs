using System.Globalization;

namespace DeskPilot.Agent;

/// <summary>
/// Turns PresentMon's CSV output, one line per frame, into frames per second for each app.
/// It uses PresentMon's own frame times, so lines that arrive in bursts still count right.
/// </summary>
public sealed class FrameCounter
{
    const double WindowSeconds = 1.0;

    readonly Lock gate = new();
    readonly Dictionary<int, Queue<double>> frames = [];
    int processColumn = -1;
    int timeColumn = -1;
    double latest;

    public void Add(string line)
    {
        var fields = line.Split(',');
        lock (gate)
        {
            if (fields.Contains("ProcessID") && fields.Contains("CPUStartTime"))
            {
                processColumn = Array.IndexOf(fields, "ProcessID");
                timeColumn = Array.IndexOf(fields, "CPUStartTime");
                frames.Clear();
                latest = 0;
                return;
            }
            if (processColumn < 0
                || fields.Length <= Math.Max(processColumn, timeColumn)
                || !int.TryParse(fields[processColumn], CultureInfo.InvariantCulture, out var process)
                || !double.TryParse(fields[timeColumn], CultureInfo.InvariantCulture, out var time))
            {
                return;
            }
            latest = Math.Max(latest, time);
            if (!frames.TryGetValue(process, out var times))
            {
                frames[process] = times = new Queue<double>();
            }
            times.Enqueue(time);
            DropOld(times);
        }
    }

    /// <summary>Frames the app drew in the last second, or null when it drew none.</summary>
    public double? Fps(int process)
    {
        lock (gate)
        {
            foreach (var (id, times) in frames.ToArray())
            {
                DropOld(times);
                if (times.Count == 0)
                {
                    frames.Remove(id);
                }
            }
            return frames.TryGetValue(process, out var recent) ? recent.Count : null;
        }
    }

    void DropOld(Queue<double> times)
    {
        while (times.Count > 0 && times.Peek() <= latest - WindowSeconds)
        {
            times.Dequeue();
        }
    }
}
