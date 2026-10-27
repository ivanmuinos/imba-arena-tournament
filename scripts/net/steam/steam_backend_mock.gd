class_name SteamBackendMock
extends SteamBackend
## Steam stand-in for development until the game is on Steam (`--steam-mock[=Name]`): copies of the game on this
## machine or the same LAN find each other over UDP and act as Steam friends of each other, with rich presence,
## lobbies (owned and served by their creator) and peer-to-peer messages, so the whole Steam flow (home panel,
## Unirse, lobby, match over SteamTransport) runs without Steam. No overlay: overlay actions are only logged.
##
## Every instance binds the first free UDP port of [base, base + count) and once a second announces itself to all
## those ports on 127.0.0.1 and to the LAN broadcast address. Lobbies are announced by their owner; join/leave go to
## the owner, which tells the members. Packets are var_to_bytes dictionaries (no objects decoded).

const APP_ID := 480
const DEFAULT_BASE := 47600
const DEFAULT_COUNT := 16
const ANNOUNCE_EVERY := 1.0
## A friend not heard from for this long shows as offline.
const TIMEOUT := 4.0
const GAME_TAG := "imba-arena-tournament"

var verbose := false
## Seconds a join waits for the lobby's owner to be discovered (a copy launched with --steam-join knows nobody yet).
var join_wait := 5.0
var _sock := PacketPeerUDP.new()
var _ok := false
var _base := DEFAULT_BASE
var _count := DEFAULT_COUNT
var _port := 0
var _id := 0
var _name := ""
var _presence := {}
var _peers := {}    # steam_id -> {name, ip, port, presence, lobby, seen (s), online}
var _lobbies := {}  # lobby_id -> {owner, members, data, max, public}: ours (authoritative) and the ones announced
var _inbox: Array = []
var _pending_joins := {}  # lobby_id -> time it started waiting
var _queue: Array = []
var _next_announce := 0.0
var _rng := RandomNumberGenerator.new()


func _init(p_name := "", p_base := DEFAULT_BASE, p_count := DEFAULT_COUNT, p_id := 0, p_verbose := false) -> void:
	verbose = p_verbose
	_base = p_base
	_count = p_count
	_rng.randomize()
	_id = p_id if p_id != 0 else 76561199000000000 + _rng.randi_range(1, 999999)
	_name = p_name if p_name != "" else "Jugador-%d" % (_id % 10000)
	for port in range(_base, _base + _count):
		if _sock.bind(port, "*") == OK:
			_port = port
			break
	if _port == 0:
		push_warning("[steam-mock] no hay puertos libres en %d-%d" % [_base, _base + _count - 1])
		return
	_sock.set_broadcast_enabled(true)
	_ok = true
	_log("%s (id %d) escuchando en el puerto %d" % [_name, _id, _port])


func _log(text: String) -> void:
	if verbose:
		print("[steam-mock] ", text)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func available() -> bool:
	return _ok


func status_text() -> String:
	return "Steam simulado (sin Steam real) como %s" % _name if _ok else "Steam simulado: no hay puertos UDP libres"


func persona_name() -> String:
	return _name


func my_id() -> int:
	return _id


func app_id() -> int:
	return APP_ID


func persona_of(steam_id: int) -> String:
	if steam_id == _id:
		return _name
	return str(_peers[steam_id].name) if _peers.has(steam_id) else ""


func run_callbacks() -> void:
	if not _ok:
		return
	if _now() >= _next_announce:
		announce()
	while _sock.get_available_packet_count() > 0:
		var raw := _sock.get_packet()
		var msg = bytes_to_var(raw)
		if typeof(msg) == TYPE_DICTIONARY and int(msg.get("from", 0)) != _id:
			_handle(msg, _sock.get_packet_ip(), _sock.get_packet_port())
	_expire()
	for l in _pending_joins.keys():
		if _lobbies.has(l) and _peers.has(int(_lobbies[l].owner)):
			_pending_joins.erase(l)
			join_lobby(l)
		elif _now() - float(_pending_joins[l]) > join_wait:
			_pending_joins.erase(l)
			_queue.append(func(): lobby_joined.emit(l, false, 0))
	var q := _queue
	_queue = []
	for c in q:
		c.call()


func shutdown() -> void:
	if not _ok:
		return
	for id in _lobbies.keys():
		if _lobbies[id].members.has(_id):
			leave_lobby(id)
	_broadcast({"t": "bye"})
	_ok = false
	_sock.close()


# ---------------------------------------------------------------- discovery

## Tells everyone who we are, where we are and the lobbies we own (also called by run_callbacks once a second).
func announce() -> void:
	if not _ok:
		return
	_next_announce = _now() + ANNOUNCE_EVERY
	var owned := {}
	for id in _lobbies:
		if _lobbies[id].owner == _id:
			owned[id] = _lobbies[id]
	_broadcast({"t": "hello", "name": _name, "presence": _presence, "lobby": _my_lobby(), "lobbies": owned})


func _broadcast(msg: Dictionary) -> void:
	msg["from"] = _id
	var bytes := var_to_bytes(msg)
	for port in range(_base, _base + _count):
		if port != _port:
			_sock.set_dest_address("127.0.0.1", port)
			_sock.put_packet(bytes)
		_sock.set_dest_address("255.255.255.255", port)
		_sock.put_packet(bytes)  # fails quietly without a network


func _send_to(steam_id: int, msg: Dictionary) -> void:
	if not _peers.has(steam_id):
		return
	msg["from"] = _id
	var p: Dictionary = _peers[steam_id]
	_sock.set_dest_address(p.ip, p.port)
	_sock.put_packet(var_to_bytes(msg))


func _expire() -> void:
	var t := _now()
	for id in _peers:
		var p: Dictionary = _peers[id]
		if p.online and t - float(p.seen) > TIMEOUT:
			_gone(id)


func _gone(id: int) -> void:
	var p: Dictionary = _peers[id]
	p.online = false
	p.lobby = 0
	p.presence = {}
	for l in _lobbies.keys():
		var lob: Dictionary = _lobbies[l]
		if lob.owner == id:
			if lob.members.has(_id):  # our host vanished: the transport sees the owner leave
				_queue.append(func(): member_changed.emit(l, id, false))
			_lobbies.erase(l)
		elif lob.owner == _id and lob.members.has(id):
			_drop_member(l, id)
	_queue.append(func(): friends_changed.emit())


func _handle(msg: Dictionary, ip: String, port: int) -> void:
	var from := int(msg.from)
	if not _peers.has(from):
		_peers[from] = {"name": "", "ip": ip, "port": port, "presence": {}, "lobby": 0, "seen": 0.0, "online": false}
	var p: Dictionary = _peers[from]
	match str(msg.get("t", "")):
		"hello":
			var before := [p.name, p.presence, p.lobby, p.online]
			p.name = str(msg.get("name", ""))
			p.ip = ip
			p.port = port
			p.presence = msg.get("presence", {})
			p.lobby = int(msg.get("lobby", 0))
			p.seen = _now()
			p.online = true
			var owned: Dictionary = msg.get("lobbies", {})
			for l in _lobbies.keys():  # lobbies it no longer owns are gone
				if _lobbies[l].owner == from and not owned.has(l):
					_lobbies.erase(l)
			for l in owned:
				_lobbies[int(l)] = owned[l]
			if before != [p.name, p.presence, p.lobby, p.online]:
				_queue.append(func(): friends_changed.emit())
		"bye":
			if p.online:
				_gone(from)
		"msg":
			_inbox.append({"from": from, "data": msg.get("data", PackedByteArray())})
		"dm":
			if typeof(msg.get("text")) == TYPE_STRING:
				var text: String = msg.text
				_queue.append(func(): dm_received.emit(from, text))
		"join":
			_on_join_request(from, int(msg.lobby))
		"joined":
			var l := int(msg.lobby)
			if bool(msg.ok):
				_lobbies[l] = msg.record
			_queue.append(func(): lobby_joined.emit(l, bool(msg.ok), from if bool(msg.ok) else 0))
		"leave":
			var l := int(msg.lobby)
			if _lobbies.has(l) and _lobbies[l].owner == _id and _lobbies[l].members.has(from):
				_drop_member(l, from)
		"member":
			var l := int(msg.lobby)
			if _lobbies.has(l):
				_lobbies[l] = msg.record
			_queue.append(func(): member_changed.emit(l, int(msg.sid), bool(msg.joined)))


# ---------------------------------------------------------------- lobbies (the owner is the authority)

func _my_lobby() -> int:
	for id in _lobbies:
		if _lobbies[id].members.has(_id):
			return id
	return 0


func create_lobby(friends_only: bool, max_members: int) -> void:
	var id := 109775240000000000 + _rng.randi_range(1, 99999999)
	_lobbies[id] = {"owner": _id, "members": [_id], "data": {"game": GAME_TAG}, "max": max_members, "public": not friends_only}
	_log("sala %d creada (%s, %d lugares)" % [id, "sólo amigos" if friends_only else "pública", max_members])
	_queue.append(func(): lobby_created.emit(id, true))
	announce()


func request_lobby_list(version: String) -> void:
	request_ranked_lobbies(version, {}, "", 0)


func request_ranked_lobbies(version: String, filters: Dictionary, near_key: String, near_value: int) -> void:
	var out: Array = []
	for id in _lobbies:
		var l: Dictionary = _lobbies[id]
		if not l.public or l.data.get("game", "") != GAME_TAG or (version != "" and l.data.get("version", "") != version):
			continue
		if filters.keys().any(func(k): return str(l.data.get(k, "")) != str(filters[k])):
			continue
		out.append({"id": id, "owner": l.owner, "name": l.data.get("name", ""), "members": l.members.size(), "max": l.max,
			"version": l.data.get("version", ""), "mode": l.data.get("mode", "2"), "map": l.data.get("map", "random")})
	if near_key != "":
		out.sort_custom(func(a, b): return absi(int(_lobbies[a.id].data.get(near_key, 0)) - near_value) < absi(int(_lobbies[b.id].data.get(near_key, 0)) - near_value))
	_queue.append(func(): lobby_list.emit(out))


func join_lobby(lobby_id: int) -> void:
	var l = _lobbies.get(lobby_id)
	if l == null or not _peers.has(int(l.owner)):
		_pending_joins[lobby_id] = _now()
		_log("sala %d: esperando encontrar a su dueño" % lobby_id)
		return
	_log("pidiendo entrar a la sala %d" % lobby_id)
	_send_to(int(l.owner), {"t": "join", "lobby": lobby_id})


func _on_join_request(from: int, lobby_id: int) -> void:
	var l = _lobbies.get(lobby_id)
	var ok: bool = l != null and l.owner == _id and (l.members.has(from) or l.members.size() < int(l.max))
	if not ok:
		_send_to(from, {"t": "joined", "lobby": lobby_id, "ok": false})
		return
	if not l.members.has(from):
		l.members.append(from)
	_send_to(from, {"t": "joined", "lobby": lobby_id, "ok": true, "record": l})
	_tell_members(lobby_id, from, true)
	_queue.append(func(): member_changed.emit(lobby_id, from, true))
	announce()


func _drop_member(lobby_id: int, sid: int) -> void:
	var l: Dictionary = _lobbies[lobby_id]
	l.members.erase(sid)
	_tell_members(lobby_id, sid, false)
	_queue.append(func(): member_changed.emit(lobby_id, sid, false))
	announce()


func _tell_members(lobby_id: int, sid: int, joined: bool) -> void:
	var l: Dictionary = _lobbies[lobby_id]
	for m in l.members:
		if m != _id and m != sid:
			_send_to(m, {"t": "member", "lobby": lobby_id, "sid": sid, "joined": joined, "record": l})


func leave_lobby(lobby_id: int) -> void:
	var l = _lobbies.get(lobby_id)
	if l == null or not l.members.has(_id):
		return
	if l.owner == _id:  # the owner closes it: members see the owner leave, as when a Steam host quits
		for m in l.members:
			if m != _id:
				_send_to(m, {"t": "member", "lobby": lobby_id, "sid": _id, "joined": false, "record": l})
		_lobbies.erase(lobby_id)
	else:
		_send_to(int(l.owner), {"t": "leave", "lobby": lobby_id})
		_lobbies.erase(lobby_id)
	announce()


func set_lobby_data(lobby_id: int, key: String, value: String) -> void:
	if _lobbies.has(lobby_id) and _lobbies[lobby_id].owner == _id:
		_lobbies[lobby_id].data[key] = value


func lobby_owner(lobby_id: int) -> int:
	return int(_lobbies[lobby_id].owner) if _lobbies.has(lobby_id) else 0


func lobby_member_ids(lobby_id: int) -> Array:
	return _lobbies[lobby_id].members.duplicate() if _lobbies.has(lobby_id) else []


func invite_dialog(lobby_id: int) -> void:
	_log("invitar (sala %d): en el simulado tus amigos entran con Unirse desde su panel" % lobby_id)


# ---------------------------------------------------------------- messages

func send(to: int, data: PackedByteArray, _reliable: bool) -> void:
	_send_to(to, {"t": "msg", "data": data})


func send_dm(to: int, text: String) -> void:
	_send_to(to, {"t": "dm", "text": text})


func poll_messages() -> Array:
	var box := _inbox
	_inbox = []
	return box


# ---------------------------------------------------------------- friends, presence, overlay

func friends() -> Array:
	var out: Array = []
	for id in _peers:
		var p: Dictionary = _peers[id]
		if str(p.name) == "":
			continue
		out.append({"id": id, "name": p.name, "state": 1 if p.online else 0, "app": APP_ID if p.online else 0,
			"lobby": int(p.lobby), "status": str(p.presence.get("status", ""))})
	return out


func set_presence(values: Dictionary) -> void:
	for k in values:
		if str(values[k]) == "":
			_presence.erase(k)
		else:
			_presence[k] = str(values[k])
	announce()


## A coloured square per player (Steam would send their picture).
func request_avatar(steam_id: int) -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.from_hsv(float(steam_id % 360) / 360.0, 0.55, 0.85))
	var tex := ImageTexture.create_from_image(img)
	_queue.append(func(): avatar_ready.emit(steam_id, tex))


## There is no overlay here: the home panel shows Social.overlay_note() instead.
func open_overlay(kind: String, steam_id: int) -> bool:
	_log("la superposición de Steam abriría: %s %s" % [kind, persona_of(steam_id) if steam_id != 0 else ""])
	return false


func find_leaderboard(board: String) -> void:
	_queue.append(func(): leaderboard_ready.emit(board, false))
