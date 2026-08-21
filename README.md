# Discord Rich Presence for Godot

Discord Rich Presence for Godot 4.3+ in pure GDScript. No GDExtension, no
DLLs, no Game SDK. One script.

<p align="center">
  <img src="docs/presence_ingame.png" alt="Rich Presence in a Discord profile" width="320">
</p>

I made this for my game [Ekonia Online](https://ekoniaonline.com) because I
ship a single binary file, and every existing Godot addon for Rich Presence
wraps the Discord Game SDK: several MB of native libraries to put next to
your game executable, for a feature that is in fact some JSON on a local
pipe. Also, Discord deprecated most of the Game SDK.

## Quick start

1. Copy `addons/discord_rich_presence/` into your project. Nothing to enable,
   it is a plain script class.
2. Create an application on the
   [Discord Developer Portal](https://discord.com/developers/applications)
   and copy its Application ID.
3. Use it:

```gdscript
var presence := DiscordRichPresence.new()
presence.app_id = "1234567890123456789"
add_child(presence)

presence.set_activity({
    "details": "In the Fungus Cave",
    "state": "Level 12",
    "timestamps": {"start": int(Time.get_unix_time_from_system())},
    "assets": {"large_image": "your_art_asset_key"},
})
```

Image keys come from your application page, under Rich Presence > Art
Assets. The key is the uploaded file name and cannot be renamed after.

## How it works

The Discord desktop client listens on a local named pipe. The protocol is
simple:

- one frame = `[opcode u32 LE][length u32 LE][JSON body]`
- op 0: handshake `{"v": 1, "client_id": "<app id>"}`, Discord answers READY
- op 1: `SET_ACTIVITY` when your presence changes
- op 3/4: ping/pong, op 2: close

The client connects when it can, retries every 20s while Discord is closed,
and sends the last activity again after a reconnect. Discord being absent
is never an error.

## Two Godot pitfalls to know

I hit both while writing this. They are handled by the addon, but if you
write your own client they will save you a day:

1. Godot only opens Windows named pipes with the `\\?\pipe\name` path
   form. The usual `\\.\pipe\name` form fails with `ERR_FILE_NOT_FOUND`.
2. `FileAccess` reads are buffered. The first `get_32()` reads everything
   the pipe holds into an internal buffer, and `get_length()` only sees the
   OS pipe. So read a frame's header and body in the same pass: a second
   `get_length()` check after the header will report 0 while your bytes
   are in the buffer.

## Platform support

| Platform | Presence |
|---|---|
| Windows | yes |
| Linux / macOS | not yet: the Discord IPC is a unix socket there, and GDScript cannot open those |
| Web / Android / iOS / headless | does nothing, by design |

You do not need any platform check on your side.

## API

- `app_id: String`: your Discord application id. Set it before add_child,
  or call `connect_now()` after changing it.
- `set_activity(activity: Dictionary)`: the SET_ACTIVITY activity object
  (details, state, timestamps, assets, party, ...). Remembered across
  reconnects, safe to call while Discord is closed.
- `clear_activity()`: remove the presence, keep the connection.
- signal `presence_connected(user: Dictionary)`: handshake done, `user` is
  the Discord user object.
- signal `presence_disconnected`: pipe dropped, the client retries alone.

## License

Source code under the [MIT License](LICENSE).
