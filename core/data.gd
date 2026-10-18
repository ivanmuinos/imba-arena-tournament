class_name GameData
extends RefCounted
## Game data exported from the web prototype (classes, abilities, power-ups, tuning).

static var classes: Dictionary = {}
static var powers: Dictionary = {}
static var maps: Dictionary = {}
## Tuning constants (C.SIM_HZ, C.PLAYER_R, ...).
static var C: Dictionary = {}


## Maximum health of a roster entry: training dummies carry their own huge value, everyone else the class's.
static func entry_max_hp(entry: Dictionary) -> float:
	ensure_loaded()
	if entry.has("hp"):
		return float(entry.hp)
	return float(kit(str(entry.cls), str(entry.get("spec", ""))).hp)


static func ensure_loaded() -> void:
	if not classes.is_empty():
		return
	classes = _read("res://data/classes.json")
	powers = _read("res://data/powers.json")
	maps = _read("res://data/maps.json")
	C = _read("res://data/constants.json")


## Spec ids of a class ([] when it has none). Specializations override the whole 7-slot kit (data/classes.json -> specs).
static func spec_ids(cls: String) -> Array:
	ensure_loaded()
	var c: Dictionary = classes.get(cls, {})
	return (c.specs as Dictionary).keys() if c.has("specs") else []


static func default_spec(cls: String) -> String:
	ensure_loaded()
	return str(classes.get(cls, {}).get("default_spec", ""))


## Any value -> a valid spec id for the class ("" when the class has no specializations).
static func normalize_spec(cls: String, spec: String) -> String:
	var ids := spec_ids(cls)
	if ids.is_empty():
		return ""
	return spec if ids.has(spec) else default_spec(cls)


## The 7 abilities a unit of this class/spec uses.
static func abilities(cls: String, spec := "") -> Array:
	ensure_loaded()
	var c: Dictionary = classes[cls]
	if spec != "" and c.has("specs") and c.specs.has(spec):
		var out: Array = []
		var kit: Dictionary = c.specs[spec].abilities
		for i in c.abilities.size():
			out.append(kit[str(i)] if kit.has(str(i)) else c.abilities[i])
		return out
	return c.abilities


## Class dictionary with the spec's abilities resolved (plus spec_id / spec_name / spec_icon / spec_color).
static func kit(cls: String, spec := "") -> Dictionary:
	ensure_loaded()
	var k: Dictionary = (classes[cls] as Dictionary).duplicate()
	k["abilities"] = abilities(cls, spec)
	if spec != "" and classes[cls].has("specs") and classes[cls].specs.has(spec):
		var s: Dictionary = classes[cls].specs[spec]
		k["spec_id"] = spec
		k["spec_name"] = s.name
		k["spec_icon"] = s.icon
		k["spec_color"] = s.color
		k["stats"] = s.stats
		k["tagline"] = s.desc
		for key in ["hp", "armor", "crit"]:  # a specialization may be sturdier, tougher or crit-ier than its class
			if s.has(key):
				k[key] = s[key]
	return k


static func ability(cls: String, slot: int, spec := "") -> Dictionary:
	return abilities(cls, spec)[slot]


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Missing data file: " + path)
	return JSON.parse_string(f.get_as_text())
