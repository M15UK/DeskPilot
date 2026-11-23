using System.Globalization;

namespace DeskPilot.Agent.Tests;

public class FrameCounterTests
{
    const string Header =
        "Application,ProcessID,SwapChainAddress,PresentRuntime,SyncInterval,PresentFlags,AllowsTearing,PresentMode,CPUStartTime,MsBetweenPresents";

    static string Frame(int process, double time) =>
        $"game.exe,{process},0x1,DXGI,0,0,1,Hardware: Independent Flip,{time.ToString(CultureInfo.InvariantCulture)},6.94";

    [Fact]
    public void CountsTheFramesOfEachAppInTheLastSecond()
    {
        var counter = new FrameCounter();
        counter.Add(Header);
        for (var frame = 0; frame < 300; frame++)
        {
            counter.Add(Frame(42, frame / 144.0));
        }
        counter.Add(Frame(7, 2.0));

        Assert.InRange(counter.Fps(42)!.Value, 143, 145);
        Assert.Equal(1, counter.Fps(7));
    }

    [Fact]
    public void AnAppThatStoppedDrawingHasNoFps()
    {
        var counter = new FrameCounter();
        counter.Add(Header);
        counter.Add(Frame(42, 0.5));
        counter.Add(Frame(7, 5.0));

        Assert.Null(counter.Fps(42));
    }

    [Fact]
    public void AnAppPresentMonHasNotSeenHasNoFps() => Assert.Null(new FrameCounter().Fps(42));

    [Fact]
    public void LinesBeforeTheHeaderAndBrokenLinesAreIgnored()
    {
        var counter = new FrameCounter();
        counter.Add(Frame(42, 1.0));
        counter.Add(Header);
        counter.Add("error: something PresentMon said");
        counter.Add("game.exe,not a number,0x1");
        counter.Add(Frame(42, 1.0));

        Assert.Equal(1, counter.Fps(42));
    }

    [Fact]
    public void FindsItsColumnsWhereverPresentMonPutsThem()
    {
        var counter = new FrameCounter();
        counter.Add("CPUStartTime,Application,ProcessID");
        counter.Add("1.5,game.exe,42");

        Assert.Equal(1, counter.Fps(42));
    }
}

public class PresentMonFpsTests
{
    [Fact]
    public void WithoutPresentMonThereIsNoFpsAndOneHint()
    {
        var hints = new List<string>();
        using var fps = new PresentMonFps(hints.Add);

        Assert.Null(fps.Read());
        Assert.Null(fps.Read());

        if (OperatingSystem.IsWindows())
        {
            // The Windows CI machine has no PresentMon installed.
            Assert.Contains("winget install Intel.PresentMon.Console", Assert.Single(hints));
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
