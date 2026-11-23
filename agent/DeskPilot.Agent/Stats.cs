using System.Collections.Frozen;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DeskPilot.Agent;

/// <summary>PC readings sent to phones each second: percent, °C, or frames per second. Null means this PC can't tell.</summary>
public sealed record PcStats(
    double? CpuLoad,
    double? GpuLoad,
    double? GpuTemp,
    double? RamLoad,
    double? CpuTemp = null,
    double? Fps = null)
{
    public static PcStats Unknown { get; } = new(null, null, null, null);

    /// <summary>The names stat tiles use, the same as the JSON property names.</summary>
    public static readonly FrozenSet<string> Names =
        new[] { "cpuLoad", "gpuLoad", "gpuTemp", "ramLoad", "cpuTemp", "fps" }.ToFrozenSet();

    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };
}

/// <summary>
/// Reads something every <paramref name="interval"/> while a phone is listening, and hands it to every connected
/// phone: PC stats once a second, sim telemetry about 30 times a second. A null reading is not sent.
/// </summary>
public sealed class Feed<T>(TimeSpan interval, Func<T?> read) where T : class
{
    public event Action<T>? Updated;

    /// <summary>Reads and hands out one reading, but only when a phone is listening.</summary>
    public void Tick()
    {
        if (Updated is { } listeners && read() is { } reading)
        {
            listeners(reading);
        }
    }

    public async Task RunAsync(ILogger logger, CancellationToken stop)
    {
        using var timer = new PeriodicTimer(interval);
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
