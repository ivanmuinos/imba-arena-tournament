class_name SteamLobbies
extends RefCounted
## Lobby state machine for the menu: create (friends only / public), list, join (list or overlay invite).

signal hosted(lobby_id: int)
signal list_changed(entries: Array)
signal joined(lobby_id: int, owner: int)
signal failed(text: String)

const MAX_MEMBERS := 6

var backend: SteamBackend
var state := "idle"  # idle | hosting | joining | in_lobby
var lobby_id := 0
var _hosting := false


func _init(p_backend: SteamBackend) -> void:
	backend = p_backend
	backend.lobby_created.connect(_on_created)
	backend.lobby_list.connect(_on_list)
	backend.lobby_joined.connect(_on_joined)
	backend.join_requested.connect(_on_join_requested)


## settings: {mode, map, name} shown in the public list.
func host(friends_only: bool, settings: Dictionary) -> void:
	if state != "idle":
		return
	state = "hosting"
	_hosting = true
	_settings = settings
	backend.create_lobby(friends_only, MAX_MEMBERS)


var _settings := {}


## The lobby of an invite accepted while the game was closed: Steam launches it with `+connect_lobby <id>`. 0 if none.
static func lobby_from_cmdline(list: PackedStringArray) -> int:
	var i := list.find("+connect_lobby")
	if i < 0 or i + 1 >= list.size() or not list[i + 1].is_valid_int():
		return 0
	return maxi(int(list[i + 1]), 0)


func refresh() -> void:
	backend.request_lobby_list(GameServer.game_version())


func join(id: int) -> void:
	if state != "idle":
		failed.emit("Ya estás en una sala")
		return
	state = "joining"
	_hosting = false
	backend.join_lobby(id)


func leave() -> void:
	if lobby_id != 0:
		backend.leave_lobby(lobby_id)
	state = "idle"
	lobby_id = 0
	_hosting = false


## Keeps the advertised settings fresh (the host changes mode/map in the lobby).
func update_settings(settings: Dictionary) -> void:
	_settings = settings
	if lobby_id != 0 and _hosting:
		_publish()


func _publish() -> void:
	backend.set_lobby_data(lobby_id, "version", GameServer.game_version())
	backend.set_lobby_data(lobby_id, "name", str(_settings.get("name", backend.persona_name())))
	backend.set_lobby_data(lobby_id, "mode", str(_settings.get("mode", 2)))
	backend.set_lobby_data(lobby_id, "map", str(_settings.get("map", "random")))


func _on_created(id: int, ok: bool) -> void:
	if state != "hosting":
		return
	if not ok:
		state = "idle"
		failed.emit("No se pudo crear la sala de Steam")
		return
	lobby_id = id
	state = "in_lobby"
	_publish()
	hosted.emit(id)


func _on_list(entries: Array) -> void:
	var v := GameServer.game_version()
	var ok: Array = entries.filter(func(e): return e.version == v and e.members < e.max)
	list_changed.emit(ok)


func _on_joined(id: int, ok: bool, owner: int) -> void:
	if state != "joining":
		return
	if not ok:
		state = "idle"
		failed.emit("No se pudo entrar a la sala (¿está llena o ya cerró?)")
		return
	lobby_id = id
	state = "in_lobby"
	joined.emit(id, owner)


func _on_join_requested(id: int) -> void:
	if state == "idle":
		join(id)
	else:
		failed.emit("Terminá lo que estás haciendo antes de aceptar una invitación")
