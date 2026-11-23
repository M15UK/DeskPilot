# DeskPilot protocol

The phone app and the PC agent talk over an encrypted WebSocket at `wss://<PC address>:8740/ws`.
Every message is one JSON object in a text frame, at most 4 KB. This is version 2.

## Pairing QR code

The PC shows a QR code with this text:

```json
{"deskpilot":2,"name":"GAMING-PC","hosts":["192.168.1.50"],"port":8740,"fingerprint":"<64 hex characters>","code":"<one time code>"}
```

* `hosts`: the PC's IPv4 addresses, home network first. The phone tries `127.0.0.1` before them, which
  reaches the PC over a USB cable after `adb reverse tcp:8740 tcp:8740`.
* `fingerprint`: SHA-256 of the PC's own certificate, in lowercase hex. The phone trusts no other
  certificate, not even ones from public certificate authorities.
* `code`: 128 random bits. Only the newest code works, once, for 5 minutes.

## Signing in

The phone's first message must arrive within 10 seconds and be one of these:

| Message | When |
| :-- | :-- |
| `{"type":"pair","code":"..."}` | The first time, with the code from the QR code. |
| `{"type":"auth","key":"..."}` | Every time after that, with the key the phone got when it paired. |

The PC answers:

| Message | When |
| :-- | :-- |
| `{"type":"paired","key":"..."}` | The code was right. The phone keeps this 256 bit key in its secure storage. The PC keeps only its SHA-256 hash. |
| `{"type":"hello","name":"GAMING-PC","version":2}` | The phone is signed in. |
| `{"type":"error","message":"..."}`, then close code 1008 | The code or key is wrong. The app shows `message`. |

## After signing in

| Phone to PC | What the PC does |
| :-- | :-- |
| `{"type":"media","action":"playPause"}` | Presses the Play/Pause media key. |

The PC answers `{"type":"error","message":"..."}` when it can't do something, for example
`"Play/Pause works on Windows for now."`, and `{"type":"error","message":"Unknown message"}` to anything
else. A message over 4 KB closes the connection with close code 1009 (message too big).
