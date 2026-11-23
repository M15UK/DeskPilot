using System.ComponentModel;
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using DeskPilot.Agent;

var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeskPilot");
using var certificate = AgentCertificate.LoadOrCreate(folder);
var security = new AgentSecurity(
    certificate,
    new PairingCodes(TimeProvider.System),
    new PairedPhones(Path.Combine(folder, "phones.json")));

var decks = new DeckStore(Path.Combine(folder, "deck.json"));

using var statsReader = new StatsReader();
using var hardwareMonitor = new HardwareMonitor(Console.WriteLine);
using var fps = new WindowsFps(Console.WriteLine);
var stats = new Feed<PcStats>(TimeSpan.FromSeconds(1), () =>
    statsReader.Read() with { CpuTemp = hardwareMonitor.CpuTemp(), Fps = fps.Read() });
using var assettoCorsa = new AssettoCorsaReader(TimeProvider.System);
var telemetry = new Feed<SimTelemetry>(TimeSpan.FromMilliseconds(33), assettoCorsa.Read);
var media = new Feed<NowPlaying>(TimeSpan.FromSeconds(1), new NowPlayingReader(TimeProvider.System).Read);

var app = AgentServer.Create(AgentServer.DefaultPort,
    new AgentServices(security, decks, stats, telemetry, media, Actions.RunAsync));
await app.StartAsync();
_ = stats.RunAsync(app.Logger, app.Lifetime.ApplicationStopping);
_ = telemetry.RunAsync(app.Logger, app.Lifetime.ApplicationStopping);
_ = media.RunAsync(app.Logger, app.Lifetime.ApplicationStopping);

Console.WriteLine($"DeskPilot is running on {Environment.MachineName}. Paired phones: {security.Phones.Count}.");
Console.WriteLine("Press Enter to pair a phone. Type forget and press Enter to unpair every phone. Press Ctrl+C to stop.");
Console.WriteLine("Type fps and press Enter, then switch to your game, to see what FPS measures.");
if (security.Phones.Count == 0)
{
    ShowPairingQr();
}
_ = Task.Run(ReadCommands);
await app.WaitForShutdownAsync();

void ReadCommands()
{
    while (Console.ReadLine() is { } line)
    {
        try
        {
            if (line.Trim().Equals("fps", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine("Switch to your game now. Checking in 5 seconds...");
                Thread.Sleep(TimeSpan.FromSeconds(5));
                Console.WriteLine(fps.Describe());
            }
            else if (line.Trim().Equals("forget", StringComparison.OrdinalIgnoreCase))
            {
                // shortcut: a phone that is connected right now stays connected until it reconnects.
                security.Phones.ForgetAll();
                Console.WriteLine("Every phone is unpaired. Press Enter to pair one again.");
            }
            else
            {
                ShowPairingQr();
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Console.WriteLine($"That did not work: {e.Message}");
        }
    }
}

void ShowPairingQr()
{
    var text = PairingQr.Text(Environment.MachineName, LanAddresses(), AgentServer.DefaultPort,
        AgentCertificate.Fingerprint(certificate), security.Codes.New());
    var image = Path.Combine(folder, "pairing-qr.png");
    PrivateFile.Write(image, PairingQr.Png(text));
    Console.WriteLine("Scan the QR code with the DeskPilot app. It works once, for 5 minutes.");
    try
    {
        Process.Start(new ProcessStartInfo(image) { UseShellExecute = true });
    }
    catch (Win32Exception)
    {
        Console.WriteLine($"Open this picture to see the QR code: {image}");
    }
}

// Network cards with a gateway come first: that is usually the home network, not a VPN or WSL.
static string[] LanAddresses() =>
    NetworkInterface.GetAllNetworkInterfaces()
        .Where(nic => nic.OperationalStatus == OperationalStatus.Up
            && nic.NetworkInterfaceType != NetworkInterfaceType.Loopback)
        .OrderByDescending(nic => nic.GetIPProperties().GatewayAddresses.Count > 0)
        .SelectMany(nic => nic.GetIPProperties().UnicastAddresses)
        .Where(unicast => unicast.Address.AddressFamily == AddressFamily.InterNetwork)
        .Select(unicast => unicast.Address.ToString())
        .ToArray();
