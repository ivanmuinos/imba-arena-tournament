class_name Keybinds
extends RefCounted
## Every rebindable action and its key, like WoW's key bindings (or Bartender's keybinding mode). Saved in
## user://keybinds.json. Keys are Godot key names with modifiers ("Q", "Shift", "Ctrl+1"); one key, one action: binding a
## key takes it away from whatever had it. Movement (WASD, Q/E strafe), Esc and the mouse are in ControlBindings.

const PATH := "user://keybinds.json"
const MACROS := 6
const VERSION := 4
## Version 1 bar (1, 2, Q, E, Shift, F, R): a saved slot still on its old default moves to the number keys, so Q/E strafe.
const V1_SLOTS := {"slot_2": "Q", "slot_3": "E", "slot_4": "Shift"}
## Version 2 bar had 7 slots (1-7, ultimate on slot_6): the kits now have 5 (basic + 3 + ultimate on slot_4). Slot 4 used
## to be a normal ability, so it goes back to its new default; a custom ultimate key carries over to the new ultimate slot.
const V2_ULT_DEFAULT := "7"

## [action, label shown in Controles, default key]
const ACTIONS := [
	["slot_0", "Habilidad 1 (básica)", "1"], ["slot_1", "Habilidad 2", "2"], ["slot_2", "Habilidad 3", "3"],
	["slot_3", "Habilidad 4", "4"], ["slot_4", "Definitiva", "R"], ["trinket", "Abalorio PvP", "T"], ["jump", "Saltar", "Space"],
	["target_next", "Siguiente objetivo", "Tab"], ["self", "Seleccionarte a vos", "F1"], ["ally_1", "Aliado 1", "F2"],
	["ally_2", "Aliado 2", "F3"], ["mute", "Silenciar", "M"], ["bind_mode", "Modo teclas (reasignar en partida)", "Ctrl+K"],
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
	var v := int(parsed.get("_v", 1))
	if v < 2:
		for a in V1_SLOTS:
			if keys[a] == V1_SLOTS[a] and action_for(defaults()[a]) == "":
				keys[a] = defaults()[a]
	if v < 3:
		var ult := str(parsed.get("slot_6", V2_ULT_DEFAULT)).substr(0, 40)
		keys.slot_4 = ""
		var want: String = defaults().slot_4 if ult == V2_ULT_DEFAULT or ult == "" else ult
		if action_for(want) == "":
			keys.slot_4 = want
		# the trinket could end up with no key (taken by another action); it is too important to stay that way
		if keys.trinket == "" and action_for(defaults().trinket) == "":
			keys.trinket = defaults().trinket
	if v < 4:
		# F1 used to pick the first of your team (often you, not always); now it is always you and F2 / F3 your allies.
		# Keys still on the old defaults move to the new layout; custom ones stay where they were.
		var old_keys := {"ally_1": "F1", "ally_2": "F2", "ally_3": "F3"}
		var moved := {}
		for a in old_keys:
			if str(parsed.get(a, old_keys[a])) == old_keys[a]:
				moved[a] = true
		if moved.has("ally_1") and moved.has("ally_2"):
			keys.ally_1 = ""
			keys.ally_2 = ""
			for a in ["self", "ally_1", "ally_2"]:
				if action_for(defaults()[a]) == "":
					keys[a] = defaults()[a]


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		var out := keys.duplicate()
		out["_v"] = VERSION
		f.store_string(JSON.stringify(out))


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
