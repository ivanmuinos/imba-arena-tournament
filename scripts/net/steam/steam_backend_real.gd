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
const FRIEND_FLAG_IMMEDIATE := 4  # regular friends (not blocked, pending or clan members)
const AVATAR_MEDIUM := 2  # 64 px
const DM_CHANNEL := 9  # private chat, apart from the match traffic on MSG_CHANNEL

## Print every Steam callback and a message count (`--log` / `--steam-log`): the real integration is debugged from these lines.
var verbose := false
var _steam = null
var _ok := false
var _status := "La extensión de Steam no está instalada"
var _pending_lobby := 0
var _sent := 0
var _received := 0
var _hooks: Array = []  # [signal name, callable]: all disconnected in shutdown()
var _boards := {}  # leaderboard name -> handle
var _friends_dirty := false
var _presence_asked := {}  # steam_id -> true once their rich presence was requested


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
	# Persona updates come in bursts (dozens at login): run_callbacks() turns them into one friends_changed.
	_hook("persona_state_change", func(_id: int, _flags: int): _friends_dirty = true)
	_hook("friend_rich_presence_update", func(_id: int, _app: int): _friends_dirty = true)
	_hook("avatar_loaded", _on_avatar_loaded)
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
		if _friends_dirty:
			_friends_dirty = false
			friends_changed.emit()
		_poll_dms()


## Private chat: only from people on our friends list, as {dm: text} dictionaries (no objects decoded).
func _poll_dms() -> void:
	for m in _steam.receiveMessagesOnChannel(DM_CHANNEL, 32):
		var from := int(m.get("identity", m.get("remote_steam_id", 0)))
		if not _steam.hasFriend(from, FRIEND_FLAG_IMMEDIATE):
			_log("mensaje privado de %d ignorado: no es amigo" % from)
			continue
		var d = bytes_to_var(m.get("payload", PackedByteArray()))
		if typeof(d) == TYPE_DICTIONARY and typeof(d.get("dm")) == TYPE_STRING:
			dm_received.emit(from, d.dm)


func send_dm(to: int, text: String) -> void:
	if _ok:
		var r := int(_steam.sendMessageToUser(to, var_to_bytes({"dm": text}), SEND_RELIABLE, DM_CHANNEL))
		_log("mensaje privado a %d -> %d" % [to, r])


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


func persona_of(steam_id: int) -> String:
	return str(_steam.getFriendPersonaName(steam_id)) if _ok else ""


func request_ranked_lobbies(version: String, filters: Dictionary, near_key: String, near_value: int) -> void:
	_steam.addRequestLobbyListStringFilter("game", GAME_TAG, 0)
	_steam.addRequestLobbyListStringFilter("version", version, 0)
	for k in filters:
		_steam.addRequestLobbyListStringFilter(str(k), str(filters[k]), 0)
	if near_key != "":
		_steam.addRequestLobbyListNearValueFilter(near_key, near_value)
	_steam.addRequestLobbyListDistanceFilter(DISTANCE_WORLDWIDE)
	_log("buscando salas ranked %s cerca de %s=%d" % [filters, near_key, near_value])
	_steam.requestLobbyList()


func find_leaderboard(board: String) -> void:
	if not _ok:
		leaderboard_ready.emit(board, false)
		return
	if _boards.has(board):
		leaderboard_ready.emit(board, true)
		return
	_log("buscando tabla %s" % board)
	_steam.findOrCreateLeaderboard(board, 2, 1)  # sort descending, numeric display


func upload_score(board: String, score: int, details: PackedInt32Array) -> void:
	if _boards.has(board):
		_steam.uploadLeaderboardScore(score, false, details, int(_boards[board]))


func request_top(board: String, start: int, end: int) -> void:
	if _boards.has(board):
		_steam.downloadLeaderboardEntries(start, end, 0, int(_boards[board]))  # 0 = global


func request_mine(board: String) -> void:
	if _boards.has(board):
		_steam.downloadLeaderboardEntriesForUsers([my_id()], int(_boards[board]))


func _board_name(handle: int) -> String:
	for k in _boards:
		if int(_boards[k]) == handle:
			return k
	return str(_steam.getLeaderboardName(handle))


func _on_board_found(handle: int, found: int) -> void:
	var board := str(_steam.getLeaderboardName(handle)) if found != 0 else ""
	_log("tabla %s -> handle %d (encontrada=%d)" % [board, handle, found])
	if found != 0 and board != "":
		_boards[board] = handle
	leaderboard_ready.emit(board, found != 0)


func _on_board_scores(_message: String, handle: int, entries: Array) -> void:
	var out: Array = []
	for e in entries:
		out.append({"steam_id": int(e.get("steam_id", 0)), "rank": int(e.get("global_rank", 0)), "score": int(e.get("score", 0)),
			"details": Array(e.get("details", PackedInt32Array()))})
	_log("%d entradas de %s" % [out.size(), _board_name(handle)])
	leaderboard_entries.emit(_board_name(handle), out)


# ---------------------------------------------------------------- friends, presence, overlay (social panel)

func app_id() -> int:
	return int(_steam.getAppID()) if _ok else 0


func friends() -> Array:
	if not _ok:
		return []
	var app := app_id()
	var out: Array = []
	for i in int(_steam.getFriendCount(FRIEND_FLAG_IMMEDIATE)):
		var id := int(_steam.getFriendByIndex(i, FRIEND_FLAG_IMMEDIATE))
		var played: Dictionary = _steam.getFriendGamePlayed(id)
		var f := {"id": id, "name": str(_steam.getFriendPersonaName(id)), "state": int(_steam.getFriendPersonaState(id)),
			"app": int(played.get("id", 0)), "lobby": int(played.get("lobby", 0)), "status": ""}
		if f.app == app:
			if not _presence_asked.has(id):
				_presence_asked[id] = true
				_steam.requestFriendRichPresence(id)  # answered by friend_rich_presence_update
			f.status = str(_steam.getFriendRichPresence(id, "status"))
		out.append(f)
	return out


func request_avatar(steam_id: int) -> void:
	if _ok:
		_steam.getPlayerAvatar(AVATAR_MEDIUM, steam_id)


func _on_avatar_loaded(steam_id: int, px: int, data: PackedByteArray) -> void:
	if px <= 0 or data.size() != px * px * 4:
		return
	var img := Image.create_from_data(px, px, false, Image.FORMAT_RGBA8, data)
	avatar_ready.emit(steam_id, ImageTexture.create_from_image(img))


## Rich presence is only shown to friends while the game runs; setting a key to "" removes it.
func set_presence(values: Dictionary) -> void:
	if not _ok:
		return
	for k in values:
		_steam.setRichPresence(str(k), str(values[k]))
	_log("rich presence: %s" % values)


## The overlay is only injected when Steam itself launched the game; otherwise the Steam client window opens instead
## (chat with the friend, their profile, the friends list) through a steam:// link.
func open_overlay(kind: String, steam_id: int) -> bool:
	if not _ok:
		return false
	if not _steam.isOverlayEnabled():
		var url := Social.steam_url(kind, steam_id)
		_log("superposición no disponible: abriendo el cliente (%s)" % url)
		return url != "" and OS.shell_open(url) == OK
	if kind == "friends":
		_steam.activateGameOverlay("Friends")
	else:
		_steam.activateGameOverlayToUser(kind, steam_id)
	return true
