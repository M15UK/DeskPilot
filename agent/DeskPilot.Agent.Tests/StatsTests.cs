namespace DeskPilot.Agent.Tests;

public class StatsTests
{
    [Fact]
    public void StatsLeaveOutReadingsThePcCannotGive()
    {
        var json = AgentServer.StatsMessage(new PcStats(CpuLoad: 12.5, GpuLoad: null, GpuTemp: 41, RamLoad: 60));

        Assert.Equal("""{"type":"stats","stats":{"cpuLoad":12.5,"gpuTemp":41,"ramLoad":60}}""", json);
    }

    [Fact]
    public void TheFeedReadsOnlyWhileAPhoneListens()
    {
        var reads = 0;
        var feed = new StatsFeed(() =>
        {
            reads++;
            return PcStats.Unknown;
        });

        feed.Tick();
        Assert.Equal(0, reads);

        PcStats? received = null;
        feed.Updated += stats => received = stats;
        feed.Tick();

        Assert.Equal(1, reads);
        Assert.Same(PcStats.Unknown, received);
    }

    [Fact]
    public void WindowsGivesCpuAndRamLoad()
    {
        if (!OperatingSystem.IsWindows())
        {
            return; // The Windows CI run checks this.
        }
        using var reader = new StatsReader();
        Thread.Sleep(500); // CPU load is a rate, so Windows needs two samples some time apart.

        var stats = reader.Read();

        Assert.InRange(stats.CpuLoad!.Value, 0, 100);
        Assert.InRange(stats.RamLoad!.Value, 1, 100);
        if (stats.GpuLoad is { } gpuLoad)
        {
            Assert.InRange(gpuLoad, 0, 100);
        }
        if (stats.GpuTemp is { } gpuTemp)
        {
            Assert.InRange(gpuTemp, 1, 200);
        }
    }
}
