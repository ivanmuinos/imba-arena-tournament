class_name LoopbackTransport
extends Transport
## In-process link between a server and a client (host playing locally, offline mode, tests).
## Messages still go through Wire.encode/decode, so serialization bugs show up here too.

var _remote: LoopbackTransport = null
var _inbox: Array = []
var _remote_id := 1
var _id := 1
var _server_side := false
var _announce := true
var _closed := false


## Returns [server_side, client_side]. The server sees the client as `client_id`.
static func pair(client_id := 1) -> Array:
	var s := LoopbackTransport.new()
	var c := LoopbackTransport.new()
	s._server_side = true
	s._remote_id = client_id
	s._id = Transport.SERVER_ID
	c._remote_id = Transport.SERVER_ID
	c._id = client_id
	s._remote = c
	c._remote = s
	return [s, c]


func local_id() -> int:
	return _id


func poll() -> void:
	if _announce:
		_announce = false
		if _server_side:
			peer_connected.emit(_remote_id)
			peer_joined.emit(self, _remote_id)
		else:
			connected_to_server.emit()
	var box := _inbox
	_inbox = []
	for item in box:
		if item == null:
			peer_disconnected.emit(_remote_id)
			continue
		var m = Wire.decode(item)
		if m != null:
			message.emit(_remote_id, m)


func send(_to: int, msg: Dictionary, _reliable := true) -> void:
	if _remote != null and not _closed:
		_remote._inbox.append(Wire.encode(msg))


func kick(_id_to_kick: int) -> void:
	close()


func close() -> void:
	if _closed:
		return
	_closed = true
	if _remote != null:
		_remote._inbox.append(null)
		_remote = null  # breaks the s <-> c reference cycle so both can be freed
