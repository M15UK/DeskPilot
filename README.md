# DeskPilot

[![App](https://github.com/M15UK/DeskPilot/actions/workflows/app.yml/badge.svg)](https://github.com/M15UK/DeskPilot/actions/workflows/app.yml)
[![PC app](https://github.com/M15UK/DeskPilot/actions/workflows/agent.yml/badge.svg)](https://github.com/M15UK/DeskPilot/actions/workflows/agent.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Status: step 5 of 8 is under way. Your phone shows a deck of buttons you set up yourself, live PC
stats with FPS, and a live Assetto Corsa dashboard. Follow along in the [build plan](docs/PLAN.md).**

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

### Make the deck yours

Tap the pencil at the top. Then:

* Tap **Add button**, give it a label and pick what it does:
  * **Media:** play or pause, next, previous, volume up, volume down or mute.
  * **Keys:** a key combo like `Ctrl+Shift+M`. Type several with commas, like `Ctrl+C, Alt+Tab, Ctrl+V`,
    and they run one after another as a macro.
  * **Open:** an app, file, folder or website, like `C:\Games\game.exe` or `steam://rungameid/244210`.
  * **Stat:** a live reading of CPU or GPU load, RAM, CPU or GPU temperature, or the FPS of the game in
    front, shown as a number, a gauge or a chart of the last minute.
  * **Stat** with a **Sim** reading: while you drive in Assetto Corsa, your speed, RPM, gear, lap
    times, position, fuel and tyre temperatures, updated 30 times a second. The RPM gauge fills to your
    car's rev limit. Put them on a page of their own for a race dash.
* Tap a button to change it, move it, or delete it.
* Use **Add page** and **Page settings** to make pages, like one for music and one per game.

Tap the check mark when you're done. The deck lives on your PC, so every paired phone shows the same
buttons.

### CPU temperature and FPS

Both need a one time setup on your PC.

**FPS** comes with DeskPilot. It counts the frames Windows itself reports, without touching the game, so
anti cheat isn't involved. Windows only allows this for users in the Performance Log Users group, so open
PowerShell as administrator and run this, then sign out of Windows and back in:

```powershell
Add-LocalGroupMember -SID S-1-5-32-559 -Member $env:USERNAME
```

**CPU temperature** needs LibreHardwareMonitor, because reading it takes a driver that Windows doesn't
have:

1. Install it in PowerShell:

   ```powershell
   winget install LibreHardwareMonitor.LibreHardwareMonitor
   ```

2. Open it and let it run as administrator. In its **Options** menu, turn on **Remote Web Server**, then
   **Run**. **Start Minimized** and **Run On Windows Startup** keep it going.
3. In its **Hardware** menu, untick everything except **CPU**. DeskPilot reads the GPU from Windows, so
   this keeps LibreHardwareMonitor's work as small as possible.

Then start DeskPilot again and add **Stat** tiles for CPU temperature and FPS.

If a tile stays empty, the DeskPilot window says why. Two checks help:

* Open <http://127.0.0.1:8085/data.json> in a browser on the PC. It should show a long list of sensors.
* Type `fps` in the DeskPilot window and press Enter, then switch to your game. After 5 seconds it shows
  the app in front and every app that is drawing frames.

Until a tool is ready, its tile shows a dash and the DeskPilot window says what is missing.

To run the tests, use `dotnet test agent/DeskPilot.slnx` (112 tests) and `flutter test` in the app
folder (58 tests).

## Limits

* Media and key buttons and the readings work on Windows only for now. Open buttons also work on a Mac.
* CPU temperature needs LibreHardwareMonitor running. FPS needs your Windows user in the Performance Log
  Users group.
* LibreHardwareMonitor's web server can be seen by other devices on your network, not just this PC.
* Key buttons can't reach a game or app that runs as administrator, unless DeskPilot runs as
  administrator too.
* A paired phone can make buttons that open any app on your PC, so only pair your own phones.
* If your PC's address on the network changes, scan a new QR code.
* **Forget this PC** in the app only removes the PC from your phone. To lock a phone out of your PC,
  type `forget` in the PC window.
* Windows comes first. Mac and Linux get the PC app later, without the game features.
* FPS and the Assetto Corsa dashboard work on Windows only. The dashboard shows dashes in menus and
  replays, and while the game is paused.
* The iPhone app needs a paid Apple developer account to go on the App Store.

## Credits

* [PhoneBox](https://github.com/ersinkoc/phonebox) (MIT license) for ideas on pairing and on
  reading PC stats. DeskPilot has its own code.
* [DeskHub](https://github.com/zacharyinserra/deskhub) (MIT license) for the idea of a desk screen
  that runs things on your PC.
* [PhoneBox Games Tab](https://github.com/lucasaz/phonebox-games-tab) (MIT license) for the idea of
  counting frames from Windows' own events.
* Not connected to Discord, Assetto Corsa, Steam or Epic Games.

## License

[MIT](LICENSE)
