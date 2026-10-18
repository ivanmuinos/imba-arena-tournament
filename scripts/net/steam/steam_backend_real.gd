class_name SteamBackendReal
extends SteamBackend
## GodotSteam (GDExtension 4.23.1, addons/godotsteam) behind the SteamBackend interface.
## NOT exercised against a live Steam client in development (none was available): the calls follow the GodotSteam
## documentation and the method/signal names were checked to exist in the loaded extension.

const APP_ID := 480  # Spacewar, for development; replace with the real app id when the game has one
const GAME_TAG := "imba-arena-tournament"
const MSG_CHANNEL := 7
const SEND_UNRELIABLE := 0
const SEND_RELIABLE := 8

var _steam = null
var _ok := false
var _status := "La extensión de Steam no está instalada"
var _pending_lobby := 0


func _init() -> void:
	if not Engine.has_singleton("Steam"):
		return
	_steam = Engine.get_singleton("Steam")
	var r: Dictionary = _steam.steamInitEx(APP_ID, false)
	if int(r.get("status", 1)) != 0:  # 0 = STEAM_API_INIT_RESULT_OK
		_status = "Abrí el cliente de Steam e iniciá sesión para usar las salas de Steam"
		return
	_ok = true
	_status = "Conectado a Steam como %s" % persona_name()
	_steam.lobby_created.connect(_on_lobby_created)
	_steam.lobby_match_list.connect(_on_match_list)
	_steam.lobby_joined.connect(_on_lobby_joined)
	_steam.lobby_chat_update.connect(_on_chat_update)
	_steam.join_requested.connect(func(lobby_id: int, _friend: int): join_requested.emit(lobby_id))
	_steam.network_messages_session_request.connect(func(remote: int): _steam.acceptSessionWithUser(remote))
	_steam.network_messages_session_failed.connect(func(_reason, remote: int, _state, _dbg): session_failed.emit(remote))
	if _steam.has_method("initRelayNetworkAccess"):
		_steam.initRelayNetworkAccess()


func available() -> bool:
	return _ok


func status_text() -> String:
	return _status


func persona_name() -> String:
	return str(_steam.getPersonaName()) if _ok else ""


func my_id() -> int:
	return int(_steam.getSteamID()) if _ok else 0


func run_callbacks() -> void:
	if _ok:
		_steam.run_callbacks()


func create_lobby(friends_only: bool, max_members: int) -> void:
	# LOBBY_TYPE_FRIENDS_ONLY = 1, LOBBY_TYPE_PUBLIC = 2
	_steam.createLobby(1 if friends_only else 2, max_members)


func request_lobby_list(version: String) -> void:
	_steam.addRequestLobbyListStringFilter("game", GAME_TAG, 0)  # 0 = equal
	_steam.addRequestLobbyListStringFilter("version", version, 0)
	_steam.requestLobbyList()


func join_lobby(lobby_id: int) -> void:
	_steam.joinLobby(lobby_id)


func leave_lobby(lobby_id: int) -> void:
	_steam.leaveLobby(lobby_id)


func set_lobby_data(lobby_id: int, key: String, value: String) -> void:
	_steam.setLobbyData(lobby_id, key, value)


func lobby_owner(lobby_id: int) -> int:
	return int(_steam.getLobbyOwner(lobby_id))


func lobby_member_ids(lobby_id: int) -> Array:
	var out: Array = []
	for i in int(_steam.getNumLobbyMembers(lobby_id)):
		out.append(int(_steam.getLobbyMemberByIndex(lobby_id, i)))
	return out


func invite_dialog(lobby_id: int) -> void:
	_steam.activateGameOverlayInviteDialog(lobby_id)


func send(to: int, data: PackedByteArray, reliable: bool) -> void:
	_steam.sendMessageToUser(to, data, SEND_RELIABLE if reliable else SEND_UNRELIABLE, MSG_CHANNEL)


func poll_messages() -> Array:
	var out: Array = []
	if not _ok:
		return out
	for m in _steam.receiveMessagesOnChannel(MSG_CHANNEL, 64):
		var from := int(m.get("identity", m.get("remote_steam_id", 0)))
		out.append({"from": from, "data": m.get("payload", PackedByteArray())})
	return out


func accept_session(from: int) -> void:
	_steam.acceptSessionWithUser(from)


func close_session(steam_id: int) -> void:
	_steam.closeSessionWithUser(steam_id)


func _on_lobby_created(connect: int, lobby_id: int) -> void:
	var ok := connect == 1
	if ok:
		_steam.setLobbyData(lobby_id, "game", GAME_TAG)
		_steam.setLobbyJoinable(lobby_id, true)
	lobby_created.emit(lobby_id, ok)


func _on_match_list(lobbies: Array) -> void:
	var entries: Array = []
	for id in lobbies:
		entries.append({
			"id": int(id), "owner": int(_steam.getLobbyOwner(id)), "name": str(_steam.getLobbyData(id, "name")),
			"members": int(_steam.getNumLobbyMembers(id)), "max": int(_steam.getLobbyMemberLimit(id)),
			"version": str(_steam.getLobbyData(id, "version")), "mode": str(_steam.getLobbyData(id, "mode")), "map": str(_steam.getLobbyData(id, "map")),
		})
	lobby_list.emit(entries)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	lobby_joined.emit(lobby_id, response == 1, int(_steam.getLobbyOwner(lobby_id)))


func _on_chat_update(lobby_id: int, changed_id: int, _making_change: int, chat_state: int) -> void:
	# chat_state bit 1 = entered; 2 = left; 4 = disconnected; 8 = kicked; 16 = banned
	member_changed.emit(lobby_id, changed_id, (chat_state & 1) != 0)
