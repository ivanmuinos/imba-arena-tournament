class_name DirectChat
extends RefCounted
## Private chat between friends inside the client, without a server: messages travel player to player over Steam
## (SteamBackend.send_dm / dm_received, a channel of their own) and only while both run the game. History (KEEP per
## friend) and unread counts live on this PC in user://dm_history.json. The backend only delivers messages from friends.

signal changed(friend_id: int)
## A friend's message arrived (for a notification when their chat is not open).
signal received(from: int, text: String)

const PATH := "user://dm_history.json"
const KEEP := 100

## Tests point this at a scratch file.
static var path := PATH

var backend: SteamBackend
var open_id := 0
var _history := {}  # friend id -> [{me, text, t}]
var _unread := {}   # friend id -> count


func _init(p_backend: SteamBackend) -> void:
	backend = p_backend
	_load()
	if backend != null:
		backend.dm_received.connect(receive)


## Only a friend who is in the game can receive (messages are not stored anywhere else).
static func can_chat(friend: Dictionary, app_id: int) -> bool:
	return int(friend.get("state", 0)) != 0 and app_id != 0 and int(friend.get("app", 0)) == app_id


static func clear_file() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func history_of(friend_id: int) -> Array:
	return _history.get(friend_id, [])


func unread_of(friend_id: int) -> int:
	return int(_unread.get(friend_id, 0))


func total_unread() -> int:
	var n := 0
	for k in _unread:
		n += int(_unread[k])
	return n


func send(to: int, text: String) -> bool:
	var clean := Wire.clean_chat({"text": text}).strip_edges()
	if clean == "" or backend == null:
		return false
	backend.send_dm(to, clean)
	_append(to, true, clean)
	return true


func receive(from: int, text: String) -> void:
	var clean := Wire.clean_chat({"text": text}).strip_edges()
	if clean == "":
		return
	if from != open_id:
		_unread[from] = unread_of(from) + 1
	_append(from, false, clean)
	received.emit(from, clean)


func open(friend_id: int) -> void:
	open_id = friend_id
	_unread.erase(friend_id)
	changed.emit(friend_id)


func close() -> void:
	open_id = 0


func _append(friend_id: int, me: bool, text: String) -> void:
	var list: Array = _history.get(friend_id, [])
	list.append({"me": me, "text": text, "t": int(Time.get_unix_time_from_system())})
	_history[friend_id] = list.slice(maxi(0, list.size() - KEEP))
	_save()
	changed.emit(friend_id)


func _save() -> void:
	var out := {}
	for k in _history:
		out[str(k)] = _history[k]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out))


func _load() -> void:
	if not FileAccess.file_exists(path):
		return
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or typeof(j.data) != TYPE_DICTIONARY:
		return
	for k in j.data:
		var list: Array = []
		for m in j.data[k]:
			if typeof(m) == TYPE_DICTIONARY and typeof(m.get("text")) == TYPE_STRING:
				list.append({"me": bool(m.get("me", false)), "text": str(m.text), "t": int(m.get("t", 0))})
		_history[int(k)] = list.slice(maxi(0, list.size() - KEEP))
