namespace DeskPilot.Agent.Tests;

public class FrameCounterTests
{
    static void Draw(FrameCounter counter, int process, FrameSource source, int frames, double fps)
    {
        for (var frame = 0; frame < frames; frame++)
        {
            counter.Add(process, source, frame / fps);
        }
    }

    [Fact]
    public void CountsTheFramesOfAnAppInTheLastSecond()
    {
        var counter = new FrameCounter();

        Draw(counter, 42, FrameSource.DirectX, 300, 144);

        Assert.InRange(counter.Fps(42)!.Value, 143, 145);
    }

    [Fact]
    public void AFrameSeenByDirectXAndTheKernelCountsOnce()
    {
        var counter = new FrameCounter();

        Draw(counter, 42, FrameSource.DirectX, 300, 144);
        Draw(counter, 42, FrameSource.Kernel, 300, 144);

        Assert.InRange(counter.Fps(42)!.Value, 143, 145);
    }

    [Fact]
    public void VulkanAndOpenGlGamesCountThroughTheKernel()
    {
        var counter = new FrameCounter();

        Draw(counter, 7, FrameSource.Kernel, 120, 60);

        Assert.InRange(counter.Fps(7)!.Value, 59, 61);
    }

    [Fact]
    public void AnAppThatStoppedDrawingHasNoFps()
    {
        var counter = new FrameCounter();
        counter.Add(42, FrameSource.DirectX, 0.5);
        counter.Add(7, FrameSource.DirectX, 5.0);

        Assert.Null(counter.Fps(42));
    }

    [Fact]
    public void AnAppThatNeverDrewHasNoFps() => Assert.Null(new FrameCounter().Fps(42));
}

public class WindowsFpsTests
{
    [Fact]
    public void TheWindowsEventLayoutsHaveTheSizesWindowsExpects() => Assert.True(EtwFrames.LayoutIsRight);

    [Fact]
    public void ListeningForFramesStartsOrSaysWhy()
    {
        var hints = new List<string>();
        using var fps = new WindowsFps(hints.Add);

        var reading = fps.Read();

        Assert.True(reading is null or >= 0);
        if (OperatingSystem.IsWindows())
        {
            // Starting works as administrator or in Performance Log Users. Anything else means a broken call.
            Assert.True(hints.Count == 0 || hints[0].Contains("Performance Log Users"), string.Join(" ", hints));
        }
        else
        {
            Assert.Empty(hints);
        }
    }

    [Fact]
    public void FpsIsSentWithTheOtherReadings() =>
        Assert.Equal("""{"type":"stats","stats":{"cpuLoad":20,"fps":144}}""",
            AgentServer.StatsMessage(new PcStats(CpuLoad: 20, GpuLoad: null, GpuTemp: null, RamLoad: null, Fps: 144)));
}
