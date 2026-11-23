using System.Net;
using System.Net.Sockets;
using System.Text.Json;

namespace DeskPilot.Agent.Tests;

public class HardwareMonitorTests
{
    // Trimmed from LibreHardwareMonitor's data.json. "Value" is formatted for people, "RawValue" is the number.
    static string Machine(string cpuSensors) => $$"""
        {"id":0,"Text":"Sensor","Children":[{"id":1,"Text":"MY-PC","Children":[
          {"id":2,"Text":"The CPU","HardwareId":"/amdcpu/0","Children":[{"id":3,"Text":"Temperatures","Children":[{{cpuSensors}}]}]},
          {"id":9,"Text":"Radeon RX 7800 XT","HardwareId":"/gpu-amd/0","Children":[
            {"id":10,"Text":"GPU Core","SensorId":"/gpu-amd/0/temperature/0","Type":"Temperature","Value":"70,0 °C","RawValue":70.0,"Children":[]}]}]}]}
        """;

    static string Sensor(string name, string id, double value) =>
        $$"""{"Text":"{{name}}","SensorId":"{{id}}","Type":"Temperature","Value":"x","RawValue":{{value.ToString(System.Globalization.CultureInfo.InvariantCulture)}},"Children":[]}""";

    static double? CpuTemp(string json) => HardwareMonitor.CpuTemp(JsonDocument.Parse(json).RootElement);

    [Fact]
    public void ReadsTheRyzenTemperature() => Assert.Equal(61.3, CpuTemp(Machine(
        Sensor("Core (Tctl/Tdie)", "/amdcpu/0/temperature/2", 61.3) + "," +
        Sensor("CCD1 (Tdie)", "/amdcpu/0/temperature/3", 64))));

    [Fact]
    public void ReadsTheIntelPackageTemperature() => Assert.Equal(55, CpuTemp(Machine(
        Sensor("Core #1", "/intelcpu/0/temperature/0", 70) + "," +
        Sensor("CPU Package", "/intelcpu/0/temperature/8", 55))));

    [Fact]
    public void OtherwiseTakesTheHottestCpuSensor() => Assert.Equal(66, CpuTemp(Machine(
        Sensor("CCD1 (Tdie)", "/amdcpu/0/temperature/3", 64) + "," +
        Sensor("CCD2 (Tdie)", "/amdcpu/0/temperature/4", 66))));

    [Fact]
    public void GpuSensorsAreNotTheCpu() => Assert.Null(CpuTemp(Machine("")));

    // LibreHardwareMonitor 0.9.6 writes readings as text in the PC's number format, not as numbers.
    [Theory]
    [InlineData("61.3 °C")]
    [InlineData("61,3 °C")]
    [InlineData("61\u066B3 °C")]
    public void ReadsVersion096TextReadings(string reading) => Assert.Equal(61.3, CpuTemp(Machine(
        $$"""{"Text":"Core (Tctl/Tdie)","SensorId":"/amdcpu/0/temperature/2","Type":"Temperature","Value":"{{reading}}","RawValue":"{{reading}}","Children":[]}""")));

    [Fact]
    public void ReadingsThatAreNotNumbersAreSkipped() => Assert.Null(CpuTemp(Machine(
        """{"Text":"Core (Tctl/Tdie)","SensorId":"/amdcpu/0/temperature/2","Type":"Temperature","Value":"-","RawValue":"-","Children":[]}""")));

    [Fact]
    public void WithoutLibreHardwareMonitorThereIsNoCpuTempAndOneHint()
    {
        var unused = new TcpListener(IPAddress.Loopback, 0);
        unused.Start();
        var port = ((IPEndPoint)unused.LocalEndpoint).Port;
        unused.Stop();
        var hints = new List<string>();
        using var monitor = new HardwareMonitor(hints.Add, port);

        Assert.Null(monitor.CpuTemp());
        Assert.Null(monitor.CpuTemp());

        Assert.Contains("can't reach LibreHardwareMonitor", Assert.Single(hints));
    }

    [Fact]
    public async Task SaysWhenItAnswersWithoutACpuTemperatureAndWhenItWorks()
    {
        var unused = new TcpListener(IPAddress.Loopback, 0);
        unused.Start();
        var port = ((IPEndPoint)unused.LocalEndpoint).Port;
        unused.Stop();
        using var server = new HttpListener();
        server.Prefixes.Add($"http://127.0.0.1:{port}/");
        server.Start();
        var answers = new[] { Machine(""), Machine(Sensor("Core (Tctl/Tdie)", "/amdcpu/0/temperature/2", 61.3)) };
        var serving = Task.Run(async () =>
        {
            foreach (var answer in answers)
            {
                var request = await server.GetContextAsync();
                await request.Response.OutputStream.WriteAsync(System.Text.Encoding.UTF8.GetBytes(answer));
                request.Response.Close();
            }
        });
        var hints = new List<string>();
        using var monitor = new HardwareMonitor(hints.Add, port);

        Assert.Null(monitor.CpuTemp());
        Assert.Equal(61.3, monitor.CpuTemp());
        await serving;

        Assert.Equal(2, hints.Count);
        Assert.Contains("shows no CPU temperature", hints[0]);
        Assert.Contains("reading it", hints[1]);
    }
}
