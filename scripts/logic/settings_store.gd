class_name SettingsStore
extends RefCounted
## Everything the player can configure, validated and persisted in user://settings.cfg.
## set_value() clamps/sanitises, so bad files and bad input never produce invalid state.

const PATH := "user://settings.cfg"
const SENS_MIN := 0.3
const SENS_MAX := 2.5
const BAR_MIN := 0.7  # size of the in-match ability bar
const BAR_MAX := 1.5
const GFX := ["auto", "alta", "media", "baja"]

static var _shared: SettingsStore = null
## Where settings live (tests point this at a scratch file).
static var path := PATH

var values := {
	"bindings": {}, "swap_sticks": false,
	"name": "", "cls": "mage", "spec": "fire", "specs": {}, "mode": 2, "map": "random", "diff": "normal", "pref": "any",
	"addr": "127.0.0.1", "port": 7777, "gfx": "auto", "fullscreen": false,
	"tutorial_seen": false, "master": 0.8, "music": 0.5, "sfx": 0.9, "sens": 1.0, "invert": false, "steam_friends": true,
	"companions": true, "news_seen": [], "bar_scale": 1.0,
}


## The one live instance (loaded from disk on first use).
static func shared() -> SettingsStore:
	if _shared == null:
		_shared = SettingsStore.new()
		_shared.load()
	return _shared


static func clear_shared() -> void:
	_shared = null


func get_value(key: String) -> Variant:
	return values[key]


## Returns the value actually stored (after validation).
func set_value(key: String, v: Variant) -> Variant:
	GameData.ensure_loaded()
	match key:
		"name":
			values.name = MatchConfig.sanitize_name(str(v)) if str(v).strip_edges() != "" else ""
		"cls":
			values.cls = str(v) if GameData.playable(str(v)) else "mage"
			values.spec = GameData.normalize_spec(values.cls, str(values.specs.get(values.cls, "")))
		"spec":
			values.spec = GameData.normalize_spec(str(values.cls), str(v))
			if values.spec != "":
				values.specs[values.cls] = values.spec   # each class remembers its own choice
		"specs":
			var clean := {}
			if typeof(v) == TYPE_DICTIONARY:
				for k in v:
					var ns := GameData.normalize_spec(str(k), str(v[k]))
					if ns != "":
						clean[str(k)] = ns
			values.specs = clean
			values.spec = GameData.normalize_spec(values.cls, str(values.specs.get(values.cls, "")))
		"mode":
			values.mode = 3 if (typeof(v) in [TYPE_INT, TYPE_FLOAT] and int(v) == 3) else 2
		"map":
			var m := str(v)
			values.map = m if (m == "random" or GameMap.IDS.has(m)) else "random"
		"diff":
			values.diff = str(v) if MatchConfig.DIFFS.has(str(v)) else "normal"
		"pref":
			values.pref = str(v) if str(v) in ["any", "red", "blue"] else "any"
		"addr":
			values.addr = str(v).strip_edges() if valid_address(str(v).strip_edges()) else "127.0.0.1"
		"port":
			var p := parse_port(str(v))
			values.port = p if p > 0 else 7777
		"gfx":
			values.gfx = str(v) if GFX.has(str(v)) else "auto"
		"bindings":
			values.bindings = ControlBindings.sanitize(v)
		"fullscreen", "invert", "steam_friends", "tutorial_seen", "swap_sticks":
			values[key] = bool(v) if typeof(v) == TYPE_BOOL else false
		"companions":
			values.companions = bool(v) if typeof(v) == TYPE_BOOL else true
		"news_seen":
			var ids: Array = []
			if typeof(v) == TYPE_ARRAY:
				for id in v:
					if not ids.has(str(id)):
						ids.append(str(id))
			values.news_seen = ids.slice(maxi(0, ids.size() - NewsFeed.SEEN_KEEP))
		"master", "music", "sfx":
			values[key] = clampf(float(v), 0.0, 1.0) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else values[key]
		"sens":
			values.sens = clampf(float(v), SENS_MIN, SENS_MAX) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 1.0
		"bar_scale":
			values.bar_scale = clampf(float(v), BAR_MIN, BAR_MAX) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 1.0
	return values[key]


func save(file := "") -> bool:
	var c := ConfigFile.new()
	for k in values:
		c.set_value("menu", k, values[k])
	return c.save(file if file != "" else path) == OK


func load(file := "") -> bool:
	var c := ConfigFile.new()
	if c.load(file if file != "" else path) != OK:
		return false
	for k in values.keys():
		if c.has_section_key("menu", k):
			var raw = c.get_value("menu", k)
			var before = values[k]
			set_value(k, raw)
			# A value of the wrong type keeps its default instead of being coerced.
			if typeof(raw) != typeof(before) and not (typeof(raw) in [TYPE_INT, TYPE_FLOAT] and typeof(before) in [TYPE_INT, TYPE_FLOAT]):
				values[k] = before
	return true


## Menu choices as a match config (see MatchConfig.normalize).
func to_cfg() -> Dictionary:
	return MatchConfig.normalize({"name": values.name, "cls": values.cls, "spec": values.spec, "mode": values.mode, "diff": values.diff, "map": values.map, "pref": values.pref})


static func parse_port(text: String) -> int:
	var t := text.strip_edges()
	if t == "" or not t.is_valid_int():
		return -1
	var p := t.to_int()
	return p if p > 0 and p < 65536 else -1


## IPv4 or a plausible host name; never anything with spaces or shell characters.
static func valid_address(a: String) -> bool:
	if a == "" or a.length() > 253:
		return false
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9]([A-Za-z0-9.\\-]*[A-Za-z0-9])?$")
	return re.search(a) != null


## "host" or "host:port" -> {addr, port (-1 when absent)}.
static func split_address(text: String) -> Dictionary:
	var parts := text.strip_edges().split(":")
	return {"addr": parts[0], "port": parse_port(parts[1]) if parts.size() > 1 else -1}
