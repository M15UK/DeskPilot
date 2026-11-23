using System.Collections.Frozen;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace DeskPilot.Agent;

/// <summary>
/// Presses key combos on Windows. Keys go out as hardware scan codes, which games read,
/// not only the virtual key codes most apps use.
/// </summary>
public static class Keyboard
{
    const uint InputKeyboard = 1;
    const uint KeyEventExtendedKey = 0x0001;
    const uint KeyEventKeyUp = 0x0002;
    const uint KeyEventScanCode = 0x0008;
    const uint MapVirtualKeyToScanCode = 0;
    static readonly TimeSpan GapBetweenCombos = TimeSpan.FromMilliseconds(50);

    // These keys share scan codes with the number pad, so Windows tells them apart by the extended flag.
    static readonly FrozenSet<ushort> ExtendedKeys =
        new ushort[] { 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2C, 0x2D, 0x2E, 0x5B }.ToFrozenSet();

    public static int InputSize => Marshal.SizeOf<Input>();

    /// <summary>Keys go down in order, then up in reverse, like a person pressing Ctrl+C.</summary>
    public static IReadOnlyList<(ushort Key, bool Up)> Strokes(IReadOnlyList<ushort> keys) =>
        [.. keys.Select(key => (key, false)), .. keys.Reverse().Select(key => (key, true))];

    public static async Task PressAsync(IReadOnlyList<string> combos)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Key buttons work on Windows for now.");
        }
        for (var i = 0; i < combos.Count; i++)
        {
            if (i > 0)
            {
                await Task.Delay(GapBetweenCombos);
            }
            var keys = KeyCombo.Parse(combos[i]) ?? throw new ArgumentException($"Unknown key in {combos[i]}.");
            var inputs = Strokes(keys).Select(stroke => ToInput(stroke.Key, stroke.Up)).ToArray();
            if (SendInput((uint)inputs.Length, inputs, InputSize) != inputs.Length)
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError());
            }
        }
    }

    static Input ToInput(ushort key, bool up) => new()
    {
        Type = InputKeyboard,
        Data = new InputData
        {
            Keyboard = new KeyboardInput
            {
                ScanCode = (ushort)MapVirtualKey(key, MapVirtualKeyToScanCode),
                Flags = KeyEventScanCode
                    | (up ? KeyEventKeyUp : 0)
                    | (ExtendedKeys.Contains(key) ? KeyEventExtendedKey : 0),
            },
        },
    };

    [StructLayout(LayoutKind.Sequential)]
    struct Input
    {
        public uint Type;
        public InputData Data;
    }

    // Windows checks the size of the whole union, so the unused mouse part must be here too.
    [StructLayout(LayoutKind.Explicit)]
    struct InputData
    {
        [FieldOffset(0)] public MouseInput Mouse;
        [FieldOffset(0)] public KeyboardInput Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MouseInput
    {
        public int X;
        public int Y;
        public uint Data;
        public uint Flags;
        public uint Time;
        public nint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct KeyboardInput
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public nint ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint count, Input[] inputs, int size);

    [DllImport("user32.dll")]
    static extern uint MapVirtualKey(uint code, uint mapType);
}
