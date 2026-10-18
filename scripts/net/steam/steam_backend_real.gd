class_name SteamBackendReal
extends SteamBackend
## GodotSteam (GDExtension 4.23.1, addons/godotsteam) behind the SteamBackend interface.
## Checked against a live Steam client (init, lobby create/list); method and signal signatures match the loaded extension.

const APP_ID := 480  # Spacewar, for development; replace with the real app id when the game has one
const GAME_TAG := "imba-arena-tournament"
const MSG_CHANNEL := 7
const SEND_UNRELIABLE := 0
const SEND_RELIABLE := 8
const DISTANCE_WORLDWIDE := 3

## Print every Steam callback and a message count (`--log` / `--steam-log`): the real integration is debugged from these lines.
var verbose := false
var _steam = null
var _ok := false
var _status := "La extensión de Steam no está instalada"
var _pending_lobby := 0
var _sent := 0
var _received := 0
var _hooks: Array = []  # [signal name, callable]: all disconnected in shutdown()


func _init(p_verbose := false) -> void:
	verbose = p_verbose
	if not Engine.has_singleton("Steam"):
		_log("la extensión GodotSteam no está cargada")
		return
	_steam = Engine.get_singleton("Steam")
	var r: Dictionary = _steam.steamInitEx(APP_ID, false)
	_log("steamInitEx(%d) -> %s" % [APP_ID, r])
	if int(r.get("status", 1)) != 0:  # 0 = STEAM_API_INIT_RESULT_OK
		_status = "Abrí el cliente de Steam e iniciá sesión para usar las salas de Steam"
		return
	_ok = true
	_status = "Conectado a Steam como %s" % persona_name()
	_log("%s (SteamID %d)" % [_status, my_id()])
	_hook("lobby_created", _on_lobby_created)
	_hook("lobby_match_list", _on_match_list)
	_hook("lobby_joined", _on_lobby_joined)
	_hook("lobby_chat_update", _on_chat_update)
	_hook("join_requested", func(lobby_id: int, friend: int):
		_log("invitación aceptada: sala %d (de %d)" % [lobby_id, friend])
		join_requested.emit(lobby_id))
	_hook("network_messages_session_request", func(remote: int):
		_log("pedido de sesión de %d: aceptado" % remote)
		_steam.acceptSessionWithUser(remote))
	_hook("network_messages_session_failed", func(reason, remote: int, state, dbg):
		_log("sesión con %d falló: motivo=%s estado=%s %s" % [remote, reason, state, dbg])
		session_failed.emit(remote))
	if _steam.has_method("initRelayNetworkAccess"):
		_steam.initRelayNetworkAccess()


func _hook(sig: String, c: Callable) -> void:
	_steam.connect(sig, c)
	_hooks.append([sig, c])


func _log(text: String) -> void:
	if verbose:
		print("[steam] ", text)


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


## Without this the process crashed on exit (segfault, exit code 139) whenever Steam had been initialized: the extension
## is torn down after the scripts, and a signal of the Steam singleton still connected to a script callable crashes it.
func shutdown() -> void:
	if not _ok:
		return
	_ok = false
	_log("cerrando Steam")
	for h in _hooks:
		if _steam.is_connected(h[0], h[1]):
			_steam.disconnect(h[0], h[1])
	_hooks.clear()
	_steam.steamShutdown()


func create_lobby(friends_only: bool, max_members: int) -> void:
	# LOBBY_TYPE_FRIENDS_ONLY = 1, LOBBY_TYPE_PUBLIC = 2
	_log("creando sala (%s, %d lugares)" % ["sólo amigos" if friends_only else "pública", max_members])
	_steam.createLobby(1 if friends_only else 2, max_members)


func request_lobby_list(version: String) -> void:
	_steam.addRequestLobbyListStringFilter("game", GAME_TAG, 0)  # 0 = equal
	_steam.addRequestLobbyListStringFilter("version", version, 0)
	_steam.addRequestLobbyListDistanceFilter(DISTANCE_WORLDWIDE)  # the default only lists nearby regions
	_log("buscando salas (versión %s)" % version)
	_steam.requestLobbyList()


func join_lobby(lobby_id: int) -> void:
	_log("entrando a la sala %d" % lobby_id)
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
	var r := int(_steam.sendMessageToUser(to, data, SEND_RELIABLE if reliable else SEND_UNRELIABLE, MSG_CHANNEL))
	_sent += 1
	if verbose and (_sent <= 5 or _sent % 500 == 0 or r != 1):  # 1 = k_EResultOK
		_log("enviado #%d a %d (%d bytes, %s) -> %d" % [_sent, to, data.size(), "fiable" if reliable else "no fiable", r])


func poll_messages() -> Array:
	var out: Array = []
	if not _ok:
		return out
	for m in _steam.receiveMessagesOnChannel(MSG_CHANNEL, 64):
		var from := int(m.get("identity", m.get("remote_steam_id", 0)))
		out.append({"from": from, "data": m.get("payload", PackedByteArray())})
		_received += 1
		if verbose and (_received <= 5 or _received % 500 == 0):
			_log("recibido #%d de %d (claves %s)" % [_received, from, m.keys()])
	return out


func accept_session(from: int) -> void:
	_steam.acceptSessionWithUser(from)


func close_session(steam_id: int) -> void:
	_log("cerrando sesión con %d" % steam_id)
	_steam.closeSessionWithUser(steam_id)


func _on_lobby_created(connect: int, lobby_id: int) -> void:
	var ok := connect == 1
	_log("sala creada: resultado=%d id=%d" % [connect, lobby_id])
	if ok:
		_steam.setLobbyData(lobby_id, "game", GAME_TAG)
		_steam.setLobbyJoinable(lobby_id, true)
	lobby_created.emit(lobby_id, ok)


func _on_match_list(lobbies: Array) -> void:
	_log("%d salas encontradas" % lobbies.size())
	var entries: Array = []
	for id in lobbies:
		entries.append({
			"id": int(id), "owner": int(_steam.getLobbyOwner(id)), "name": str(_steam.getLobbyData(id, "name")),
			"members": int(_steam.getNumLobbyMembers(id)), "max": int(_steam.getLobbyMemberLimit(id)),
			"version": str(_steam.getLobbyData(id, "version")), "mode": str(_steam.getLobbyData(id, "mode")), "map": str(_steam.getLobbyData(id, "map")),
		})
	lobby_list.emit(entries)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	_log("entrada a la sala %d: respuesta=%d dueño=%d" % [lobby_id, response, int(_steam.getLobbyOwner(lobby_id))])
	lobby_joined.emit(lobby_id, response == 1, int(_steam.getLobbyOwner(lobby_id)))


func _on_chat_update(lobby_id: int, changed_id: int, _making_change: int, chat_state: int) -> void:
	# chat_state bit 1 = entered; 2 = left; 4 = disconnected; 8 = kicked; 16 = banned
	_log("sala %d: miembro %d estado=%d" % [lobby_id, changed_id, chat_state])
	member_changed.emit(lobby_id, changed_id, (chat_state & 1) != 0)
