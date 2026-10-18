class_name GameClient
extends RefCounted
## The player's side of the connection: lobby/match messages in, inputs and casts out.
## It only knows the Transport interface (see transport.gd).

signal connected
signal welcomed
signal lobby_updated(msg: Dictionary)
signal match_started(msg: Dictionary)
signal state_received(snap: Dictionary)
signal fx_received(list: Array)
signal kill_received(msg: Dictionary)
signal match_ended(msg: Dictionary)
signal server_error(text: String)
signal closed(reason: String)

var transport: Transport
var peer_id := 0
var is_host := false
var in_match := false
var unit_id := -1
var roster: Array = []
var map_id := "bridge"
var mode := 2
var lobby: Dictionary = {}
var buffer := SnapshotBuffer.new()
var rtt_ms := -1
var hello: Dictionary = {}
## Overridable in tests; normally the version in project.godot.
var hello_version := GameServer.game_version()

var _ping_timer := 0.0
var _greeted := false


## `hello`: {name, cls, pref}. Sent as soon as the transport is connected.
func attach(t: Transport, p_hello: Dictionary) -> void:
	transport = t
	hello = p_hello
	t.connected_to_server.connect(_on_connected)
	t.connection_failed.connect(_on_failed)
	t.peer_disconnected.connect(_on_lost)
	t.message.connect(_on_message)


func poll(delta_ms: float) -> void:
	if transport == null:
		return
	transport.poll()
	if _greeted:
		_ping_timer -= delta_ms
		if _ping_timer <= 0.0:
			_ping_timer = 2000.0
			_send({"t": "ping", "at": Time.get_ticks_msec()}, false)


func close() -> void:
	if transport != null:
		_send({"t": "leave"})
		transport.poll()
		transport.close()
		transport = null
	buffer.clear()


func _send(msg: Dictionary, reliable := true) -> void:
	if transport != null:
		transport.send(Transport.SERVER_ID, msg, reliable)


func _on_failed() -> void:
	closed.emit("No se pudo conectar al servidor")


func _on_lost(_id: int) -> void:
	closed.emit("Se perdió la conexión con el servidor")


func _on_connected() -> void:
	_greeted = true
	var h := hello.duplicate()
	h["t"] = "hello"
	h["v"] = GameServer.PROTO
	h["ver"] = hello_version
	_send(h)
	connected.emit()


func _on_message(_from: int, msg: Dictionary) -> void:
	match msg.t:
		"welcome":
			peer_id = int(msg.peer)
			is_host = bool(msg.host)
			welcomed.emit()
		"lobby":
			lobby = msg
			if in_match:
				in_match = false
			lobby_updated.emit(msg)
		"match":
			in_match = true
			unit_id = int(msg.you)
			roster = msg.roster
			map_id = msg.map
			mode = int(msg.mode)
			buffer.clear()
			match_started.emit(msg)
		"state":
			if not SnapshotCodec.is_valid(msg):
				return
			var snap := SnapshotCodec.unpack(msg)
			if buffer.push(snap, Time.get_ticks_msec()):
				state_received.emit(snap)
		"fx":
			fx_received.emit(msg.list)
		"kill":
			kill_received.emit(msg)
		"end":
			match_ended.emit(msg)
		"error":
			server_error.emit(str(msg.get("text", "")))
		"closed":
			closed.emit(str(msg.get("reason", "")))
		"pong":
			if typeof(msg.get("at")) in [TYPE_INT, TYPE_FLOAT]:
				rtt_ms = clampi(Time.get_ticks_msec() - int(msg.at), 0, 9999)


# ---------------------------------------------------------------- outgoing

func send_input(dx: float, dz: float, ax: float, az: float) -> void:
	_send({"t": "input", "dx": dx, "dz": dz, "ax": ax, "az": az}, false)


func send_cast(msg: Dictionary) -> void:
	var m := msg.duplicate()
	m["t"] = "cast"
	_send(m)


func send_target(id: int) -> void:
	_send({"t": "target", "id": id})


## Auto-attack on/off against enemy `id` (the server ignores it for casters).
func send_auto(on: bool, id := -1) -> void:
	_send({"t": "auto", "on": on, "id": id})


func send_stop_cast() -> void:
	_send({"t": "stopcast"})


## Practice arena controls: "reset", "nocd" (on) or "ult".
func send_practice(cmd: String, on := true) -> void:
	_send({"t": "practice", "cmd": cmd, "on": on})


func send_jump() -> void:
	_send({"t": "jump"})


## Lobby settings: {cls?, pref?, and, for the host, mode?, diff?, map?}.
func send_set(settings: Dictionary) -> void:
	var m := settings.duplicate()
	m["t"] = "set"
	_send(m)


func send_start() -> void:
	_send({"t": "start"})
