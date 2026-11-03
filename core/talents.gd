class_name Talents
extends RefCounted
## Talent rows per kit (data/talents.json): each row offers 3 choices, a player picks one per unlocked row.
## A talent is data only: "mul" / "add" change a number of one ability (or of the kit when it names no ability),
## "swap" replaces an ability with one from the class's reserve, on the same slot.
## Picks are an Array with one index per row (-1 = nothing picked).

const PATH := "res://data/talents.json"
## Rows in this version (levels Progress.TALENT_ROWS[0..ROWS-1]).
const ROWS := 2

static var data: Dictionary = {}
static var _cache := {}


static func ensure_loaded() -> void:
	if not data.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	assert(f != null, "Missing data file: " + PATH)
	data = JSON.parse_string(f.get_as_text())


## "mage/fire" for a class with specs, "priest" for one without.
static func key(cls: String, spec := "") -> String:
	var sid := GameData.normalize_spec(cls, spec) if GameData.classes.has(cls) else ""
	return cls + "/" + sid if sid != "" else cls


## The talent rows of a kit ([] when it has none, e.g. a disabled class).
static func rows(cls: String, spec := "") -> Array:
	ensure_loaded()
	GameData.ensure_loaded()
	return data.get(key(cls, spec), [])


static func talent(cls: String, spec: String, row: int, i: int) -> Dictionary:
	var r := rows(cls, spec)
	if row < 0 or row >= r.size() or i < 0 or i >= (r[row] as Array).size():
		return {}
	return r[row][i]


## Any value -> ROWS ints, each a valid choice of its row or -1. Rows past `max_rows` (locked by level) are -1.
static func normalize(cls: String, spec: String, picks, max_rows := ROWS) -> Array:
	var r := rows(cls, spec)
	var out: Array = []
	for row in ROWS:
		var v := -1
		if picks is Array and row < (picks as Array).size() and row < mini(max_rows, r.size()):
			var p = picks[row]
			if (p is int or p is float) and int(p) >= 0 and int(p) < (r[row] as Array).size():
				v = int(p)
		out.append(v)
	return out


## Random choice on every row, for bots.
static func random_picks(cls: String, spec: String, rng: RandomNumberGenerator) -> Array:
	var r := rows(cls, spec)
	var out: Array = []
	for row in ROWS:
		out.append(rng.randi_range(0, (r[row] as Array).size() - 1) if row < r.size() else -1)
	return out


## The kit with the picked talents applied. Never modifies GameData: abilities are copied before they change.
static func apply(kit: Dictionary, cls: String, spec: String, picks) -> Dictionary:
	var p := normalize(cls, spec, picks)
	if not p.any(func(v): return v >= 0):
		return kit
	var out := kit.duplicate()
	var abilities: Array = (kit.abilities as Array).duplicate()
	var effects: Array = []
	for row in p.size():
		if p[row] >= 0:
			effects.append_array(talent(cls, spec, row, p[row]).get("effects", []))
	for e in effects:  # swaps first, so a number change can target the ability swapped in
		if str(e.op) == "swap":
			var slot := _slot_of(abilities, str(e.ability))
			var a := GameData.find_ability(cls, str(e.to), spec)
			if slot >= 0 and not a.is_empty():
				abilities[slot] = a
	for e in effects:
		var op := str(e.op)
		if op != "mul" and op != "add":
			continue
		var field := str(e.field)
		if not e.has("ability"):
			out[field] = _change(op, out.get(field, 0.0), float(e.value))
			continue
		var slot := _slot_of(abilities, str(e.ability))
		if slot < 0:
			continue
		var a: Dictionary = (abilities[slot] as Dictionary).duplicate(true)
		a[field] = _change(op, a.get(field, 0.0), float(e.value))
		abilities[slot] = a
	out.abilities = abilities
	return out


## GameData.kit plus talents, cached (the HUD asks every frame).
static func kit(cls: String, spec: String, picks) -> Dictionary:
	var sid := GameData.normalize_spec(cls, spec)
	var p := normalize(cls, sid, picks)
	var k := "%s|%s|%s" % [cls, sid, p]
	if not _cache.has(k):
		_cache[k] = apply(GameData.kit(cls, sid), cls, sid, p)
	return _cache[k]


## Player-facing text built from the effects (the numbers, never a hand-written description that can drift).
static func describe(cls: String, spec: String, t: Dictionary) -> String:
	var parts: Array = []
	for e in t.get("effects", []):
		var target := _ability_name(cls, spec, str(e.get("ability", "")))
		match str(e.op):
			"swap":
				parts.append("Cambia %s por %s" % [target, _ability_name(cls, spec, str(e.to))])
			"mul":
				var pct := roundi((float(e.value) - 1.0) * 100.0)
				parts.append("%s: %s %s%d%%" % [target, _field_name(str(e.field)), "+" if pct >= 0 else "", pct])
			"add":
				var f := str(e.field)
				var v := float(e.value)
				var txt := ("+%d%%" % roundi(v * 100.0)) if f in ["slowPct", "crit"] else ("+%s" % _num(v))
				if f == "range":
					txt += " m"
				elif f == "shatter":
					txt = "+×%s" % _num(v)
				parts.append(("%s %s" % [_field_name(f), txt]) if target == "" else ("%s: %s %s" % [target, _field_name(f), txt]))
	return ". ".join(parts)


## Icon of a talent: its own, else the ability it swaps in or changes.
static func icon(cls: String, spec: String, t: Dictionary) -> String:
	if t.has("icon"):
		return str(GameData.find_ability(cls, str(t.icon), spec).get("icon", t.icon))
	for e in t.get("effects", []):
		var id := str(e.get("to", e.get("ability", "")))
		var a := GameData.find_ability(cls, id, spec)
		if not a.is_empty():
			return str(a.icon)
	return ""


static func _slot_of(abilities: Array, id: String) -> int:
	for i in abilities.size():
		if str(abilities[i].id) == id:
			return i
	return -1


static func _change(op: String, cur, v: float) -> float:
	return float(cur) * v if op == "mul" else float(cur) + v


static func _ability_name(cls: String, spec: String, id: String) -> String:
	if id == "":
		return ""
	return str(GameData.find_ability(cls, id, spec).get("name", id))


static func _field_name(f: String) -> String:
	match f:
		"dmg": return "daño"
		"heal": return "curación"
		"cd": return "recarga"
		"cast": return "tiempo de lanzamiento"
		"burnDps": return "quemadura"
		"dotDps": return "daño por segundo"
		"slowPct": return "ralentización"
		"range": return "alcance"
		"shatter": return "astillado"
		"crit": return "Probabilidad de crítico"
	return f


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v).replace(".", ",")
