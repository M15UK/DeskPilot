using System.Net.NetworkInformation;
using System.Net.Sockets;
using DeskPilot.Agent;

var app = AgentServer.Create(AgentServer.DefaultPort, Media.PlayPause);
await app.StartAsync();

Console.WriteLine($"DeskPilot is running on {Environment.MachineName}. In the phone app, type one of these addresses:");
foreach (var address in LanAddresses())
{
    Console.WriteLine($"  {address}");
}
Console.WriteLine("Press Ctrl+C to stop.");
await app.WaitForShutdownAsync();

static IEnumerable<string> LanAddresses() =>
    NetworkInterface.GetAllNetworkInterfaces()
        .Where(nic => nic.OperationalStatus == OperationalStatus.Up
            && nic.NetworkInterfaceType != NetworkInterfaceType.Loopback)
        .SelectMany(nic => nic.GetIPProperties().UnicastAddresses)
        .Where(unicast => unicast.Address.AddressFamily == AddressFamily.InterNetwork)
        .Select(unicast => unicast.Address.ToString());
