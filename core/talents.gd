class_name Talents
extends RefCounted
## Talent rows per kit (data/talents.json): each row offers 3 choices, a player picks one per unlocked row.
## A talent is data only: "mul" / "add" change a number of one ability (or of the kit when it names no ability),
## "set" gives an ability a mechanic field that ArenaMatch reads (bounce, nth, leech, killReset...; "also" sets its
## companion fields), "swap" replaces an ability with one from the class's reserve, on the same slot.
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
## Every ability a talent touches gets `talent: {id, name, kind, text}` (TalentMark draws the kind on its icon,
## tooltips print the text). A swap marks "swap"; a kit-wide change marks the ability named by the talent's "icon".
static func apply(kit: Dictionary, cls: String, spec: String, picks) -> Dictionary:
	var p := normalize(cls, spec, picks)
	if not p.any(func(v): return v >= 0):
		return kit
	var out := kit.duplicate()
	var abilities: Array = (kit.abilities as Array).duplicate()
	var chosen: Array = []  # [talent, effect]
	for row in p.size():
		if p[row] >= 0:
			var t := talent(cls, spec, row, p[row])
			for e in t.get("effects", []):
				chosen.append([t, e])
	for te in chosen:  # swaps first, so a number change can target the ability swapped in
		var e: Dictionary = te[1]
		if str(e.op) == "swap":
			var slot := _slot_of(abilities, str(e.ability))
			var a := GameData.find_ability(cls, str(e.to), spec)
			if slot >= 0 and not a.is_empty():
				abilities[slot] = _marked(a, cls, spec, te[0], "swap")
	for te in chosen:
		var t: Dictionary = te[0]
		var e: Dictionary = te[1]
		var op := str(e.op)
		if op == "set":
			var ss := _slot_of(abilities, str(e.ability))
			if ss < 0:
				continue
			var sa: Dictionary = (abilities[ss] as Dictionary).duplicate(true)
			sa[str(e.field)] = e.value
			for k in e.get("also", {}):
				sa[k] = e.also[k]
			abilities[ss] = _marked(sa, cls, spec, t, _kind(str(e.field)))
			continue
		if op != "mul" and op != "add":
			continue
		var field := str(e.field)
		if not e.has("ability"):
			out[field] = _change(op, out.get(field, 0.0), float(e.value))
			var shown := _slot_of(abilities, str(t.get("icon", "")))
			if shown >= 0:
				abilities[shown] = _marked(abilities[shown], cls, spec, t, _kind(field))
			continue
		var slot := _slot_of(abilities, str(e.ability))
		if slot < 0:
			continue
		var a: Dictionary = (abilities[slot] as Dictionary).duplicate(true)
		a[field] = _change(op, a.get(field, 0.0), float(e.value))
		abilities[slot] = _marked(a, cls, spec, t, _kind(field))
	out.abilities = abilities
	return out


## Mark kind of a talent: what its seal shows (see TalentMark).
static func mark_kind(t: Dictionary) -> String:
	for e in t.get("effects", []):
		if str(e.op) == "swap":
			return "swap"
	var effects: Array = t.get("effects", [])
	return _kind(str(effects[0].field)) if not effects.is_empty() else ""


static func _kind(field: String) -> String:
	match field:
		"dmg", "ultGain", "healCut", "block": return "dmg"
		"heal", "leech", "allyHeal", "drainHeal", "hotHps": return "heal"
		"cd", "stillCd", "cdOf", "killReset", "charges": return "cd"
		"cast", "instantAfterCrits", "noPushback", "curseHaste", "castMove": return "cast"
		"range": return "range"
		"burnDps", "dotDps", "poison", "curseMark", "spread": return "burn"
		"slowPct", "shatter", "slowStack": return "frost"
		"crit", "vsSlowed", "behind", "critVsSlowed": return "crit"
		"bounce": return "bounce"
		"nth": return "nth"
	return "dmg"


## A copy of the ability carrying the talent that changed it (a swap keeps its mark when numbers change it later).
static func _marked(a: Dictionary, cls: String, spec: String, t: Dictionary, kind: String) -> Dictionary:
	var m := a.duplicate(true)
	if str(m.get("talent", {}).get("id", "")) == str(t.id):
		return m
	m["talent"] = {"id": t.id, "name": t.name, "kind": kind, "text": describe(cls, spec, t)}
	return m


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
			"set":
				parts.append(_mechanic(cls, spec, target, e))
			"add":
				var f := str(e.field)
				var v := float(e.value)
				var txt := ("+%d%%" % roundi(v * 100.0)) if f in ["slowPct", "crit", "block"] else ("+%s" % _num(v))
				if f == "cast":
					txt = "%s%s s" % ["+" if v >= 0 else "−", _num(absf(v) / 1000.0)]
				elif f == "range":
					txt += " m"
				elif f == "shatter":
					txt = "+×%s" % _num(v)
				parts.append(("%s %s" % [_field_name(f), txt]) if target == "" else ("%s: %s %s" % [target, _field_name(f), txt]))
	return ". ".join(parts)


## Text of a "set" mechanic.
static func _mechanic(cls: String, spec: String, target: String, e: Dictionary) -> String:
	var v = e.value
	var also: Dictionary = e.get("also", {})
	var pct := func(x) -> int: return roundi(float(x) * 100.0)
	match str(e.field):
		"bounce": return "%s rebota a un 2.º enemigo cercano con el %d%% del daño" % [target, pct.call(v)]
		"nth":
			match str(also.get("nthEffect", "crit")):
				"freeze": return "%s: 1 de cada %d congela al objetivo %s s" % [target, int(v), _num(float(also.get("nthMs", 1000)) / 1000.0)]
				"pierce": return "%s: 1 de cada %d atraviesa a los enemigos" % [target, int(v)]
			return "%s: 1 de cada %d es crítico seguro" % [target, int(v)]
		"instantAfterCrits": return "%s instantánea después de %d críticos" % [target, int(v)]
		"noPushback": return "%s no se retrasa cuando recibís daño" % target
		"curseHaste": return "%s se lanza %d%% más rápido contra un objetivo con tu maldición" % [target, pct.call(v)]
		"castMove": return "%s se puede lanzar mientras te movés" % target
		"leech": return "%s te cura el %d%% de su daño" % [target, pct.call(v)]
		"allyHeal": return "%s cura al aliado más herido el %d%% de su daño" % [target, pct.call(v)]
		"drainHeal": return "%s cura %d%% más" % [target, roundi((float(v) - 1.0) * 100.0)]
		"hotHps": return "%s deja una curación de %d en %s s" % [target, roundi(float(v) * float(also.get("hotMs", 6000)) / 1000.0), _num(float(also.get("hotMs", 6000)) / 1000.0)]
		"curseMark": return "%s marca al objetivo: tus maldiciones le hacen +%d%% de daño por %s s" % [target, pct.call(v), _num(float(also.get("markMs", 6000)) / 1000.0)]
		"spread": return "%s también maldice a un enemigo cercano" % target
		"poison": return "%s envenena: %s de daño por segundo durante %s s" % [target, _num(float(v)), _num(float(also.get("poisonMs", 6000)) / 1000.0)]
		"slowStack": return "%s ralentiza %d%% por golpe (hasta %d%%)" % [target, pct.call(v), pct.call(float(v) * float(also.get("slowStacks", 3)))]
		"stillCd": return "%s %d%% más rápido si estás quieto" % [target, pct.call(v)]
		"critVsSlowed": return "%s es crítico seguro contra enemigos ralentizados o enraizados" % target
		"vsSlowed": return "%s +%d%% de daño contra enemigos ralentizados o enraizados" % [target, pct.call(v)]
		"behind": return "%s +%d%% de daño por la espalda" % [target, pct.call(v)]
		"ultGain": return "%s carga la definitiva %d%% más" % [target, roundi((float(v) - 1.0) * 100.0)]
		"healCut": return "%s reduce la curación del objetivo %d%% (en vez de 50%%)" % [target, pct.call(v)]
		"killReset":
			return ("%s se reinicia si mata" % target) if str(v) == str(e.ability) else ("Si %s mata, se reinicia %s" % [target, _ability_name(cls, spec, str(v))])
		"cdOf":
			var ids: Array = v if v is Array else [v]
			return "%s baja %s s la recarga de %s" % [target, _num(float(also.get("cdBy", 1000)) / 1000.0), _ability_name(cls, spec, str(ids[0]))]
		"charges": return "%s tiene %d cargas" % [target, int(v)]
	return "%s: %s" % [target, str(e.field)]


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
		"block": return "Probabilidad de bloqueo"
	return f


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v).replace(".", ",")
