using System.Text.Json;

namespace DeskPilot.Agent;

/// <summary>
/// CPU temperature from LibreHardwareMonitor, which has the driver Windows lacks for reading it. It must be
/// running with Options, Remote Web Server, Run turned on. Until then the reading is null and the PC window
/// shows one hint.
/// </summary>
public sealed class HardwareMonitor(Action<string> hint, int port = HardwareMonitor.DefaultPort) : IDisposable
{
    public const int DefaultPort = 8085;
    const string Hint =
        "For CPU temperature, install LibreHardwareMonitor (winget install LibreHardwareMonitor.LibreHardwareMonitor), "
        + "run it, and turn on Options > Remote Web Server > Run.";

    // The sensor each CPU maker means by "the CPU temperature". Otherwise the hottest CPU sensor is used.
    static readonly string[] Preferred = ["CPU Package", "Core (Tctl/Tdie)"];

    readonly HttpClient client = new() { Timeout = TimeSpan.FromMilliseconds(500) };
    bool hinted;

    public double? CpuTemp()
    {
        try
        {
            using var response = client.Send(new HttpRequestMessage(HttpMethod.Get, $"http://127.0.0.1:{port}/data.json"));
            response.EnsureSuccessStatusCode();
            using var json = JsonDocument.Parse(response.Content.ReadAsStream());
            return CpuTemp(json.RootElement);
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException or JsonException)
        {
            if (!hinted)
            {
                hinted = true;
                hint(Hint);
            }
            return null;
        }
    }

    public void Dispose() => client.Dispose();

    /// <summary>Picks the CPU temperature, in °C, from LibreHardwareMonitor's sensor tree.</summary>
    public static double? CpuTemp(JsonElement root)
    {
        var temperatures = new List<(string Name, double Value)>();
        Collect(root, temperatures);
        if (temperatures.Count == 0)
        {
            return null;
        }
        foreach (var name in Preferred)
        {
            foreach (var (sensor, value) in temperatures)
            {
                if (sensor == name)
                {
                    return Math.Round(value, 1);
                }
            }
        }
        return Math.Round(temperatures.Max(temperature => temperature.Value), 1);
    }

    static void Collect(JsonElement node, List<(string Name, double Value)> temperatures)
    {
        if (node.ValueKind != JsonValueKind.Object)
        {
            return;
        }
        if (Text(node, "Type") == "Temperature"
            && Text(node, "SensorId") is { } id
            && (id.StartsWith("/amdcpu/", StringComparison.Ordinal) || id.StartsWith("/intelcpu/", StringComparison.Ordinal))
            && Text(node, "Text") is { } name
            && node.TryGetProperty("RawValue", out var raw)
            && raw.ValueKind == JsonValueKind.Number
            && raw.GetDouble() is > 0 and < 150)
        {
            temperatures.Add((name, raw.GetDouble()));
        }
        if (node.TryGetProperty("Children", out var children) && children.ValueKind == JsonValueKind.Array)
        {
            foreach (var child in children.EnumerateArray())
            {
                Collect(child, temperatures);
            }
        }
    }

    static string? Text(JsonElement node, string name) =>
        node.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
