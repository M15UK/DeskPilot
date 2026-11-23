# DeskPilot

[![App](https://github.com/M15UK/DeskPilot/actions/workflows/app.yml/badge.svg)](https://github.com/M15UK/DeskPilot/actions/workflows/app.yml)
[![PC app](https://github.com/M15UK/DeskPilot/actions/workflows/agent.yml/badge.svg)](https://github.com/M15UK/DeskPilot/actions/workflows/agent.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Status: step 1 of 8 is done. Your phone connects to your PC and can press Play/Pause. Follow along in
the [build plan](docs/PLAN.md).**

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

You need the .NET 11 SDK for the PC app, and Flutter 3.47 with an Android phone for the phone app.

```bash
dotnet run --project agent/DeskPilot.Agent   # starts the PC app and shows its addresses
cd app && flutter run                         # installs the phone app on your connected phone
```

Type one of the addresses the PC app shows into the phone app, then tap Connect. Your phone and PC
need to be on the same network. The first time, Windows Firewall asks about DeskPilot. Allow it on
private networks.

To run the tests, use `dotnet test agent/DeskPilot.slnx` (10 tests) and `flutter test` in the app
folder (5 tests).

## Limits

* Play/Pause works on Windows only for now. On a Mac or Linux PC, the app tells you so.
* There is no pairing yet, so anyone on your network could press Play/Pause. Step 2 fixes this.
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
