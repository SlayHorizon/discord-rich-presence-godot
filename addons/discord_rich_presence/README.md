# Discord Rich Presence for Godot

Discord Rich Presence for Godot 4.3+ in pure GDScript. No GDExtension, no
DLLs, no Game SDK. This folder is the whole addon: one script class,
`DiscordRichPresence`, nothing to enable in the editor.

```gdscript
var presence := DiscordRichPresence.new()
presence.app_id = "1234567890123456789"  # Discord Developer Portal
add_child(presence)
presence.set_activity({"details": "In the Hub", "state": "Level 12"})
```

Windows only for now: on Linux and macOS the Discord IPC is a unix socket,
and GDScript cannot open those. Everywhere else the node does nothing.

Full documentation and the two Godot pitfalls this addon works around are
in the repository README. [MIT License](../../LICENSE).
