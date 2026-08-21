class_name DiscordRichPresence
extends Node
## Discord Rich Presence in pure GDScript. No GDExtension, no Game SDK.
##
## Talks directly to the Discord client over its local IPC named pipe.
## A frame is [opcode u32][length u32] in little endian, then a JSON body.
## Handshake with your application id (op 0), then SET_ACTIVITY (op 1)
## when the presence changes.
##
## Windows only for now: on Linux and macOS the Discord IPC is a unix
## socket, and GDScript cannot open those. On any platform where the pipe
## is not available (web, mobile, headless), this node does nothing.
## Discord not running is not an error either: the client retries alone.
##
## Note: Godot only opens Windows named pipes with the "\\?\pipe\name"
## path form. The usual "\\.\pipe\name" form fails with ERR_FILE_NOT_FOUND.
##
## Usage:
##     var presence := DiscordRichPresence.new()
##     presence.app_id = "1234567890123456789"
##     add_child(presence)
##     presence.set_activity({"details": "In the Hub", "state": "Level 12"})

## Emitted when the handshake completes. [param user] is the Discord user
## object (id, username, ...).
signal presence_connected(user: Dictionary)
## Emitted when the pipe drops. The client retries by itself.
signal presence_disconnected

const _OP_HANDSHAKE: int = 0
const _OP_FRAME: int = 1
const _OP_CLOSE: int = 2
const _OP_PING: int = 3
const _OP_PONG: int = 4
## Discord can serve several IPC endpoints (main client, PTB, Canary).
const _MAX_PIPE_INDEX: int = 9
## Delay before looking for Discord again after a failure.
const _RETRY_SECONDS: float = 20.0

## Your Discord application id (from the Developer Portal). Set it before
## add_child, or call connect_now() after changing it.
@export var app_id: String = ""

var _pipe: FileAccess
var _ready_received: bool = false
var _wanted_activity: Dictionary = {}
var _activity_dirty: bool = false
var _retry_left: float = 0.0
var _nonce: int = 0


func _ready() -> void:
	connect_now()


func _process(delta: float) -> void:
	if _pipe == null:
		_retry_left -= delta
		if _retry_left <= 0.0:
			_retry_left = _RETRY_SECONDS
			_try_connect()
		return
	_poll_frames()
	if _activity_dirty and _ready_received and _pipe:
		_activity_dirty = false
		_send(_OP_FRAME, {
			"cmd": "SET_ACTIVITY",
			"args": {"pid": OS.get_process_id(), "activity": _wanted_activity},
			"nonce": str(_nonce),
		})
		_nonce += 1


## Restart the connection cycle. Safe to call at any time.
func connect_now() -> void:
	_retry_left = 0.0
	set_process(_supported())


## Ask Discord to show [param activity] (the SET_ACTIVITY activity object:
## details, state, timestamps, assets, party, ...). Remembered across
## reconnects, and safe to call while Discord is closed.
func set_activity(activity: Dictionary) -> void:
	_wanted_activity = activity
	_activity_dirty = true


## Remove the presence but keep the connection.
func clear_activity() -> void:
	set_activity({})


func _supported() -> bool:
	return OS.get_name() == "Windows" and DisplayServer.get_name() != "headless"


func _try_connect() -> void:
	if app_id.is_empty():
		return
	for index: int in _MAX_PIPE_INDEX + 1:
		# Only the "\\?\pipe\" path form works, see the class doc.
		var path: String = "\\\\?\\pipe\\discord-ipc-%d" % index
		var pipe: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
		if pipe == null:
			continue
		_pipe = pipe
		_ready_received = false
		_send(_OP_HANDSHAKE, {"v": 1, "client_id": app_id})
		return


func _poll_frames() -> void:
	# FileAccess reads are buffered: the first get_32() reads everything the
	# pipe holds into an internal buffer, and get_length() only sees the OS
	# pipe. So a frame's header and body must be read in the same pass:
	# after the header, a second get_length() check would report 0 while the
	# body sits in the buffer. Discord writes a frame in one write, so when
	# 8 bytes are visible the whole frame is readable.
	while _pipe and _pipe.get_length() >= 8:
		var op: int = _pipe.get_32()
		var length: int = _pipe.get_32()
		var body: Dictionary = {}
		if length > 0:
			var parsed: Variant = JSON.parse_string(
				_pipe.get_buffer(length).get_string_from_utf8())
			if parsed is Dictionary:
				body = parsed
		_handle_frame(op, body)


func _handle_frame(op: int, body: Dictionary) -> void:
	match op:
		_OP_FRAME:
			if not _ready_received and str(body.get("cmd", "")) == "DISPATCH" \
					and str(body.get("evt", "")) == "READY":
				_ready_received = true
				_activity_dirty = true  # Reassert the wanted presence.
				var user: Variant = (body.get("data", {}) as Dictionary).get("user", {})
				presence_connected.emit(user if user is Dictionary else {})
		_OP_PING:
			_send(_OP_PONG, body)
		_OP_CLOSE:
			_drop()


func _send(op: int, body: Dictionary) -> void:
	if _pipe == null:
		return
	var payload: PackedByteArray = JSON.stringify(body).to_utf8_buffer()
	_pipe.store_32(op)  # FileAccess defaults to little endian, the wire order.
	_pipe.store_32(payload.size())
	_pipe.store_buffer(payload)
	_pipe.flush()
	if _pipe.get_error() != OK:
		_drop()


func _drop() -> void:
	_pipe = null
	if _ready_received:
		_ready_received = false
		presence_disconnected.emit()
	_retry_left = _RETRY_SECONDS
