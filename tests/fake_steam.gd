class_name FakeSteam
extends RefCounted
## In-process stand-in for Steam: a shared "network" with lobbies and mailboxes, and one FakeSteamBackend per user.
## Callbacks are deferred to run_callbacks() like the real thing.

var lobbies := {}   # id -> {owner, members: [], data: {}, max, joinable}
var mailboxes := {} # steam_id -> [{from, data}]
var _next_lobby := 109775240000000000
var backends := {}


func user(steam_id: int, name: String) -> FakeSteamBackend:
	var b := FakeSteamBackend.new()
	b.net = self
	b.sid = steam_id
	b.name_ = name
	mailboxes[steam_id] = []
	backends[steam_id] = b
	return b


func new_lobby_id() -> int:
	_next_lobby += 1
	return _next_lobby


## Simulates accepting an invite in the Steam overlay.
func invite(lobby_id: int, to_steam_id: int) -> void:
	backends[to_steam_id]._queue.append(func(): backends[to_steam_id].join_requested.emit(lobby_id))


class FakeSteamBackend:
	extends SteamBackend
	var net: FakeSteam
	var sid := 0
	var name_ := ""
	var online := true
	var _queue: Array = []
	var closed_sessions: Array = []
	var accepted: Array = []

	func available() -> bool:
		return online

	func status_text() -> String:
		return "Conectado" if online else "Abrí el cliente de Steam"

	func persona_name() -> String:
		return name_

	func my_id() -> int:
		return sid

	func run_callbacks() -> void:
		var q := _queue
		_queue = []
		for c in q:
			c.call()

	func create_lobby(_friends_only: bool, max_members: int) -> void:
		var id := net.new_lobby_id()
		net.lobbies[id] = {"owner": sid, "members": [sid], "data": {"game": "imba-arena-tournament"}, "max": max_members, "joinable": true}
		_queue.append(func(): lobby_created.emit(id, true))

	func request_lobby_list(version: String) -> void:
		var out: Array = []
		for id in net.lobbies:
			var l: Dictionary = net.lobbies[id]
			if l.data.get("game", "") != "imba-arena-tournament":
				continue
			out.append({"id": id, "owner": l.owner, "name": l.data.get("name", ""), "members": l.members.size(), "max": l.max,
				"version": l.data.get("version", ""), "mode": l.data.get("mode", "2"), "map": l.data.get("map", "random")})
		_queue.append(func(): lobby_list.emit(out))

	func join_lobby(lobby_id: int) -> void:
		var l = net.lobbies.get(lobby_id)
		if l == null or l.members.size() >= l.max or not l.joinable:
			_queue.append(func(): lobby_joined.emit(lobby_id, false, 0))
			return
		l.members.append(sid)
		_queue.append(func(): lobby_joined.emit(lobby_id, true, l.owner))
		for m in l.members:
			if m != sid:
				var other: FakeSteamBackend = net.backends[m]
				other._queue.append(func(): other.member_changed.emit(lobby_id, sid, true))

	func leave_lobby(lobby_id: int) -> void:
		var l = net.lobbies.get(lobby_id)
		if l == null or not l.members.has(sid):
			return
		l.members.erase(sid)
		for m in l.members:
			var other: FakeSteamBackend = net.backends[m]
			other._queue.append(func(): other.member_changed.emit(lobby_id, sid, false))
		if l.owner == sid and not l.members.is_empty():
			l.owner = l.members[0]
		if l.members.is_empty():
			net.lobbies.erase(lobby_id)

	func set_lobby_data(lobby_id: int, key: String, value: String) -> void:
		net.lobbies[lobby_id].data[key] = value

	func lobby_owner(lobby_id: int) -> int:
		return net.lobbies[lobby_id].owner

	func lobby_member_ids(lobby_id: int) -> Array:
		return net.lobbies[lobby_id].members.duplicate() if net.lobbies.has(lobby_id) else []

	func send(to: int, data: PackedByteArray, _reliable: bool) -> void:
		if net.mailboxes.has(to):
			net.mailboxes[to].append({"from": sid, "data": data})

	func poll_messages() -> Array:
		var box: Array = net.mailboxes[sid]
		net.mailboxes[sid] = []
		return box

	func accept_session(from: int) -> void:
		accepted.append(from)

	func close_session(steam_id: int) -> void:
		closed_sessions.append(steam_id)
