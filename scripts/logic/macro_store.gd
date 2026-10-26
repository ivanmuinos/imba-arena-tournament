class_name MacroStore
extends RefCounted
## The player's macro texts (COUNT slots), saved in user://macros.json; their keys live in Keybinds ("macro_1"...).
## The texts use ability names, so one set works for every class (a line naming an ability the current class lacks is
## just skipped).

## Off: macros are hidden everywhere (HUD bar, Macros tab, their keys, the tutorial step) until they are ready.
const ENABLED := false
const PATH := "user://macros.json"
const COUNT := Keybinds.MACROS
const DEFAULT_TEXTS := [
	"#Marcar foco\n/focus",
	"#Oveja al foco\n/cast [@focus] Polimorfia",
	"#Ceguera al foco\n/cast [@focus] Ceguera",
	"#Miedo al foco\n/cast [@focus] Miedo",
	"#Interrumpir al foco\n/cast [@focus] Patada\n/cast [@focus] Zurrar\n/cast [@focus] Contrahechizo",
	"",
]

var path := PATH
var macros: Array = []  # [{text}]


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


func load_file() -> void:
	macros = []
	for i in COUNT:
		macros.append({"text": DEFAULT_TEXTS[i]})
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		return
	for i in mini(parsed.size(), COUNT):
		if typeof(parsed[i]) == TYPE_DICTIONARY:
			macros[i] = {"text": str(parsed[i].get("text", "")).substr(0, 1000)}


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(macros))


func set_text(i: int, text: String) -> void:
	if i >= 0 and i < COUNT:
		macros[i] = {"text": text}


func is_empty(i: int) -> bool:
	return str(macros[i].text).strip_edges() == ""


## Short name for buttons: the macro's # comment, else "Macro N".
func title(i: int) -> String:
	for line in str(macros[i].text).split("\n"):
		var l := line.strip_edges()
		if l.begins_with("#") and l.length() > 1:
			return l.substr(1).strip_edges()
	return "Macro %d" % (i + 1)
