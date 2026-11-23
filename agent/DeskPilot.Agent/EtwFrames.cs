using System.Diagnostics;
using System.Runtime.InteropServices;

namespace DeskPilot.Agent;

/// <summary>
/// Listens to Windows' own "frame presented" events in a real time ETW session: the same events PresentMon
/// uses. Nothing is loaded into the game, so anti cheat isn't involved. Starting the session needs the
/// Performance Log Users group or administrator rights. Idea from PhoneBox Games Tab (MIT).
/// </summary>
public static unsafe class EtwFrames
{
    public const uint AccessDenied = 5;

    static readonly Guid DxgiProvider = new("CA11C036-0102-4A2D-A6AD-F03CFED5D3C9");
    static readonly Guid D3D9Provider = new("783ACA0A-790E-4D7F-8451-AA850511C6B9");
    static readonly Guid KernelProvider = new("802EC45A-1E99-4B83-9920-87C98277BA9D");
    const ushort DxgiPresentStart = 42;
    const ushort D3D9PresentStart = 1;
    const ushort KernelPresent = 184;
    const ulong KernelPresentKeyword = 0x8000000;

    const uint TracedGuidFlag = 0x00020000;
    const uint RealTimeMode = 0x00000100;
    const uint ReadEventRecords = 0x10000000;
    const uint RawTimestamps = 0x00001000;
    const uint EnableProvider = 1;
    const byte InformationLevel = 4;
    const uint StopControl = 1;
    const ulong InvalidTrace = ulong.MaxValue;

    // Only one session per DeskPilot, and the Windows callback is static, so it finds the counter here.
    static FrameCounter? counter;
    static ulong trace;
    static nint namePointer;
    static volatile bool listening;

    /// <summary>True while Windows is still sending events. It turns false if the session is stopped from outside.</summary>
    public static bool IsListening => listening;

    /// <summary>Windows checks these sizes; a wrong field layout means every call fails.</summary>
    public static bool LayoutIsRight =>
        !Environment.Is64BitProcess || (sizeof(TraceProperties) == 120 && sizeof(TraceLogFile) == 448);

    /// <summary>Starts listening and feeds frames to <paramref name="frames"/>. Returns 0, or the Windows error code.</summary>
    public static uint Start(string name, FrameCounter frames)
    {
        Stop(name); // a session left behind if DeskPilot crashed
        var size = sizeof(TraceProperties) + 1024;
        var properties = (TraceProperties*)NativeMemory.AllocZeroed((nuint)size);
        ulong session;
        try
        {
            properties->Wnode.BufferSize = (uint)size;
            properties->Wnode.Flags = TracedGuidFlag;
            properties->Wnode.ClientContext = 1; // time stamps from the performance counter, like Stopwatch
            properties->LogFileMode = RealTimeMode;
            properties->BufferSize = 64;
            properties->MinimumBuffers = 8;
            properties->MaximumBuffers = 64;
            properties->FlushTimer = 1;
            properties->LoggerNameOffset = (uint)sizeof(TraceProperties);
            var started = StartTraceW(out session, name, properties);
            if (started != 0)
            {
                return started;
            }
        }
        finally
        {
            NativeMemory.Free(properties);
        }

        Enable(session, DxgiProvider, ulong.MaxValue);
        Enable(session, D3D9Provider, ulong.MaxValue);
        Enable(session, KernelProvider, KernelPresentKeyword);

        counter = frames;
        namePointer = Marshal.StringToHGlobalUni(name);
        var logFile = new TraceLogFile
        {
            LoggerName = namePointer,
            ProcessTraceMode = RealTimeMode | ReadEventRecords | RawTimestamps,
            EventRecordCallback = (nint)(delegate* unmanaged<byte*, void>)&OnEvent,
        };
        trace = OpenTraceW(&logFile);
        if (trace == InvalidTrace)
        {
            var error = (uint)Marshal.GetLastPInvokeError();
            Stop(name);
            return error;
        }
        listening = true;
        var handle = trace;
        new Thread(() =>
        {
            var traceHandle = handle;
            ProcessTrace(&traceHandle, 1, 0, 0);
            listening = false;
        })
        {
            IsBackground = true,
            Name = "DeskPilot frames",
        }.Start();
        return 0;
    }

    public static void Stop(string name)
    {
        if (trace is not 0 and not InvalidTrace)
        {
            CloseTrace(trace);
        }
        trace = 0;
        var size = sizeof(TraceProperties) + 1024;
        var properties = (TraceProperties*)NativeMemory.AllocZeroed((nuint)size);
        properties->Wnode.BufferSize = (uint)size;
        properties->LoggerNameOffset = (uint)sizeof(TraceProperties);
        ControlTraceW(0, name, properties, StopControl);
        NativeMemory.Free(properties);
        if (namePointer != 0)
        {
            Marshal.FreeHGlobal(namePointer);
            namePointer = 0;
        }
        counter = null;
        listening = false;
    }

    static void Enable(ulong session, Guid provider, ulong keywords) =>
        EnableTraceEx2(session, &provider, EnableProvider, InformationLevel, keywords, 0, 0, 0);

    [UnmanagedCallersOnly]
    static void OnEvent(byte* record)
    {
        // EVENT_RECORD starts with EVENT_HEADER: ProcessId at 12, TimeStamp at 16, ProviderId at 24, event Id at 40.
        var id = *(ushort*)(record + 40);
        var provider = *(Guid*)(record + 24);
        FrameSource source;
        if ((id == DxgiPresentStart && provider == DxgiProvider) || (id == D3D9PresentStart && provider == D3D9Provider))
        {
            source = FrameSource.DirectX;
        }
        else if (id == KernelPresent && provider == KernelProvider)
        {
            source = FrameSource.Kernel;
        }
        else
        {
            return;
        }
        var process = *(uint*)(record + 12);
        var ticks = *(long*)(record + 16);
        counter?.Add((int)process, source, ticks / (double)Stopwatch.Frequency);
    }

    // Windows' own layouts, field for field (WNODE_HEADER, EVENT_TRACE_PROPERTIES, EVENT_TRACE_LOGFILEW and friends).
    [StructLayout(LayoutKind.Sequential)]
    struct WnodeHeader
    {
        public uint BufferSize;
        public uint ProviderId;
        public ulong HistoricalContext;
        public long TimeStamp;
        public Guid Guid;
        public uint ClientContext;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct TraceProperties
    {
        public WnodeHeader Wnode;
        public uint BufferSize;
        public uint MinimumBuffers;
        public uint MaximumBuffers;
        public uint MaximumFileSize;
        public uint LogFileMode;
        public uint FlushTimer;
        public uint EnableFlags;
        public int AgeLimit;
        public uint NumberOfBuffers;
        public uint FreeBuffers;
        public uint EventsLost;
        public uint BuffersWritten;
        public uint LogBuffersLost;
        public uint RealTimeBuffersLost;
        public nint LoggerThreadId;
        public uint LogFileNameOffset;
        public uint LoggerNameOffset;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct TraceHeader
    {
        public ushort Size;
        public ushort FieldTypeFlags;
        public uint Version;
        public uint ThreadId;
        public uint ProcessId;
        public long TimeStamp;
        public Guid Guid;
        public ulong ProcessorTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct TraceEvent
    {
        public TraceHeader Header;
        public uint InstanceId;
        public uint ParentInstanceId;
        public Guid ParentGuid;
        public nint MofData;
        public uint MofLength;
        public uint ClientContext;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct SystemTime
    {
        public ushort Year;
        public ushort Month;
        public ushort DayOfWeek;
        public ushort Day;
        public ushort Hour;
        public ushort Minute;
        public ushort Second;
        public ushort Milliseconds;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct TimeZoneInformation
    {
        public int Bias;
        public fixed char StandardName[32];
        public SystemTime StandardDate;
        public int StandardBias;
        public fixed char DaylightName[32];
        public SystemTime DaylightDate;
        public int DaylightBias;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct TraceLogFileHeader
    {
        public uint BufferSize;
        public uint Version;
        public uint ProviderVersion;
        public uint NumberOfProcessors;
        public long EndTime;
        public uint TimerResolution;
        public uint MaximumFileSize;
        public uint LogFileMode;
        public uint BuffersWritten;
        public Guid LogInstanceGuid;
        public nint LoggerName;
        public nint LogFileName;
        public TimeZoneInformation TimeZone;
        public long BootTime;
        public long PerfFreq;
        public long StartTime;
        public uint ReservedFlags;
        public uint BuffersLost;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct TraceLogFile
    {
        public nint LogFileName;
        public nint LoggerName;
        public long CurrentTime;
        public uint BuffersRead;
        public uint ProcessTraceMode;
        public TraceEvent CurrentEvent;
        public TraceLogFileHeader LogfileHeader;
        public nint BufferCallback;
        public uint BufferSize;
        public uint Filled;
        public uint EventsLost;
        public nint EventRecordCallback;
        public uint IsKernelTrace;
        public nint Context;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
    static extern uint StartTraceW(out ulong session, string name, TraceProperties* properties);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
    static extern uint ControlTraceW(ulong session, string name, TraceProperties* properties, uint control);

    [DllImport("advapi32.dll")]
    static extern uint EnableTraceEx2(ulong session, Guid* provider, uint control, byte level, ulong anyKeyword,
        ulong allKeyword, uint timeout, nint parameters);

    [DllImport("advapi32.dll", SetLastError = true)]
    static extern ulong OpenTraceW(TraceLogFile* logFile);

    [DllImport("advapi32.dll")]
    static extern uint ProcessTrace(ulong* traces, uint count, nint start, nint end);

    [DllImport("advapi32.dll")]
    static extern uint CloseTrace(ulong trace);
}
