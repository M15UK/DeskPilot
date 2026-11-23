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

        Assert.Contains("LibreHardwareMonitor", Assert.Single(hints));
    }
}
