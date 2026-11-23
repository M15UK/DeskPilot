using System.Text.Json;

namespace DeskPilot.Agent;

/// <summary>
/// CPU temperature from LibreHardwareMonitor, which has the driver Windows lacks for reading it. It must be
/// running with Options, Remote Web Server, Run turned on. The PC window says each time the situation changes:
/// can't reach it, it shows no CPU temperature, or it works.
/// </summary>
public sealed class HardwareMonitor(Action<string> report, int port = HardwareMonitor.DefaultPort) : IDisposable
{
    public const int DefaultPort = 8085;
    const string Working = "CPU temperature: reading it from LibreHardwareMonitor.";
    const string NoCpuSensor =
        "CPU temperature: LibreHardwareMonitor answers, but shows no CPU temperature. Run it as administrator, let it "
        + "install PawnIO when it asks, and keep CPU ticked in its Hardware menu.";

    // The sensor each CPU maker means by "the CPU temperature". Otherwise the hottest CPU sensor is used.
    static readonly string[] Preferred = ["CPU Package", "Core (Tctl/Tdie)"];

    // A system proxy must not get in the way of a program on this same PC.
    readonly HttpClient client = new(new HttpClientHandler { UseProxy = false }) { Timeout = TimeSpan.FromSeconds(2) };
    string? lastReport;

    public double? CpuTemp()
    {
        double? temperature = null;
        string situation;
        try
        {
            using var response = client.Send(new HttpRequestMessage(HttpMethod.Get, Address));
            response.EnsureSuccessStatusCode();
            using var json = JsonDocument.Parse(response.Content.ReadAsStream());
            temperature = CpuTemp(json.RootElement);
            situation = temperature is null ? NoCpuSensor : Working;
        }
        catch (HttpRequestException e)
        {
            situation = CantReach(e.StatusCode is { } status ? $"it answered {(int)status} {status}" : e.Message);
        }
        catch (OperationCanceledException)
        {
            situation = CantReach("it didn't answer within 2 seconds");
        }
        catch (JsonException)
        {
            situation = CantReach("its answer wasn't sensor data");
        }
        if (situation != lastReport)
        {
            lastReport = situation;
            report(situation);
        }
        return temperature;
    }

    string Address => $"http://127.0.0.1:{port}/data.json";

    string CantReach(string reason) =>
        $"CPU temperature: can't reach LibreHardwareMonitor at {Address} ({reason}). Install it "
        + "(winget install LibreHardwareMonitor.LibreHardwareMonitor), run it, and turn on Options > Remote Web Server > Run.";

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
