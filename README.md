# DeskPilot

[![App](https://github.com/M15UK/DeskPilot/actions/workflows/app.yml/badge.svg)](https://github.com/M15UK/DeskPilot/actions/workflows/app.yml)
[![PC app](https://github.com/M15UK/DeskPilot/actions/workflows/agent.yml/badge.svg)](https://github.com/M15UK/DeskPilot/actions/workflows/agent.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Status: step 2 of 8 is done. Your phone pairs with your PC by QR code and presses Play/Pause over an
encrypted connection. Follow along in the [build plan](docs/PLAN.md).**

DeskPilot turns your phone into a control deck for your gaming PC. Tap buttons to control music,
Discord and your games, and see live PC stats like temperature and FPS. It is made for gamers and
sim racers, with a live dashboard for Assetto Corsa.

## What it will do

* **Buttons:** a grid of buttons on your phone, in pages you set up yourself.
  * Key combos and macros that also work inside games
  * Open apps, games and websites
  * Music, volume for each app, and Discord mute and deafen
* **PC stats:** CPU and graphics card load and temperature, memory, and the FPS of the game you are
  playing.
* **Sim racing:** a live dashboard with speed, RPM, gear, lap times, fuel and tyre temperatures
  from Assetto Corsa.
* **Game pages:** ready made button pages for each game that open by themselves when the game
  starts.
* **Game launcher:** start your Steam, Epic and other games from your phone.

## How it will work

1. A small app runs on your PC, with an icon in the taskbar.
2. You pair your phone once by scanning a QR code on the PC. After that they talk over your home
   network, or over a USB cable on Android.
3. The PC app sends live stats to your phone, and your phone sends button presses back.

Everything stays on your own network, with no account and no cloud service. The connection is
encrypted, and only phones you paired can control your PC. For games, DeskPilot only presses keys
the normal way and reads data that games share on purpose, so it never touches a game's memory.

## Plan

1. First connection: one working Play and Pause button
2. Safe pairing with a QR code
3. The button deck
4. PC stats and FPS
5. Gaming: Assetto Corsa dashboard, game pages, game launcher and Discord
6. iPhone app
7. PC app for Mac and Linux
8. Installers and releases

The details are in the [build plan](docs/PLAN.md).

## Built with

Flutter (one app for Android and iPhone) · C# and .NET (the PC app) · GitHub Actions

## Run it on your computer

DeskPilot has two parts: the PC app on your Windows PC, and the phone app on your Android phone.
Both need to be on the same home network.

### On your Windows PC

1. Open PowerShell: press the Windows key, type `PowerShell` and press Enter.
2. Install the .NET 11 SDK and Git:

   ```powershell
   winget install Microsoft.DotNet.SDK.11
   winget install Git.Git
   ```

3. Close PowerShell and open it again, so it finds the new tools.
4. Download DeskPilot and start the PC app:

   ```powershell
   git clone https://github.com/M15UK/DeskPilot.git
   cd DeskPilot
   dotnet run --project agent/DeskPilot.Agent
   ```

5. The first start takes about a minute. Then a QR code opens on your screen. It works once, for 5
   minutes.
6. If Windows Firewall asks about DeskPilot, tick **Private networks** and click **Allow**.

Keep that window open while you use DeskPilot. In it, press Enter to show a new QR code for another
phone, or type `forget` and press Enter to unpair every phone. To update later, run `git pull` in the
DeskPilot folder, then the `dotnet run` line again.

### On your Android phone

There is no app download yet, so you install it from a computer that has Flutter 3.47.

1. On the phone, open **Settings**, then **About phone**, and tap **Build number** seven times. This
   turns on Developer options.
2. Find **Developer options** in Settings (often under **System**) and turn on **USB debugging**.
3. Plug the phone into the computer with a USB cable. When the phone asks, allow the computer.
4. In the DeskPilot folder on that computer, install the app:

   ```bash
   cd app
   flutter run
   ```

5. In the app, tap **Scan the QR code** and point the camera at the QR code on your PC. Play some
   music on the PC, then tap **Play / Pause**.

The app remembers your PC and connects by itself the next time you open it.

To run the tests, use `dotnet test agent/DeskPilot.slnx` (27 tests) and `flutter test` in the app
folder (13 tests).

## Limits

* Play/Pause works on Windows only for now. On a Mac or Linux PC, the app tells you so.
* If your PC's address on the network changes, scan a new QR code.
* **Forget this PC** in the app only removes the PC from your phone. To lock a phone out of your PC,
  type `forget` in the PC window.
* Windows comes first. Mac and Linux get the PC app later, without the game features.
* FPS and the Assetto Corsa dashboard will only work on Windows.
* CPU temperature on Windows will need HWiNFO or LibreHardwareMonitor running in the background.
* The iPhone app needs a paid Apple developer account to go on the App Store.

## Credits

* [PhoneBox](https://github.com/ersinkoc/phonebox) (MIT license) for ideas on pairing and on
  reading PC stats. DeskPilot has its own code.
* [DeskHub](https://github.com/zacharyinserra/deskhub) (MIT license) for the idea of a desk screen
  that runs things on your PC.
* Not connected to Discord, Assetto Corsa, Steam or Epic Games.

## License

[MIT](LICENSE)
