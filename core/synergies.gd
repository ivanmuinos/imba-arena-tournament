class_name Synergies
extends RefCounted
## Team bonuses (data/synergies.json): a pair of classes on the same team turns on its effects for the whole team.
## ArenaMatch reads the merged effects; the menu and the HUD only show the text.

const PATH := "res://data/synergies.json"

static var data: Dictionary = {}


static func ensure_loaded() -> void:
	if not data.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	assert(f != null, "Missing data file: " + PATH)
	data = JSON.parse_string(f.get_as_text())


static func all() -> Array:
	ensure_loaded()
	return data.pairs


## The pairs this class belongs to.
static func of_class(cls: String) -> Array:
	return all().filter(func(p): return cls in p.classes)


## The other class of a pair.
static func partner(pair: Dictionary, cls: String) -> String:
	return str(pair.classes[1] if pair.classes[0] == cls else pair.classes[0])


## The pairs turned on by these classes (one team's).
static func active(classes: Array) -> Array:
	return all().filter(func(p): return p.classes.all(func(c): return c in classes))


## Effect field -> value for a team made of these classes.
static func effects(classes: Array) -> Dictionary:
	var out := {}
	for p in active(classes):
		out.merge(p.effects)
	return out


## Line for the countdown screen ("" when the team has no synergy): names only, the Champions screen explains them.
static func banner(classes: Array) -> String:
	var names := active(classes).map(func(p): return str(p.name))
	return "" if names.is_empty() else "\nSinergia: " + " · ".join(names)
