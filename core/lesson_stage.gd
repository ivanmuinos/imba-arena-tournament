class_name LessonStage
extends RefCounted
## Runs one scenario on top of an ArenaMatch: places everyone, watches the plates and fires the declared triggers. Pure simulation
## (no nodes), so lessons can be played headless. See LessonScenarios for the scenario format.

var scenario: Dictionary
## This lesson keeps the dampening a round would have (a practice match has none).
var damp := false
var pressed := 0  # plates stepped on
var active := 0   # plates that count right now
## Stopped by a failed attempt: triggers no longer fire.
var halted := false
var _fired := {}  # trigger index -> true
var _by_key := {}  # unit key -> ArenaUnit
var _actors := {}  # unit key -> LessonActor
var _hidden_ms := {}  # watch index -> how long the player has been out of that unit's sight
var _last := -1.0


func _init(p_scenario: Dictionary) -> void:
	scenario = p_scenario
	damp = bool(scenario.get("damp", false))


func setup(m: ArenaMatch, now: float) -> void:
	var start: Array = scenario.get("start", [0.0, 0.0])
	m.map.spawns = {"red": [{"x": float(start[0]), "z": float(start[1])}], "blue": m.map.spawns.blue}
	for u in m.units:
		if u.peer != 0:
			u.x = float(start[0])
			u.z = float(start[1])
			u.rot = PI
		elif u.lesson_key != "":
			_by_key[u.lesson_key] = u
			u.x = u.home.x
			u.z = u.home.y
	for spec in scenario.get("units", []):
		if str(spec.kind) == "actor":
			_actors[str(spec.key)] = LessonActor.new(_by_key[str(spec.key)], spec.get("script", []))
		if bool(spec.get("dormant", false)):
			var u: ArenaUnit = _by_key[str(spec.key)]
			u.dormant = true
			u.alive = false
	m.map.set_doors(int(scenario.get("doors", 0)))
	for p in scenario.get("active", []):
		active |= 1 << int(p)
	_fire(m, "start", now)


func step(m: ArenaMatch, now: float) -> void:
	if halted:
		return
	var player := _player(m)
	var dt := 0.0 if _last < 0.0 else now - _last
	_last = now
	for key in _actors:
		(_actors[key] as LessonActor).tick(m, player, now)
	_watch(m, player, now, dt)
	if bool(scenario.get("fresh_dr", false)):
		for key in _by_key:
			(_by_key[key] as ArenaUnit).dr.clear()
	for u in m.units:
		if u.peer == 0 or not u.alive:
			continue
		var plate := m.map.plate_at(u.x, u.z)
		if plate >= 0 and active & (1 << plate) != 0 and pressed & (1 << plate) == 0:
			pressed |= 1 << plate
			m._ev("plate", now, {"i": plate})
			_fire(m, "plate:%d" % plate, now)
	var triggers: Array = scenario.get("triggers", [])
	for i in triggers.size():
		var on := str(triggers[i].on)
		if not _fired.has(i) and on.begins_with("dead:") and _all_down(on.substr(5)):
			_run(m, i, now)


## Standing rules of the scenario: {hidden_from: unit key, ms, note} tells the lesson once the player has stayed out of that
## unit's line of sight for `ms`. It fires again only after being seen.
func _watch(m: ArenaMatch, player: ArenaUnit, now: float, dt: float) -> void:
	var watches: Array = scenario.get("watch", [])
	for i in watches.size():
		var w: Dictionary = watches[i]
		var u: ArenaUnit = _by_key.get(str(w.get("hidden_from", "")))
		if u == null or player == null or not u.alive or not player.alive:
			continue
		if Rules.has_los(m.map, player, u):
			_hidden_ms[i] = 0.0
			continue
		var before := float(_hidden_ms.get(i, 0.0))
		_hidden_ms[i] = before + dt
		var need := float(w.get("ms", 800.0))
		if before < need and before + dt >= need:
			m._ev("note", now, {"k": str(w.get("note", "hidden"))})


## The client told us the player reached a step of the lesson. Unknown numbers do nothing.
func cue(m: ArenaMatch, n: int, now: float) -> void:
	if not halted:
		_fire(m, "cue:%d" % n, now)


## What the client needs to draw doors and plates.
func client_state(m: ArenaMatch) -> Dictionary:
	return {"d": m.map.door_mask, "p": pressed, "a": active}


func unit(key: String) -> ArenaUnit:
	return _by_key.get(key)


func _all_down(pattern: String) -> bool:
	var wild := pattern.ends_with("*")
	var name := pattern.trim_suffix("*")
	var any := false
	for key in _by_key:
		if key == name or (wild and key.begins_with(name)):
			any = true
			var u: ArenaUnit = _by_key[key]
			if u.alive or (u.dormant and u.deaths == 0):  # still waiting to appear is not the same as down
				return false
	return any


func _fire(m: ArenaMatch, on: String, now: float) -> void:
	var triggers: Array = scenario.get("triggers", [])
	for i in triggers.size():
		if str(triggers[i].on) == on and not _fired.has(i):
			_run(m, i, now)


func _run(m: ArenaMatch, i: int, now: float) -> void:
	if not bool(scenario.triggers[i].get("again", false)):  # a quest can be taken again: its cues fire every time
		_fired[i] = true
	for a in scenario.triggers[i].do:
		_action(m, a, now)


func _action(m: ArenaMatch, a: Array, now: float) -> void:
	var player := _player(m)
	match str(a[0]):
		"open":
			m.map.set_doors(m.map.door_mask | (1 << int(a[1])))
			m._ev("door", now, {"i": int(a[1]), "open": true})
		"close":
			m.map.set_doors(m.map.door_mask & ~(1 << int(a[1])))
			m._ev("door", now, {"i": int(a[1]), "open": false})
		"activate":
			active |= 1 << int(a[1])
		"reset_plates":
			for p in a[1]:
				active &= ~(1 << int(p))
				pressed &= ~(1 << int(p))
		"spawn":
			_spawn(m, str(a[1]), now)
		"stun":
			player.trinket_ready = 0.0
			player.stun_until = now + float(a[1])
			m._label(player, "ATURDIDO", "#ffd166")
		"ult":
			player.ult = 100.0
		"gem":
			m.spawn_power(str(a[1]), float(a[2]), float(a[3]))
		"nocd":
			m.nocd = bool(a[1])
		"note":
			m._ev("note", now, {"k": str(a[1])})
		"hurt":
			var hurt: ArenaUnit = _by_key.get(str(a[1]))
			if hurt != null:
				hurt.hp = maxf(1.0, hurt.max_hp * float(a[2]))
		"cast":
			if _actors.has(str(a[1])):
				(_actors[str(a[1])] as LessonActor).order_cast(m, str(a[2]), player, now)


func _spawn(m: ArenaMatch, key: String, now: float) -> void:
	var u: ArenaUnit = _by_key.get(key)
	if u == null:
		return
	u.dormant = false
	u.alive = true
	u.hp = u.max_hp
	u.x = u.home.x
	u.z = u.home.y
	u.reset_effects()
	m._ev("spawn", now, {"key": key, "id": u.id})


func _player(m: ArenaMatch) -> ArenaUnit:
	for u in m.units:
		if u.peer != 0:
			return u
	return null
