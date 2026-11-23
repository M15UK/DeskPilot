# DeskPilot protocol

The phone app and the PC agent talk over a WebSocket at `ws://<PC address>:8740/ws`.
Every message is one JSON object in a text frame, at most 4 KB.

This is version 1, from Phase 1. There is no pairing or encryption yet. Phase 2 adds both.

## PC to phone

| Message | When |
| :-- | :-- |
| `{"type":"hello","name":"GAMING-PC","version":1}` | Right after the phone connects. `name` is the PC's name. |
| `{"type":"error","message":"Play/Pause works on Windows for now."}` | The PC could not do what the phone asked. The app shows `message` to the user. |

## Phone to PC

| Message | What the PC does |
| :-- | :-- |
| `{"type":"media","action":"playPause"}` | Presses the Play/Pause media key. |

The PC answers any other message with `{"type":"error","message":"Unknown message"}`. A message over 4 KB
closes the connection with close code 1009 (message too big).
