class_name SteamTransport
extends Transport
## Transport over Steam peer-to-peer messages (Steam relays them, no port forwarding). Game code keeps using
## Godot-style peer ids: the server is 1 and every Steam user that talks to it gets the next free integer.

const CLIENT_ID := 2

var backend: SteamBackend
var lobby_id := 0
var _is_server := false
var _host_sid := 0
var _peer_by_sid := {}
var _sid_by_peer := {}
var _next_peer := 2
var _announced := false
var _closed := false


## Server side: peers are the members of `lobby` that send us something.
static func host(p_backend: SteamBackend, p_lobby: int) -> SteamTransport:
	var t := SteamTransport.new()
	t.backend = p_backend
	t.lobby_id = p_lobby
	t._is_server = true
	p_backend.member_changed.connect(t._on_member)
	p_backend.session_failed.connect(t._on_failed)
	return t


## Client side: talks to the lobby owner.
static func join(p_backend: SteamBackend, p_lobby: int, host_steam_id: int) -> SteamTransport:
	var t := SteamTransport.new()
	t.backend = p_backend
	t.lobby_id = p_lobby
	t._host_sid = host_steam_id
	p_backend.member_changed.connect(t._on_member)
	p_backend.session_failed.connect(t._on_failed)
	return t


func local_id() -> int:
	return SERVER_ID if _is_server else CLIENT_ID


func peer_for(steam_id: int) -> int:
	return _peer_by_sid.get(steam_id, -1)


func steam_id_of(peer: int) -> int:
	return _sid_by_peer.get(peer, 0)


func poll() -> void:
	if _closed:
		return
	if not _is_server and not _announced:
		_announced = true
		connected_to_server.emit()
	for m in backend.poll_messages():
		_on_packet(m.from, m.data)


func _on_packet(from: int, data: PackedByteArray) -> void:
	var peer := SERVER_ID
	if _is_server:
		if not _peer_by_sid.has(from):
			# Only lobby members may talk to the server.
			if not backend.lobby_member_ids(lobby_id).has(from):
				return
			peer = _next_peer
			_next_peer += 1
			_peer_by_sid[from] = peer
			_sid_by_peer[peer] = from
			backend.accept_session(from)
			peer_connected.emit(peer)
			peer_joined.emit(self, peer)
		peer = _peer_by_sid[from]
	elif from != _host_sid:
		return
	if data.size() > (4096 if _is_server else 262144):
		return
	var msg = Wire.decode(data)
	if msg != null:
		message.emit(peer, msg)


func send(to: int, msg: Dictionary, reliable := true) -> void:
	if _closed:
		return
	var sid: int = _sid_by_peer.get(to, 0) if _is_server else _host_sid
	if sid != 0:
		backend.send(sid, Wire.encode(msg), reliable)


func kick(id: int) -> void:
	var sid: int = _sid_by_peer.get(id, 0)
	if sid != 0:
		backend.close_session(sid)
		_drop(sid)


func close() -> void:
	if _closed:
		return
	_closed = true
	for sid in _peer_by_sid.keys():
		backend.close_session(sid)
	if not _is_server:
		backend.close_session(_host_sid)
	backend.leave_lobby(lobby_id)


func _drop(sid: int) -> void:
	if _is_server and _peer_by_sid.has(sid):
		var peer: int = _peer_by_sid[sid]
		_peer_by_sid.erase(sid)
		_sid_by_peer.erase(peer)
		peer_disconnected.emit(peer)
	elif not _is_server and sid == _host_sid and not _closed:
		peer_disconnected.emit(SERVER_ID)


func _on_member(lobby: int, steam_id: int, joined: bool) -> void:
	if lobby == lobby_id and not joined:
		_drop(steam_id)


func _on_failed(steam_id: int) -> void:
	_drop(steam_id)
