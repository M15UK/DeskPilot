# DeskPilot protocol

The phone app and the PC agent talk over an encrypted WebSocket at `wss://<PC address>:8740/ws`.
Every message is one JSON object in a text frame. This is version 4.

## Pairing QR code

The PC shows a QR code with this text:

```json
{"deskpilot":4,"name":"GAMING-PC","hosts":["192.168.1.50"],"port":8740,"fingerprint":"<64 hex characters>","code":"<one time code>"}
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
| `{"type":"hello","name":"GAMING-PC","version":4}` | The phone is signed in. The deck follows right after. |
| `{"type":"error","message":"..."}`, then close code 1008 | The code or key is wrong. The app shows `message`. |

## After signing in

Messages can be up to 1 MB. A bigger one closes the connection with close code 1009.

| Phone to PC | What the PC does |
| :-- | :-- |
| `{"type":"press","id":"play-pause"}` | Runs the action of the deck button with that id. |
| `{"type":"saveDeck","deck":{...}}` | Checks the deck, saves it in `deck.json` and sends it to every connected phone. |

| PC to phone | When |
| :-- | :-- |
| `{"type":"deck","deck":{...}}` | Right after `hello`, and whenever any phone saves a deck. |
| `{"type":"stats","stats":{"cpuLoad":23.5,"gpuLoad":41,"gpuTemp":62.5,"ramLoad":48,"cpuTemp":61.3,"fps":144}}` | Every second. Loads are in percent, temperatures in °C, and `fps` is the frames per second of the app in front. A reading the PC can't give is left out: `cpuTemp` needs LibreHardwareMonitor and `fps` needs PresentMon. |
| `{"type":"error","message":"..."}` | Something could not be done, for example a deck that breaks a rule below, or `"Key buttons work on Windows for now."`. Anything else gets `"Unknown message"`. |

## Deck

```json
{"pages":[{"name":"Main","buttons":[
  {"id":"play-pause","label":"Play / Pause","action":{"kind":"media","media":"playPause"}},
  {"id":"pit","label":"Pit","action":{"kind":"keys","combos":["Ctrl+P","Enter"]}},
  {"id":"ac","label":"Assetto Corsa","action":{"kind":"open","target":"steam://rungameid/244210"}}
]}]}
```

| Action | Rules |
| :-- | :-- |
| `media` | `media` is `playPause`, `next`, `previous`, `volumeUp`, `volumeDown` or `mute`. |
| `keys` | 1 to 20 combos, run 50 ms apart. A combo is up to 6 keys joined by `+`: `Ctrl`, `Shift`, `Alt`, `Win`, `A` to `Z`, `0` to `9`, `F1` to `F24`, `Enter`, `Esc`, `Tab`, `Space`, `Backspace`, `Delete`, `Insert`, `Home`, `End`, `PageUp`, `PageDown`, `Up`, `Down`, `Left`, `Right`, `PrintScreen`. Keys are sent as scan codes, so games see them. |
| `open` | `target` is up to 1000 characters: an app, file, folder or link, opened the way a double click would. |
| `stat` | Shows a reading instead of doing something. `stat` is `cpuLoad`, `gpuLoad`, `gpuTemp`, `ramLoad`, `cpuTemp` or `fps`, and `style` is `number`, `gauge` or `chart`. Pressing it does nothing. |

A deck has 1 to 20 pages, a page up to 32 buttons, and every page name and button label is 1 to 40
characters. Button ids are unique across the deck, up to 64 characters.
