class_name MacroStore
extends RefCounted
## The player's macros: COUNT slots of {key, text}, saved in user://macros.json. The texts use ability names, so one set
## works for every class (a line naming an ability the current class lacks is just skipped and reported).

const PATH := "user://macros.json"
const COUNT := 6
const DEFAULT_KEYS := ["Ctrl+1", "Ctrl+2", "Ctrl+3", "Ctrl+4", "Ctrl+5", "Ctrl+6"]
const DEFAULT_TEXTS := [
	"#Marcar foco\n/focus",
	"#Oveja al foco\n/cast [@focus] Polimorfia",
	"#Ceguera al foco\n/cast [@focus] Ceguera",
	"#Miedo al foco\n/cast [@focus] Miedo",
	"#Interrumpir al foco\n/cast [@focus] Patada\n/cast [@focus] Zurrar\n/cast [@focus] Contrahechizo",
	"",
]

var path := PATH
var macros: Array = []  # [{key, text}]


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


func load_file() -> void:
	macros = []
	for i in COUNT:
		macros.append({"key": DEFAULT_KEYS[i], "text": DEFAULT_TEXTS[i]})
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		return
	for i in mini(parsed.size(), COUNT):
		if typeof(parsed[i]) == TYPE_DICTIONARY:
			macros[i] = {"key": str(parsed[i].get("key", "")).substr(0, 40), "text": str(parsed[i].get("text", "")).substr(0, 1000)}


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(macros))


func set_macro(i: int, key: String, text: String) -> void:
	if i < 0 or i >= COUNT:
		return
	# one key, one macro: taking a key from another macro unbinds that one
	for j in COUNT:
		if j != i and key != "" and macros[j].key == key:
			macros[j].key = ""
	macros[i] = {"key": key, "text": text}


## Index of the macro bound to `key` ("Ctrl+1"), -1 if none.
func index_for_key(key: String) -> int:
	for i in COUNT:
		if key != "" and macros[i].key == key and str(macros[i].text).strip_edges() != "":
			return i
	return -1
