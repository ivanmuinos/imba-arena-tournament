class_name PeerTransport
extends Transport
## Transport over any Godot MultiplayerPeer: ENet today (PeerTransport.host / .join), and
## GodotSteam's SteamMultiplayerPeer later (`PeerTransport.wrap(steam_peer)`).
## Raw packets are used (no SceneMultiplayer/RPC), carrying Wire-encoded messages.

const CH_RELIABLE := 0
const CH_FAST := 1
const CHANNELS := 2
const MAX_UNRELIABLE := 1300

var peer: MultiplayerPeer
var max_inbound := 262144
var _is_server := false
var _announced := false
var _closed := false


## Starts an ENet server. Returns null (and prints) when the port cannot be opened.
static func host(port: int, max_clients := 8) -> PeerTransport:
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_clients, CHANNELS)
	if err != OK:
		push_warning("No se pudo abrir el puerto %d (error %d)" % [port, err])
		return null
	var t := PeerTransport.wrap(enet)
	t._is_server = true
	t.max_inbound = 4096  # clients only send tiny messages
	return t


## Connects to an ENet server. Returns null on immediate failure.
static func join(address: String, port: int) -> PeerTransport:
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(address, port, CHANNELS)
	if err != OK:
		push_warning("No se pudo conectar a %s:%d (error %d)" % [address, port, err])
		return null
	return PeerTransport.wrap(enet)


## Any MultiplayerPeer that is already created/connected (Steam, WebRTC, ...).
static func wrap(p: MultiplayerPeer) -> PeerTransport:
	var t := PeerTransport.new()
	t.peer = p
	t._is_server = p.get_unique_id() == Transport.SERVER_ID and p.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTING
	p.peer_connected.connect(t._on_peer_connected)
	p.peer_disconnected.connect(t._on_peer_gone)
	return t


func local_id() -> int:
	return peer.get_unique_id()


func _on_peer_gone(id: int) -> void:
	peer_disconnected.emit(id)


func _on_peer_connected(id: int) -> void:
	if _is_server:
		peer_connected.emit(id)
		peer_joined.emit(self, id)
	elif id == Transport.SERVER_ID:
		connected_to_server.emit()


func poll() -> void:
	if _closed:
		return
	peer.poll()
	if not _is_server and not _announced and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_announced = true
		connection_failed.emit()
		return
	while peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var bytes := peer.get_packet()
		if bytes.size() > max_inbound:
			continue
		var m = Wire.decode(bytes)
		if m != null:
			message.emit(from, m)


func send(to: int, msg: Dictionary, reliable := true) -> void:
	if _closed or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var bytes := Wire.encode(msg)
	# Unreliable packets above the MTU get dropped by ENet: send those reliably instead.
	var fast := not reliable and bytes.size() <= MAX_UNRELIABLE
	peer.set_target_peer(to)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if fast else MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.transfer_channel = CH_FAST if not reliable else CH_RELIABLE
	peer.put_packet(bytes)


func kick(id: int) -> void:
	if not _closed:
		peer.disconnect_peer(id)


func close() -> void:
	if _closed:
		return
	_closed = true
	peer.close()
