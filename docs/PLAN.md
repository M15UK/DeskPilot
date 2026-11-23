# DeskPilot plan

DeskPilot turns your phone into a control deck for your gaming PC: shortcut buttons, music controls, live PC
stats with FPS, Discord controls, and a sim racing dashboard for Assetto Corsa.

## Decisions

| Topic | Choice |
|---|---|
| Phone app | Flutter, one codebase for Android and iPhone. Android first (that's the test phone), iPhone after |
| PC agent | C# on .NET 11 (supported until November 2028), a tray app. Windows first, then the core features on Mac and Linux |
| Connection | Wi-Fi with QR pairing. USB on Android through `adb reverse`. USB on iPhone later |
| GitHub | Public repo, MIT license |
| Reference | [PhoneBox](https://github.com/ersinkoc/phonebox) (MIT): we borrow ideas, write our own code, and credit it in the README |
| Dev machines | Mac for coding and iPhone builds; Windows PC for game, FPS and sensor testing |

## How it works

```
Phone app (Flutter)                                  PC agent (C# .NET, tray icon)
  button grid, pages, dashboards   <── WebSocket ──>   sensors, media, key presses,
  edit mode (long press)             over TLS, JSON    game data, game launcher
```

- The agent pushes state: PC stats once a second, sim telemetry about 30 times a second while a sim runs.
- The phone sends actions, for example `{"type":"key","keys":"Ctrl+Shift+M"}`.
- Layouts are saved as JSON on the PC, so every paired phone gets the same decks.
- Pairing (PhoneBox's idea): the agent shows a QR code with the PC's name, address, port, TLS certificate fingerprint
  and a one-time code. The phone pins the certificate and trades the code for a long-lived key. The key is never in
  the QR code, and a code works once for a few minutes.

## Repo layout

```
deskpilot/
  agent/       C# agent and its tests
  app/         Flutter phone app
  docs/        this plan, and PROTOCOL.md with the messages both sides use
```

## Features and how each one works

| Feature | Windows | Mac / Linux | Notes |
|---|---|---|---|
| Key combos and macros | `SendInput` with scan codes | CGEvent / xdotool | Games ignore normal key events, so scan codes are a must. Wayland limits fake input |
| Music and now playing | Windows media session API | macOS needs a workaround / MPRIS | Apple locked the Now Playing API in macOS 15.4 |
| Volume, per app | Core Audio (NAudio) | CoreAudio / PipeWire | |
| CPU, GPU, RAM usage | performance counters, D3DKMT, `nvidia-smi` | sysctl / `/proc`, sysfs | PhoneBox uses the same sources |
| Temperatures | GPU: `nvidia-smi` (AMD later). CPU: read from HWiNFO or LibreHardwareMonitor if running | SMC / hwmon | Reading CPU temps directly needs a kernel driver; we avoid shipping one |
| FPS, frame time, 1% lows | Intel PresentMon (MIT) | not planned | Needs admin or the "Performance Log Users" group |
| Discord mute, deafen, join | Discord's local RPC with your own Discord app ID | same | Fallback: Discord keybinds as normal key buttons |
| Assetto Corsa dashboard | shared memory `acpmf_physics`, `acpmf_graphics`, `acpmf_static` | not planned | ACC uses the same layout, so it comes almost free |
| Game button boxes | per game button pages, switched by watching which game is running | same | Ships with an Assetto Corsa preset: pit, lights, wipers, cameras |
| Game launcher | Steam (`libraryfolders.vdf`), Epic (launcher manifests), any `.exe` you add | Steam, apps | |

## Phases

Each phase ends with something working on your phone.

0. **Setup:** GitHub repo, MIT license, README, `.gitignore`, GitHub Actions that build the agent and the app.
1. **First connection (done):** agent with a WebSocket server; the app connects by typing the PC's IP; one Play/Pause button
   works. This proves the whole path end to end.
2. **Pairing and security (done):** QR pairing, TLS with the pinned certificate, the key kept in the phone's secure storage,
   USB through `adb reverse`.
3. **The deck (done):** button grid, pages, edit mode on the phone, actions (keys, macros, open app or website, media,
   volume).
4. **PC stats (loads and GPU temperature done; CPU temperature and FPS next):** CPU, GPU and RAM usage, temperatures, FPS; widgets for a number tile, a gauge and a small chart.
5. **Gaming:** Assetto Corsa dashboard, game button boxes that switch automatically, game launcher, Discord controls.
6. **iPhone:** iOS build; test on your own iPhone with a free Apple ID (installs last 7 days) or TestFlight
   ($99 a year Apple developer account). iPhone over USB through `usbmuxd`.
7. **Mac and Linux agent:** keys, media, volume and stats. Game features stay Windows only.
8. **Release:** Windows installer, Mac `.dmg`, Linux package, APK on GitHub Releases, store listings later.

## Testing

- Agent: xUnit tests for parsing, pairing and the message format.
- App: Flutter widget tests.
- A demo mode in the agent that replays recorded Assetto Corsa and PC data, so the phone UI can be built on the Mac
  without running the game.

## Risks

- **Anti cheat:** we only send normal OS key presses and read data that games publish on purpose (Assetto Corsa's
  shared memory, PresentMon). We never read or write another game's memory.
- **CPU temperature on Windows** depends on HWiNFO or LibreHardwareMonitor running; without them the tile says
  "not available".
- **Unsigned Windows builds** trigger SmartScreen warnings until we get code signing (PhoneBox uses SignPath's free
  open source program).
- **iPhone distribution** needs the paid Apple developer account for TestFlight and the App Store.

## Setup checklist

- Mac: Flutter 3.47, Xcode 16.2, Android SDK, GitHub CLI and .NET 11 SDK are installed.
- Windows PC: .NET 11 SDK, Assetto Corsa, Discord desktop app, PresentMon (bundled later).
- Android phone: Developer options and USB debugging turned on, for USB and installing test builds.
