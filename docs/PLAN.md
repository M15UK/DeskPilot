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
| FPS | Windows' own frame events (ETW), built in | not planned | Needs admin or the "Performance Log Users" group |
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
4. **PC stats (done, CPU temperature through LibreHardwareMonitor):** CPU, GPU and RAM usage, temperatures, FPS; widgets for a number tile, a gauge and a small chart.
5. **Gaming (Assetto Corsa dashboard done):** Assetto Corsa dashboard, game button boxes that switch automatically, game launcher, Discord controls.
6. **iPhone:** iOS build; test on your own iPhone with a free Apple ID (installs last 7 days) or TestFlight
   ($99 a year Apple developer account). iPhone over USB through `usbmuxd`.
7. **Mac and Linux agent:** keys, media, volume and stats. Game features stay Windows only.
8. **Release:** Windows installer, Mac `.dmg`, Linux package, APK on GitHub Releases, store listings later.
   FPS is already built in (Windows' own frame events). The Windows installer bundles the LibreHardwareMonitor
   library (MPL-2.0), so users download nothing else. CPU temperature and FPS stay off until the user turns
   them on: one admin prompt then adds the user to Performance Log Users and installs a small helper
   service with the PawnIO driver, while the main agent keeps running without admin. Before shipping: confirm PawnIO's redistribution terms (or download it from the official source
   at that moment), check anti-cheat games accept PawnIO, and code sign the installer and helper.

## UI round (before the rest of Phase 5)

Asked for after Phase 5's dashboard worked: a real UI for everything. The look mixes the best of PhoneBox
(colored stat cards with small charts), DeskHub (ring gauges, page rail, big icon buttons), Stream Deck
(pages, folders) and Touch Portal (sliders, wide tiles), on a dark screen. Each step ends tested on the PC
and tablet.

1. **Look and editor:** dark theme; a page rail on the left of a tablet (a bottom bar on a phone); every
   button gets an icon and a color; a stat tile names itself from the reading (editable); drag to reorder;
   a live preview in the editor; haptic feedback on presses.
2. **Now playing:** a music card with the song's cover art, title, artist, the app playing it, progress and
   controls. The agent reads it from Windows' media session, so it works with Spotify, browsers and most
   players.
3. **Racing page** (instead of a full screen dash): live info on top (gear and speed with a small shift
   light bar, delta, last and best lap, fuel with laps left and how much to add at the pit, four tyres
   colored by temperature with pressures, position, lap, flag) and big buttons below (pit limiter that
   lights up while on, ignition, starter, lights, flash, wipers, plus and minus for TC, ABS and brake bias,
   camera, look back, hide apps, push to talk, mute, pause). Keys come from the player's own
   `Documents\Assetto Corsa\cfg\controls.ini` (only cameras F1 to F6 and Ctrl+A / Ctrl+T are known
   defaults; pit limiter and lights have none). New AC data: delta (physics 312), pit limiter (physics
   248), tyre pressures (physics 88), flag (graphics 268), pit lane (graphics 276), sectors (graphics 164,
   168). ACC shares the same layout.
4. **Settings and PC window:** a settings screen on the phone (PC info, connection, pair another PC,
   forget, FPS and CPU temperature checks), and a Windows tray app instead of the PowerShell window (QR
   code, paired phones, status, start with Windows).

## Customizing (picked after the new look)

- **Saved in the deck on the PC, so every phone gets them:** button size per page (small, medium, large,
  huge); button shape (normal, wide, tall, big); button style (tinted, solid, outline); labels (icon and
  name, icon only, name only); folders of buttons; your own picture on a button; page icon; page background
  (a color or a wallpaper). Pictures are resized on the phone and kept on the PC.
- **Saved on each phone:** themes (Midnight, Carbon, Neon, Racing red); full screen with the screen kept
  on; haptics and a click sound; spacing and corners; which home cards show (music, clock and PC); big
  CPU, GPU, RAM and FPS cards; backup and share a deck or a page as a file.

## Built in features (instead of Stream Deck plugins)

The most popular Stream Deck plugins are closed source, and Marketplace plugins have used Elgato's DRM
since January 2026, so DeskPilot can't run them. It builds the same jobs in, in its own look, with no extra
downloads.

| # | Feature (like the plugin) | How DeskPilot does it |
|---|---|---|
| 1 | Assetto Corsa (Race Deck, AC Connect) | The Racing page above |
| 2 | Discord (Elgato Discord) | Mute, deafen, push to talk, join voice through Discord's local RPC with your own Discord app; Discord keybinds as the fallback |
| 3 | Music with cover art (Spotify) | Windows' media session; liking songs and playlists through a Spotify sign in later |
| 4 | Volume per app (Win Tools, Volume Controller) | Core Audio sessions: sliders and mute for the game, Discord, Spotify |
| 5 | Switch audio device (Audio Switcher) | Headset or speakers in one tap |
| 6 | Macros (Super Macro, Multi Action) | Record keys on the PC, play them back with delays |
| 7 | App and game launcher (Advanced Launcher) | Pick from installed apps and Steam games, show if running |
| 8 | PC tools (Win Tools) | Lock, sleep, screenshot, AMD instant replay, close a stuck game |
| 9 | PC stats | Done: CPU, GPU, RAM, temperatures, FPS |
| 10 | OBS Studio (Elgato OBS, OBS Tools) | obs-websocket, built into OBS 28 and later |
| 11 | Soundboard | Play sound clips on the PC |
| 12 | Clock, timer, stopwatch | On the phone, no PC needed |
| 13 | iRacing and other sims (iRaceDeck) | The Racing page fed by each sim's own data |
| 14 | Smart lights (Hue, Elgato Key Light, Home Assistant) | Each one's local API |
| 15 | Twitch (Elgato Twitch) | Markers, chat, ads after a Twitch sign in |

Order: 1 to 10 come with the UI round and Phase 5, 11 to 15 after.

## Plugins

Asked for: community plugins like other platforms, the 10 most popular ready to use, and an Assetto Corsa
plugin.

- **One plugin format.** DeskPilot's own features become plugins that add actions and tiles to the editor
  (for example "Assetto Corsa: pit limiter", "Discord: mute"). Each plugin has a name, an icon, its actions
  and their settings.
- **Ten pre-installed**, ready to drop on a page from the editor: Assetto Corsa (telemetry tiles, the
  Racing page, race keys), Discord, Music, OBS Studio, Volume per app, Audio device, Macros, Launcher,
  PC tools, PC stats. These are our own code: the most popular Stream Deck plugins are closed source, and
  Marketplace plugins have used Elgato's DRM since January 2026, so they can't be shipped or run.
- **Community plugins.** The PC agent hosts plugins written for the Stream Deck SDK and its open
  OpenAction version (the WebSocket protocol, our own MIT code, not OpenDeck's GPL code). People add a free
  plugin's `.sdPlugin` folder or `.streamDeckPlugin` file; its keys and pictures show on the phone, and its
  settings page opens in the editor. Plugins run as the user on the PC, so DeskPilot asks before installing
  one and lists what it can do.
- **A plugin gallery** in the app: installed plugins, the ten built in, and a list of known free plugins.

## Testing

- Agent: xUnit tests for parsing, pairing and the message format.
- App: Flutter widget tests.
- A demo mode in the agent that replays recorded Assetto Corsa and PC data, so the phone UI can be built on the Mac
  without running the game.

## Risks

- **Anti cheat:** we only send normal OS key presses and read data that games publish on purpose (Assetto Corsa's
  shared memory, Windows' own frame events). We never read or write another game's memory.
- **CPU temperature on Windows** depends on HWiNFO or LibreHardwareMonitor running; without them the tile says
  "not available".
- **Unsigned Windows builds** trigger SmartScreen warnings until we get code signing (PhoneBox uses SignPath's free
  open source program).
- **iPhone distribution** needs the paid Apple developer account for TestFlight and the App Store.

## Setup checklist

- Mac: Flutter 3.47, Xcode 16.2, Android SDK, GitHub CLI and .NET 11 SDK are installed.
- Windows PC: .NET 11 SDK, Assetto Corsa, Discord desktop app, LibreHardwareMonitor for CPU temperature.
- Android phone: Developer options and USB debugging turned on, for USB and installing test builds.
