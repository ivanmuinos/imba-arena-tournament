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
## Leaderboards (ranked): found/created, entries downloaded [{steam_id, rank, score, details}], own score uploaded.
signal leaderboard_ready(board: String, ok: bool)
signal leaderboard_entries(board: String, entries: Array)
signal leaderboard_uploaded(board: String, ok: bool)


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


## Steam name of any player (empty when unknown).
func persona_of(_steam_id: int) -> String:
	return ""


## Ranked lobbies: lobbies of this game and version with lobby data `filters` ({key: value}), closest `near` value first.
func request_ranked_lobbies(_version: String, _filters: Dictionary, _near_key: String, _near_value: int) -> void:
	pass


## Finds (or creates) a leaderboard; leaderboard_ready says when it can be used.
func find_leaderboard(_board: String) -> void:
	pass


## Replaces our score (not "keep best": a rating goes down too). `details`: extra ints (games, wins).
func upload_score(_board: String, _score: int, _details: PackedInt32Array) -> void:
	pass


## Global top entries [start, end] (1-based ranks).
func request_top(_board: String, _start: int, _end: int) -> void:
	pass


## Just our own entry.
func request_mine(_board: String) -> void:
	pass
