using System.Collections.Frozen;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DeskPilot.Agent;

/// <summary>PC readings sent to phones each second, in percent or °C. Null means this PC can't tell.</summary>
public sealed record PcStats(double? CpuLoad, double? GpuLoad, double? GpuTemp, double? RamLoad)
{
    public static PcStats Unknown { get; } = new(null, null, null, null);

    /// <summary>The names stat tiles use, the same as the JSON property names.</summary>
    public static readonly FrozenSet<string> Names =
        new[] { "cpuLoad", "gpuLoad", "gpuTemp", "ramLoad" }.ToFrozenSet();

    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };
}

/// <summary>Reads the PC's stats once a second while a phone is listening, and hands them to every connected phone.</summary>
public sealed class StatsFeed(Func<PcStats> read)
{
    static readonly TimeSpan Interval = TimeSpan.FromSeconds(1);

    public event Action<PcStats>? Updated;

    /// <summary>Reads and hands out one set of stats, but only when a phone is listening.</summary>
    public void Tick()
    {
        var listeners = Updated;
        listeners?.Invoke(read());
    }

    public async Task RunAsync(ILogger logger, CancellationToken stop)
    {
        using var timer = new PeriodicTimer(Interval);
        while (await timer.WaitForNextTickAsync(stop))
        {
            try
            {
                Tick();
            }
            catch (Exception e)
            {
                logger.LogError(e, "Reading the PC stats failed");
            }
        }
    }
}
