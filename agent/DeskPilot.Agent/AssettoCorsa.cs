using System.Buffers.Binary;
using System.Collections.Frozen;
using System.IO.MemoryMappedFiles;

namespace DeskPilot.Agent;

/// <summary>
/// What a sim racing dashboard shows. Speed in km/h, fuel in litres, times in seconds, temperatures in °C, pressures
/// in psi. Gear is -1 for reverse, 0 for neutral, then 1, 2, 3... A lap time that doesn't exist yet is null.
/// <see cref="Delta"/> is seconds against the best lap (negative is faster). <see cref="PitLimiter"/> and
/// <see cref="InPitLane"/> are 1 or 0, <see cref="Flag"/> is 0 none, 1 blue, 2 yellow, 3 black, 4 white, 5 chequered,
/// 6 penalty. <see cref="Laps"/> is the race length, null in practice. The fuel numbers come from the laps driven.
/// </summary>
public sealed record SimTelemetry(
    double Speed,
    double Rpm,
    double RpmMax,
    int Gear,
    double Fuel,
    double FuelMax,
    int Lap,
    int Position,
    double LapTime,
    double? LastLap,
    double? BestLap,
    double TyreFlTemp,
    double TyreFrTemp,
    double TyreRlTemp,
    double TyreRrTemp,
    double? Delta = null,
    int PitLimiter = 0,
    int InPitLane = 0,
    int Flag = 0,
    int? Laps = null,
    int Sector = 1,
    double? LastSector = null,
    double TyreFlPressure = 0,
    double TyreFrPressure = 0,
    double TyreRlPressure = 0,
    double TyreRrPressure = 0,
    double? FuelPerLap = null,
    double? LapsOfFuel = null,
    double? FuelToFinish = null)
{
    /// <summary>The names stat tiles use, the same as the JSON property names.</summary>
    public static readonly FrozenSet<string> Names = new[]
    {
        "speed", "rpm", "rpmMax", "gear", "fuel", "fuelMax", "lap", "position", "lapTime", "lastLap", "bestLap",
        "tyreFlTemp", "tyreFrTemp", "tyreRlTemp", "tyreRrTemp", "delta", "pitLimiter", "inPitLane", "flag", "laps",
        "sector", "lastSector", "tyreFlPressure", "tyreFrPressure", "tyreRlPressure", "tyreRrPressure", "fuelPerLap",
        "lapsOfFuel", "fuelToFinish",
    }.ToFrozenSet();
}

/// <summary>
/// Reads Assetto Corsa's shared memory: three pages the game publishes for dashboards and apps (physics, graphics
/// and static info). Offsets follow the official layout, packed to 4 bytes with 2 byte characters.
/// </summary>
public static class AssettoCorsa
{
    public const int PhysicsBytes = 316;
    public const int GraphicsBytes = 280;
    public const int StaticBytes = 420;
    const int Driving = 2;
    const int Paused = 3;

    /// <summary>The dashboard while you drive or pause, or null in menus and replays.</summary>
    public static SimTelemetry? Parse(ReadOnlySpan<byte> physics, ReadOnlySpan<byte> graphics, ReadOnlySpan<byte> info)
    {
        if (physics.Length < PhysicsBytes || graphics.Length < GraphicsBytes || info.Length < StaticBytes
            || Int(graphics, 4) is not (Driving or Paused))
        {
            return null;
        }
        return new SimTelemetry(
            Speed: Math.Round(Float(physics, 28)),
            Rpm: Int(physics, 20),
            RpmMax: Int(info, 412),
            Gear: Int(physics, 16) - 1, // AC counts 0 as reverse and 1 as neutral
            Fuel: Math.Round(Float(physics, 12), 1),
            FuelMax: Math.Round(Float(info, 416), 1),
            Lap: Int(graphics, 132) + 1, // the lap you're on, not the laps you've finished
            Position: Int(graphics, 136),
            LapTime: Seconds(Int(graphics, 140)) ?? 0,
            LastLap: Seconds(Int(graphics, 144)),
            BestLap: Seconds(Int(graphics, 148)),
            TyreFlTemp: Math.Round(Float(physics, 152)),
            TyreFrTemp: Math.Round(Float(physics, 156)),
            TyreRlTemp: Math.Round(Float(physics, 160)),
            TyreRrTemp: Math.Round(Float(physics, 164)),
            // Meaningless until there is a best lap to compare with.
            Delta: Seconds(Int(graphics, 148)) is null ? null : Math.Round(Float(physics, 312), 3),
            PitLimiter: Int(physics, 248) == 0 ? 0 : 1,
            InPitLane: Int(graphics, 276) == 0 ? 0 : 1,
            Flag: Int(graphics, 268) is >= 0 and <= 6 and var flag ? flag : 0,
            Laps: Int(graphics, 172) is > 0 and var laps ? laps : null,
            Sector: Int(graphics, 164) + 1, // AC counts sectors from 0
            LastSector: Seconds(Int(graphics, 168)),
            TyreFlPressure: Math.Round(Float(physics, 88), 1),
            TyreFrPressure: Math.Round(Float(physics, 92), 1),
            TyreRlPressure: Math.Round(Float(physics, 96), 1),
            TyreRrPressure: Math.Round(Float(physics, 100), 1));
    }

    static int Int(ReadOnlySpan<byte> page, int at) => BinaryPrimitives.ReadInt32LittleEndian(page[at..]);

    static double Float(ReadOnlySpan<byte> page, int at) => BinaryPrimitives.ReadSingleLittleEndian(page[at..]);

    static double? Seconds(int milliseconds) => milliseconds is > 0 and < 100_000_000 ? milliseconds / 1000.0 : null;
}

/// <summary>
/// Reads Assetto Corsa's shared memory while the game runs. Holding the memory open would keep it alive after AC
/// quits, so when AC's frame counter stops for 2 seconds the reader lets go and shows nothing until it moves again.
/// </summary>
public sealed class AssettoCorsaReader : IDisposable
{
    static readonly TimeSpan StaleAfter = TimeSpan.FromSeconds(2);
    static readonly TimeSpan RetryEvery = TimeSpan.FromSeconds(1);

    readonly TimeProvider time;
    readonly Func<(byte[] Physics, byte[] Graphics, byte[] Static)?> snapshot;
    MemoryMappedFile[] files = [];
    int lastPacket = int.MinValue;
    readonly FuelLog fuel = new();
    DateTimeOffset lastChange;
    DateTimeOffset nextTry;

    public AssettoCorsaReader(TimeProvider time) : this(time, null)
    {
    }

    /// <summary>Tests pass <paramref name="snapshot"/> instead of reading the game's memory.</summary>
    public AssettoCorsaReader(TimeProvider time, Func<(byte[] Physics, byte[] Graphics, byte[] Static)?>? snapshot)
    {
        this.time = time;
        this.snapshot = snapshot ?? ReadMemory;
    }

    public SimTelemetry? Read()
    {
        var now = time.GetUtcNow();
        if (now < nextTry || snapshot() is not var (physics, graphics, info))
        {
            return null;
        }
        var packet = BinaryPrimitives.ReadInt32LittleEndian(physics);
        if (packet != lastPacket)
        {
            lastPacket = packet;
            lastChange = now;
        }
        else if (now - lastChange > StaleAfter)
        {
            Close();
            nextTry = now + RetryEvery;
            return null;
        }
        return AssettoCorsa.Parse(physics, graphics, info) is { } car ? fuel.Add(car) : null;
    }

    public void Dispose() => Close();

    (byte[] Physics, byte[] Graphics, byte[] Static)? ReadMemory()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }
        if (files.Length == 0)
        {
            try
            {
                files =
                [
                    MemoryMappedFile.OpenExisting(@"Local\acpmf_physics", MemoryMappedFileRights.Read),
                    MemoryMappedFile.OpenExisting(@"Local\acpmf_graphics", MemoryMappedFileRights.Read),
                    MemoryMappedFile.OpenExisting(@"Local\acpmf_static", MemoryMappedFileRights.Read),
                ];
            }
            catch (FileNotFoundException)
            {
                // Assetto Corsa isn't running. Look again in a second, not 30 times a second.
                Close();
                nextTry = time.GetUtcNow() + RetryEvery;
                return null;
            }
        }
        return (Page(files[0], AssettoCorsa.PhysicsBytes), Page(files[1], AssettoCorsa.GraphicsBytes),
            Page(files[2], AssettoCorsa.StaticBytes));
    }

    static byte[] Page(MemoryMappedFile file, int length)
    {
        using var view = file.CreateViewAccessor(0, length, MemoryMappedFileAccess.Read);
        var bytes = new byte[length];
        view.ReadArray(0, bytes, 0, length);
        return bytes;
    }

    void Close()
    {
        foreach (var file in files)
        {
            file.Dispose();
        }
        files = [];
        lastPacket = int.MinValue;
    }
}

/// <summary>
/// Works out fuel per lap from the last few whole laps, and from that the laps of fuel left and how much to add to
/// finish the race. A lap you joined halfway, or one with a refuel, doesn't count.
/// </summary>
sealed class FuelLog
{
    const int LapsKept = 5;
    readonly Queue<double> perLap = new();
    int lap = -1;
    double fuelAtLapStart;
    bool sawLapStart;

    public SimTelemetry Add(SimTelemetry car)
    {
        if (car.Lap != lap)
        {
            if (car.Lap == lap + 1 && sawLapStart && fuelAtLapStart - car.Fuel is > 0 and var used
                && used < car.FuelMax)
            {
                perLap.Enqueue(used);
                if (perLap.Count > LapsKept)
                {
                    perLap.Dequeue();
                }
            }
            else if (car.Lap < lap)
            {
                perLap.Clear(); // a new session
            }
            sawLapStart = lap >= 0;
            lap = car.Lap;
            fuelAtLapStart = car.Fuel;
        }
        if (perLap.Count == 0)
        {
            return car;
        }
        var average = perLap.Average();
        // The current lap still needs driving, so it counts as one to go.
        double? toFinish = car.Laps is { } laps
            ? Math.Max(0, Math.Ceiling(((laps - car.Lap + 1) * average - car.Fuel) * 10) / 10)
            : null;
        return car with
        {
            FuelPerLap = Math.Round(average, 2),
            LapsOfFuel = Math.Round(car.Fuel / average, 1),
            FuelToFinish = toFinish,
        };
    }
}
