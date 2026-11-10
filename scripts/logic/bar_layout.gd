class_name BarLayout
extends RefCounted
## How the player arranged the action bar: position on the bar -> canonical ability slot, one order per kit.
## Client only. The server, the wire, the predictor and the cooldowns keep using canonical slots; keybinds belong to the
## position (slot_0 is "the leftmost button"), so moving an ability onto a button also moves it onto that button's key.
## A talent that swaps an ability replaces it on the same canonical slot, so it takes the place of the one it replaced.

const PATH := "user://bar_layouts.json"
const VERSION := 1

static var _shared: BarLayout = null

var path := PATH
var layouts := {}  # kit key (Talents.key) -> Array[int], only for kits the player changed


static func shared() -> BarLayout:
	if _shared == null:
		_shared = BarLayout.new()
	return _shared


## Number of buttons that can be arranged (the trinket keeps its own button).
static func size() -> int:
	return int(GameData.C.SLOT_COUNT)


static func _identity() -> Array:
	return range(size())


## The order as integers, or [] when it is not a permutation of the bar.
static func _sanitized(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY or raw.size() != size():
		return []
	var out: Array = []
	for v in raw:
		if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or float(v) != floorf(float(v)):
			return []
		var slot := int(v)
		if slot < 0 or slot >= size() or out.has(slot):
			return []
		out.append(slot)
	return out


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


func load_file() -> void:
	layouts = {}
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("layouts")) != TYPE_DICTIONARY:
		return
	for key in parsed.layouts:
		var order := _sanitized(parsed.layouts[key])
		if not order.is_empty():
			layouts[str(key)] = order


func save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"_v": VERSION, "layouts": layouts}))


func order(key: String) -> Array:
	return layouts[key].duplicate() if layouts.has(key) else _identity()


func is_custom(key: String) -> bool:
	return layouts.has(key)


## The canonical slot of a bar position. Anything off the bar passes through unchanged.
func slot_at(key: String, pos: int) -> int:
	if pos < 0 or pos >= size() or not layouts.has(key):
		return pos
	return layouts[key][pos]


## The bar position of a canonical slot. Anything off the bar passes through unchanged.
func pos_of(key: String, slot: int) -> int:
	if slot < 0 or slot >= size() or not layouts.has(key):
		return slot
	return layouts[key].find(slot)


## Swaps two buttons. Returns whether anything changed. The caller saves.
func swap(key: String, a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= size() or b >= size():
		return false
	var o := order(key)
	var held: int = o[a]
	o[a] = o[b]
	o[b] = held
	if o == _identity():
		layouts.erase(key)
	else:
		layouts[key] = o
	return true


func reset(key: String) -> void:
	layouts.erase(key)
