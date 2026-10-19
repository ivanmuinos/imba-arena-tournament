class_name Keybinds
extends RefCounted
## Every rebindable action and its key, like WoW's key bindings (or Bartender's keybinding mode). Saved in
## user://keybinds.json. Keys are Godot key names with modifiers ("Q", "Shift", "Ctrl+1"); one key, one action: binding a
## key takes it away from whatever had it. Movement (WASD), Esc and the mouse stay fixed.

const PATH := "user://keybinds.json"
const MACROS := 6

## [action, label shown in Controles, default key]
const ACTIONS := [
	["slot_0", "Habilidad 1 (básica)", "1"], ["slot_1", "Habilidad 2", "2"], ["slot_2", "Habilidad 3", "Q"],
	["slot_3", "Habilidad 4", "E"], ["slot_4", "Habilidad 5", "Shift"], ["slot_5", "Habilidad 6", "F"],
	["slot_6", "Definitiva", "R"], ["trinket", "Abalorio PvP", "T"], ["jump", "Saltar", "Space"],
	["target_next", "Siguiente objetivo", "Tab"], ["ally_1", "Aliado 1", "F1"], ["ally_2", "Aliado 2", "F2"],
	["ally_3", "Aliado 3", "F3"], ["mute", "Silenciar", "M"], ["bind_mode", "Modo teclas (reasignar en partida)", "Ctrl+K"],
	["macro_1", "Macro 1", "Ctrl+1"], ["macro_2", "Macro 2", "Ctrl+2"], ["macro_3", "Macro 3", "Ctrl+3"],
	["macro_4", "Macro 4", "Ctrl+4"], ["macro_5", "Macro 5", "Ctrl+5"], ["macro_6", "Macro 6", "Ctrl+6"],
]
const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

static var _shared: Keybinds = null

var path := PATH
var keys := {}  # action -> key name ("" = unbound)


static func shared() -> Keybinds:
	if _shared == null:
		_shared = Keybinds.new()
	return _shared


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


static func defaults() -> Dictionary:
	var d := {}
	for a in ACTIONS:
		d[a[0]] = a[2]
	return d


func load_file() -> void:
	keys = defaults()
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for a in keys:
		if parsed.has(a):
			keys[a] = str(parsed[a]).substr(0, 40)


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(keys))


func reset() -> void:
	keys = defaults()


## Binds `key` to `action`; returns the action that lost the key ("" if none).
func bind(action: String, key: String) -> String:
	if not keys.has(action):
		return ""
	var lost := ""
	if key != "":
		for a in keys:
			if a != action and keys[a] == key:
				keys[a] = ""
				lost = a
	keys[action] = key
	return lost


func key_of(action: String) -> String:
	return str(keys.get(action, ""))


## What the key shows on buttons and in the tutorial ("—" when unbound).
func label(action: String) -> String:
	var k := key_of(action)
	return "—" if k == "" else k.replace("Space", "Espacio")


func action_for(key: String) -> String:
	if key == "":
		return ""
	for a in keys:
		if keys[a] == key:
			return a
	return ""


func slot_label(slot: int) -> String:
	return label("slot_%d" % slot)


## Godot's name of a pressed key with its modifiers ("Ctrl+1"); a lone modifier is just its own name ("Shift").
static func event_name(e: InputEventKey) -> String:
	if e.keycode in MODIFIERS:
		return OS.get_keycode_string(e.keycode)
	return OS.get_keycode_string(e.get_keycode_with_modifiers())


static func action_label(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action
