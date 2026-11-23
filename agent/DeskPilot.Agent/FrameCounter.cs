namespace DeskPilot.Agent;

/// <summary>
/// Where Windows reported a frame. DirectX games show up in DirectX and in the graphics kernel;
/// Vulkan and OpenGL games only in the kernel.
/// </summary>
public enum FrameSource
{
    DirectX,
    Kernel,
}

/// <summary>
/// Turns frame events into frames per second for each app. It goes by the events' own times,
/// so events that arrive in bursts still count right.
/// </summary>
public sealed class FrameCounter
{
    const double WindowSeconds = 1.0;

    readonly Lock gate = new();
    readonly Dictionary<(int Process, FrameSource Source), Queue<double>> frames = [];
    double latest;

    public void Add(int process, FrameSource source, double seconds)
    {
        lock (gate)
        {
            latest = Math.Max(latest, seconds);
            if (!frames.TryGetValue((process, source), out var times))
            {
                frames[(process, source)] = times = new Queue<double>();
            }
            times.Enqueue(seconds);
            DropOld(times);
        }
    }

    /// <summary>Frames the app drew in the last second, or null when it drew none.</summary>
    public double? Fps(int process)
    {
        lock (gate)
        {
            foreach (var (key, times) in frames.ToArray())
            {
                DropOld(times);
                if (times.Count == 0)
                {
                    frames.Remove(key);
                }
            }
            // The kernel also sees DirectX frames, so it only counts for apps DirectX doesn't report.
            if (frames.TryGetValue((process, FrameSource.DirectX), out var directX))
            {
                return directX.Count;
            }
            return frames.TryGetValue((process, FrameSource.Kernel), out var kernel) ? kernel.Count : null;
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
