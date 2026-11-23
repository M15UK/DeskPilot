using System.Buffers.Binary;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace DeskPilot.Agent;

/// <summary>
/// Reads CPU, GPU and RAM load and GPU temperature from Windows itself, for any GPU brand: the performance
/// counters Task Manager uses, and the graphics kernel (D3DKMT) for the temperature Task Manager shows.
/// Other systems get <see cref="PcStats.Unknown"/> for now.
/// </summary>
public sealed partial class StatsReader : IDisposable
{
    const uint PdhMoreData = 0x800007D2;
    const uint PdhFormat = 0x200 | 0x8000; // a double, not capped at 100
    const int QueryAdapterType = 15;
    const int QueryDeviceIds = 31;
    const int QueryPerformanceData = 62;
    const uint MicrosoftVendorId = 0x1414;
    // D3DKMT_ADAPTER_PERFDATA keeps the temperature, in tenths of a degree, after an index, five 64 bit
    // memory and bus fields, and the fan and power values.
    const int TemperatureOffset = 56;

    readonly nint query;
    readonly nint cpuCounter;
    readonly nint gpuCounter;
    readonly uint[] adapters = [];

    public StatsReader()
    {
        if (!OperatingSystem.IsWindows() || PdhOpenQuery(null, 0, out query) != 0)
        {
            return;
        }
        cpuCounter = Counter(@"\Processor Information(_Total)\% Processor Utility")
            ?? Counter(@"\Processor(_Total)\% Processor Time")
            ?? 0;
        gpuCounter = Counter(@"\GPU Engine(*)\Utilization Percentage") ?? 0;
        PdhCollectQueryData(query); // Loads are rates, so this first sample is only a starting point.
        adapters = HardwareAdapters();
    }

    public PcStats Read()
    {
        if (query == 0)
        {
            return PcStats.Unknown;
        }
        var sampled = PdhCollectQueryData(query) == 0;
        return new PcStats(
            CpuLoad: sampled ? CpuLoad() : null,
            GpuLoad: sampled ? GpuLoad() : null,
            GpuTemp: GpuTemp(),
            RamLoad: RamLoad());
    }

    public void Dispose()
    {
        if (query != 0)
        {
            PdhCloseQuery(query);
        }
        foreach (var adapter in adapters)
        {
            var handle = adapter;
            D3DKMTCloseAdapter(ref handle);
        }
    }

    nint? Counter(string path) => PdhAddEnglishCounter(query, path, 0, out var counter) == 0 ? counter : null;

    double? CpuLoad()
    {
        if (cpuCounter == 0 || PdhGetFormattedCounterValue(cpuCounter, PdhFormat, 0, out var value) != 0
            || value.Status > 1)
        {
            return null;
        }
        return Percent(value.Value);
    }

    /// <summary>The busiest engine of the busiest GPU, like Task Manager shows it.</summary>
    double? GpuLoad()
    {
        if (gpuCounter == 0)
        {
            return null;
        }
        var engines = new Dictionary<string, double>();
        foreach (var (name, value) in CounterArray(gpuCounter))
        {
            // Instances look like pid_1234_luid_0x0_0x1C621_phys_0_eng_3_engtype_3D: one per program and engine.
            var engine = EngineName().Match(name);
            if (engine.Success)
            {
                engines[engine.Value] = engines.GetValueOrDefault(engine.Value) + value;
            }
        }
        return engines.Count == 0 ? null : Percent(engines.Values.Max());
    }

    /// <summary>The hottest GPU, in °C.</summary>
    double? GpuTemp()
    {
        double? hottest = null;
        foreach (var adapter in adapters)
        {
            var data = new byte[64];
            if (QueryAdapter(adapter, QueryPerformanceData, data) != 0)
            {
                continue;
            }
            var tenths = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(TemperatureOffset));
            if (tenths is > 0 and < 2000)
            {
                hottest = Math.Max(hottest ?? 0, Math.Round(tenths / 10.0, 1));
            }
        }
        return hottest;
    }

    static double? RamLoad()
    {
        var status = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        return GlobalMemoryStatusEx(ref status) ? status.MemoryLoad : null;
    }

    static double Percent(double value) => Math.Round(Math.Clamp(value, 0, 100), 1);

    static List<(string Name, double Value)> CounterArray(nint counter)
    {
        uint size = 0;
        uint count = 0;
        if (PdhGetFormattedCounterArray(counter, PdhFormat, ref size, ref count, 0) != PdhMoreData || size == 0)
        {
            return [];
        }
        var buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            if (PdhGetFormattedCounterArray(counter, PdhFormat, ref size, ref count, buffer) != 0)
            {
                return [];
            }
            var items = new List<(string, double)>((int)count);
            var itemSize = Marshal.SizeOf<CounterItem>();
            for (var i = 0; i < count; i++)
            {
                var item = Marshal.PtrToStructure<CounterItem>(buffer + i * itemSize);
                if (item.Status <= 1)
                {
                    items.Add((Marshal.PtrToStringUni(item.Name) ?? "", item.Value));
                }
            }
            return items;
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    /// <summary>Real graphics cards: not software renderers or Microsoft's basic display adapter.</summary>
    static uint[] HardwareAdapters()
    {
        var infos = new AdapterInfo[16];
        var pinned = GCHandle.Alloc(infos, GCHandleType.Pinned);
        uint count;
        try
        {
            var request = new EnumAdapters { Count = (uint)infos.Length, Adapters = pinned.AddrOfPinnedObject() };
            if (D3DKMTEnumAdapters2(ref request) != 0)
            {
                return [];
            }
            count = Math.Min(request.Count, (uint)infos.Length);
        }
        finally
        {
            pinned.Free();
        }

        var kept = new List<uint>();
        foreach (var info in infos.AsSpan(0, (int)count))
        {
            if (IsRealGpu(info.Handle))
            {
                kept.Add(info.Handle);
            }
            else
            {
                var handle = info.Handle;
                D3DKMTCloseAdapter(ref handle);
            }
        }
        return [.. kept];
    }

    static bool IsRealGpu(uint adapter)
    {
        var type = new byte[4];
        var ids = new byte[28];
        if (QueryAdapter(adapter, QueryAdapterType, type) != 0 || QueryAdapter(adapter, QueryDeviceIds, ids) != 0)
        {
            return false;
        }
        var flags = BinaryPrimitives.ReadUInt32LittleEndian(type);
        var renders = (flags & 0b1) != 0;
        var software = (flags & 0b100) != 0;
        var vendor = BinaryPrimitives.ReadUInt32LittleEndian(ids.AsSpan(4));
        return renders && !software && vendor != MicrosoftVendorId;
    }

    static uint QueryAdapter(uint adapter, int type, byte[] data)
    {
        var pinned = GCHandle.Alloc(data, GCHandleType.Pinned);
        try
        {
            var request = new QueryAdapterInfo
            {
                Adapter = adapter,
                Type = type,
                Data = pinned.AddrOfPinnedObject(),
                DataSize = (uint)data.Length,
            };
            return D3DKMTQueryAdapterInfo(ref request);
        }
        finally
        {
            pinned.Free();
        }
    }

    [GeneratedRegex(@"luid_0x[0-9a-f]+_0x[0-9a-f]+_phys_\d+_eng_\d+", RegexOptions.IgnoreCase)]
    private static partial Regex EngineName();

    [StructLayout(LayoutKind.Sequential)]
    struct CounterValue
    {
        public uint Status;
        public double Value;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct CounterItem
    {
        public nint Name;
        public uint Status;
        public double Value;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MemoryStatus
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhysical;
        public ulong AvailablePhysical;
        public ulong TotalPageFile;
        public ulong AvailablePageFile;
        public ulong TotalVirtual;
        public ulong AvailableVirtual;
        public ulong AvailableExtendedVirtual;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct AdapterInfo
    {
        public uint Handle;
        public uint LuidLow;
        public int LuidHigh;
        public uint Sources;
        public int PrecisePresentRegionsPreferred;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct EnumAdapters
    {
        public uint Count;
        public nint Adapters;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct QueryAdapterInfo
    {
        public uint Adapter;
        public int Type;
        public nint Data;
        public uint DataSize;
    }

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    static extern uint PdhOpenQuery(string? source, nint user, out nint query);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    static extern uint PdhAddEnglishCounter(nint query, string path, nint user, out nint counter);

    [DllImport("pdh.dll")]
    static extern uint PdhCollectQueryData(nint query);

    [DllImport("pdh.dll")]
    static extern uint PdhGetFormattedCounterValue(nint counter, uint format, nint type, out CounterValue value);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    static extern uint PdhGetFormattedCounterArray(nint counter, uint format, ref uint size, ref uint count, nint items);

    [DllImport("pdh.dll")]
    static extern uint PdhCloseQuery(nint query);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);

    [DllImport("gdi32.dll")]
    static extern uint D3DKMTEnumAdapters2(ref EnumAdapters request);

    [DllImport("gdi32.dll")]
    static extern uint D3DKMTQueryAdapterInfo(ref QueryAdapterInfo request);

    [DllImport("gdi32.dll")]
    static extern uint D3DKMTCloseAdapter(ref uint adapter);
}
