class_name SteamBackend
extends RefCounted
## What the game needs from Steam (lobbies + peer-to-peer messages), as an interface. SteamBackendReal talks to the
## GodotSteam GDExtension; tests use a fake. Steam is optional: when `available()` is false nothing here is used.

signal lobby_created(lobby_id: int, ok: bool)
## entries: [{id, owner, name, members, max, version, mode, map}]
signal lobby_list(entries: Array)
signal lobby_joined(lobby_id: int, ok: bool, owner: int)
signal member_changed(lobby_id: int, steam_id: int, joined: bool)
## The player accepted an invite / "join game" in the Steam overlay or friends list.
signal join_requested(lobby_id: int)
signal session_failed(steam_id: int)


func available() -> bool:
	return false


## Short explanation for the menu when not available.
func status_text() -> String:
	return "Steam no disponible"


func persona_name() -> String:
	return ""


func my_id() -> int:
	return 0


func run_callbacks() -> void:
	pass


## Called once when the game exits: release Steam before the engine unloads the extension.
func shutdown() -> void:
	pass


func create_lobby(_friends_only: bool, _max_members: int) -> void:
	pass


## Lobbies of this game with the same version.
func request_lobby_list(_version: String) -> void:
	pass


func join_lobby(_lobby_id: int) -> void:
	pass


func leave_lobby(_lobby_id: int) -> void:
	pass


func set_lobby_data(_lobby_id: int, _key: String, _value: String) -> void:
	pass


func lobby_owner(_lobby_id: int) -> int:
	return 0


func lobby_member_ids(_lobby_id: int) -> Array:
	return []


func invite_dialog(_lobby_id: int) -> void:
	pass


func send(_to: int, _data: PackedByteArray, _reliable: bool) -> void:
	pass


## [{from: steam_id, data: PackedByteArray}]
func poll_messages() -> Array:
	return []


func accept_session(_from: int) -> void:
	pass


func close_session(_steam_id: int) -> void:
	pass
