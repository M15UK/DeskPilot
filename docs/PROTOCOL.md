# DeskPilot protocol

The phone app and the PC agent talk over an encrypted WebSocket at `wss://<PC address>:8740/ws`.
Every message is one JSON object in a text frame. This is version 5.

## Pairing QR code

The PC shows a QR code with this text:

```json
{"deskpilot":5,"name":"GAMING-PC","hosts":["192.168.1.50"],"port":8740,"fingerprint":"<64 hex characters>","code":"<one time code>"}
```

* `hosts`: the PC's IPv4 addresses, home network first. The phone tries `127.0.0.1` before them, which
  reaches the PC over a USB cable after `adb reverse tcp:8740 tcp:8740`.
* `fingerprint`: SHA-256 of the PC's own certificate, in lowercase hex. The phone trusts no other
  certificate, not even ones from public certificate authorities.
* `code`: 128 random bits. Only the newest code works, once, for 5 minutes.

## Signing in

The phone's first message must arrive within 10 seconds, be at most 4 KB, and be one of these:

| Message | When |
| :-- | :-- |
| `{"type":"pair","code":"..."}` | The first time, with the code from the QR code. |
| `{"type":"auth","key":"..."}` | Every time after that, with the key the phone got when it paired. |

The PC answers:

| Message | When |
| :-- | :-- |
| `{"type":"paired","key":"..."}` | The code was right. The phone keeps this 256 bit key in its secure storage. The PC keeps only its SHA-256 hash. |
| `{"type":"hello","name":"GAMING-PC","version":5}` | The phone is signed in. The deck follows right after. |
| `{"type":"error","message":"..."}`, then close code 1008 | The code or key is wrong. The app shows `message`. |

## After signing in

Messages can be up to 1 MB. A bigger one closes the connection with close code 1009.

| Phone to PC | What the PC does |
| :-- | :-- |
| `{"type":"press","id":"play-pause"}` | Runs the action of the deck button with that id. |
| `{"type":"saveDeck","deck":{...}}` | Checks the deck, saves it in `deck.json` and sends it to every connected phone. |
| `{"type":"mediaKey","media":"next"}` | Presses a media key, for the music card's buttons. `media` is one of the `media` action's keys below. |

| PC to phone | When |
| :-- | :-- |
| `{"type":"deck","deck":{...}}` | Right after `hello`, and whenever any phone saves a deck. |
| `{"type":"stats","stats":{"cpuLoad":23.5,"gpuLoad":41,"gpuTemp":62.5,"ramLoad":48,"cpuTemp":61.3,"fps":144}}` | Every second. Loads are in percent, temperatures in °C, and `fps` is the frames per second of the app in front. A reading the PC can't give is left out: `cpuTemp` needs LibreHardwareMonitor, and `fps` needs the Windows user in the Performance Log Users group. |
| `{"type":"telemetry","telemetry":{"speed":182,"rpm":7350,"rpmMax":8500,"gear":3,"fuel":41.5,"fuelMax":65,"lap":5,"position":2,"lapTime":31.25,"lastLap":103.9,"bestLap":102.345,"tyreFlTemp":85,...}}` | About 30 times a second while you drive or pause in Assetto Corsa, read from the shared memory the game publishes. Speed in km/h, fuel in litres, times in seconds, gear -1 for reverse and 0 for neutral. A lap time that doesn't exist yet is left out. If a phone is still sending the last one, the next is skipped. |
| `{"type":"media","media":{"title":"Neon Highway","artist":"The Midnight Drive","app":"Spotify","playing":true,"position":35,"duration":240,"coverId":"9f2c...","cover":"<base64>"}}` | When what's playing changes, read from Windows' media session (Spotify, browsers, most players). Times in seconds, left out when the app doesn't give a length. `cover` is the album art (JPEG or PNG, up to 512 KB) and comes once per picture: later messages only carry its `coverId`. `{"type":"media"}` alone means nothing is playing. |
| `{"type":"error","message":"..."}` | Something could not be done, for example a deck that breaks a rule below, or `"Key buttons work on Windows for now."`. Anything else gets `"Unknown message"`. |

## Deck

```json
{"pages":[{"name":"Main","buttons":[
  {"id":"play-pause","label":"Play / Pause","action":{"kind":"media","media":"playPause"}},
  {"id":"pit","label":"Pit","action":{"kind":"keys","combos":["Ctrl+P","Enter"]},"icon":"flag","color":"amber"},
  {"id":"ac","label":"Assetto Corsa","action":{"kind":"open","target":"steam://rungameid/244210"}}
]}]}
```

| Action | Rules |
| :-- | :-- |
| `media` | `media` is `playPause`, `next`, `previous`, `volumeUp`, `volumeDown` or `mute`. |
| `keys` | 1 to 20 combos, run 50 ms apart. A combo is up to 6 keys joined by `+`: `Ctrl`, `Shift`, `Alt`, `Win`, `A` to `Z`, `0` to `9`, `F1` to `F24`, `Enter`, `Esc`, `Tab`, `Space`, `Backspace`, `Delete`, `Insert`, `Home`, `End`, `PageUp`, `PageDown`, `Up`, `Down`, `Left`, `Right`, `PrintScreen`. Keys are sent as scan codes, so games see them. |
| `open` | `target` is up to 1000 characters: an app, file, folder or link, opened the way a double click would. |
| `stat` | Shows a reading instead of doing something. `stat` is `cpuLoad`, `gpuLoad`, `gpuTemp`, `ramLoad`, `cpuTemp`, `fps`, or a telemetry name (`speed`, `rpm`, `gear`, `fuel`, `lap`, `position`, `lapTime`, `lastLap`, `bestLap`, `tyreFlTemp`, `tyreFrTemp`, `tyreRlTemp`, `tyreRrTemp`), and `style` is `number`, `gauge` or `chart`. Pressing it does nothing. |

A deck has 1 to 20 pages, a page up to 32 buttons, and every page name and button label is 1 to 40
characters. Button ids are unique across the deck, up to 64 characters. A button may have an `icon` (a name
of up to 40 lowercase letters, digits and `_`, from the app's icon set) and a `color` (`red`, `amber`,
`green`, `teal`, `blue`, `purple`, `pink` or `gray`). Without them the app picks both from what the button
does. It may also have a `size` (`wide`, `tall` or `big`; left out it takes one place), a `style` (`solid`
or `outline`; left out it is tinted) and a `show` (`icon` or `name`; left out it shows both). A page may
have a `size` for its buttons (`small`, `medium`, `large` or `huge`), an `icon` for the page rail, and a
`background` color.
