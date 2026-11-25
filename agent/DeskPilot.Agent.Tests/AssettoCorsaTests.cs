using System.Buffers.Binary;

namespace DeskPilot.Agent.Tests;

public class AssettoCorsaTests
{
    // A car in 3rd gear at 182 km/h on lap 5, in P2, with a 1:42.345 best lap.
    static (byte[] Physics, byte[] Graphics, byte[] Static) Snapshot(int status = 2, int packet = 1, int acGear = 4,
        int completedLaps = 4, float fuel = 41.5f, int totalLaps = 20)
    {
        var physics = new byte[800];
        var graphics = new byte[800];
        var info = new byte[800];
        Int(physics, 0, packet);
        Float(physics, 12, fuel);
        Int(physics, 16, acGear);
        Int(physics, 20, 7350);
        Float(physics, 28, 182.4f);
        float[] tyres = [85.2f, 86.9f, 79.1f, 80.4f];
        for (var tyre = 0; tyre < 4; tyre++)
        {
            Float(physics, 152 + tyre * 4, tyres[tyre]);
        }
        Int(graphics, 4, status);
        Int(graphics, 132, completedLaps);
        Int(graphics, 136, 2);
        Int(graphics, 140, 31_250);
        Int(graphics, 144, 103_900);
        Int(graphics, 148, 102_345);
        float[] pressures = [27.61f, 28.44f, 26.1f, 27.3f];
        for (var tyre = 0; tyre < 4; tyre++)
        {
            Float(physics, 88 + tyre * 4, pressures[tyre]);
        }
        Int(physics, 248, 1); // pit limiter on
        Float(physics, 312, -0.2141f); // a fifth of a second faster than the best lap
        Int(graphics, 164, 1); // in the second sector
        Int(graphics, 168, 31_500);
        Int(graphics, 172, totalLaps);
        Int(graphics, 268, 2); // yellow flag
        Int(graphics, 276, 0); // not in the pit lane
        Int(info, 412, 8500);
        Float(info, 416, 65f);
        return (physics, graphics, info);
    }

    static void Int(byte[] page, int at, int value) => BinaryPrimitives.WriteInt32LittleEndian(page.AsSpan(at), value);

    static void Float(byte[] page, int at, float value) => BinaryPrimitives.WriteSingleLittleEndian(page.AsSpan(at), value);

    [Fact]
    public void ReadsTheDashboardFromAssettoCorsasMemory()
    {
        var (physics, graphics, info) = Snapshot();

        var car = AssettoCorsa.Parse(physics, graphics, info)!;

        Assert.Equal(182, car.Speed);
        Assert.Equal(7350, car.Rpm);
        Assert.Equal(8500, car.RpmMax);
        Assert.Equal(3, car.Gear);
        Assert.Equal(41.5, car.Fuel);
        Assert.Equal(65, car.FuelMax);
        Assert.Equal(5, car.Lap);
        Assert.Equal(2, car.Position);
        Assert.Equal(31.25, car.LapTime);
        Assert.Equal(103.9, car.LastLap);
        Assert.Equal(102.345, car.BestLap);
        Assert.Equal(85, car.TyreFlTemp);
        Assert.Equal(80, car.TyreRrTemp);
    }

    [Fact]
    public void ReadsWhatARacingPageShows()
    {
        var (physics, graphics, info) = Snapshot();

        var car = AssettoCorsa.Parse(physics, graphics, info)!;

        Assert.Equal(-0.214, car.Delta);
        Assert.Equal(1, car.PitLimiter);
        Assert.Equal(0, car.InPitLane);
        Assert.Equal(2, car.Flag);
        Assert.Equal(20, car.Laps);
        Assert.Equal(2, car.Sector);
        Assert.Equal(31.5, car.LastSector);
        Assert.Equal(27.6, car.TyreFlPressure);
        Assert.Equal(27.3, car.TyreRrPressure);
    }

    [Fact]
    public void WithoutABestLapOrALapCountThoseAreLeftOut()
    {
        var (physics, graphics, info) = Snapshot(totalLaps: 0);
        Int(graphics, 148, 0);

        var car = AssettoCorsa.Parse(physics, graphics, info)!;

        Assert.Null(car.Delta);
        Assert.Null(car.Laps);
    }

    [Fact]
    public void WorksOutFuelPerLapLapsLeftAndFuelToFinish()
    {
        var time = new FakeTime();
        var (completed, fuel, packet) = (4, 43.0f, 1);
        using var reader = new AssettoCorsaReader(time, () => Snapshot(packet: packet, completedLaps: completed, fuel: fuel));

        Assert.Null(reader.Read()!.FuelPerLap); // joined mid lap: that lap doesn't count
        (completed, fuel, packet) = (5, 41.5f, 2);
        Assert.Null(reader.Read()!.FuelPerLap);
        (completed, fuel, packet) = (6, 38.5f, 3); // a whole lap used 3.0 L
        reader.Read();
        (completed, fuel, packet) = (7, 35.4f, 4); // and the next 3.1 L
        var car = reader.Read()!;

        Assert.Equal(3.05, car.FuelPerLap);
        Assert.Equal(11.6, car.LapsOfFuel);
        Assert.Equal(4.3, car.FuelToFinish); // lap 8 of 20: 13 laps need 39.65 L, 4.25 more, rounded up
    }

    [Theory]
    [InlineData(0, -1)] // reverse
    [InlineData(1, 0)] // neutral
    [InlineData(2, 1)] // first gear
    public void GearsReadLikeOnTheDash(int acGear, int gear)
    {
        var (physics, graphics, info) = Snapshot(acGear: acGear);

        Assert.Equal(gear, AssettoCorsa.Parse(physics, graphics, info)!.Gear);
    }

    [Theory]
    [InlineData(0)] // off
    [InlineData(1)] // replay
    public void NothingIsSentUnlessYouAreDriving(int status)
    {
        var (physics, graphics, info) = Snapshot(status: status);

        Assert.Null(AssettoCorsa.Parse(physics, graphics, info));
    }

    [Fact]
    public void AMissingLapTimeIsLeftOut()
    {
        var (physics, graphics, info) = Snapshot();
        Int(graphics, 148, 0);

        var json = AgentServer.TelemetryMessage(AssettoCorsa.Parse(physics, graphics, info)!);

        Assert.DoesNotContain("bestLap", json);
        Assert.StartsWith("""{"type":"telemetry","telemetry":{"speed":182,""", json);
    }

    [Fact]
    public void FrozenDataCountsAsAssettoCorsaGone()
    {
        var time = new FakeTime();
        var packet = 1;
        using var reader = new AssettoCorsaReader(time, () => Snapshot(packet: packet));

        Assert.NotNull(reader.Read());
        time.Now += TimeSpan.FromSeconds(1);
        Assert.NotNull(reader.Read());
        time.Now += TimeSpan.FromSeconds(2);
        Assert.Null(reader.Read()); // the frame counter stopped: AC closed or froze

        packet = 2;
        time.Now += TimeSpan.FromSeconds(2);
        Assert.NotNull(reader.Read()); // driving again
    }

    [Fact]
    public void WithoutAssettoCorsaThereIsNoTelemetry()
    {
        using var reader = new AssettoCorsaReader(new FakeTime(), () => null);

        Assert.Null(reader.Read());
    }

    [Fact]
    public void SimTilesAreValidDeckReadings()
    {
        var deck = new Deck([new DeckPage("Racing", [new DeckButton("gear", "Gear", new StatAction("gear", "number"))])]);

        Assert.Null(deck.Problem());
        Assert.Contains("rpm", (IReadOnlySet<string>)SimTelemetry.Names);
    }
}
