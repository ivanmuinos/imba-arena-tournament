class_name LessonActor
extends RefCounted
## The script of one enemy in a lesson: a real fighter without AI, so its casts, cast bars and crowd control are the real thing.
## A script is a list of behaviours that all run every tick:
##   {do: "hold_position"}                         stay at home (walks back if pushed)
##   {do: "chase_melee"}                           run to the player and auto-attack
##   {do: "cast_loop", ability, every}             cast it at the player whenever possible, `every` ms apart
##   {do: "heal_self", ability, below}             cast it on itself under that fraction of health
##   {do: "stun_on_cast", ms}                      stun the player as soon as they start a cast (for baiting)
##   {do: "trinket_when_cc"}                       break crowd control with the trinket

const KNOWN := ["hold_position", "chase_melee", "cast_loop", "heal_self", "stun_on_cast", "trinket_when_cc"]
const MELEE_RANGE := 2.6

var unit: ArenaUnit
var behaviours: Array
var _next := {}  # behaviour index -> time (ms) it may act again


func _init(p_unit: ArenaUnit, p_script: Array) -> void:
	unit = p_unit
	behaviours = p_script


## Mistakes in a scenario's unit description. Empty when it is fine (static content test).
static func problems(unit_spec: Dictionary) -> Array:
	var out: Array = []
	var kit := GameData.abilities(str(unit_spec.cls), str(unit_spec.get("spec", "")))
	var ids: Array = kit.map(func(a): return str(a.id))
	for b in unit_spec.get("script", []):
		if not KNOWN.has(str(b.get("do", ""))):
			out.append("comportamiento desconocido: %s" % str(b.get("do", "")))
		elif b.has("ability") and not ids.has(str(b.ability)):
			out.append("%s no tiene %s" % [unit_spec.cls, b.ability])
	return out


static func slot_of(u: ArenaUnit, ability: String) -> int:
	for i in int(GameData.C.SLOT_COUNT):
		if str(u.ability(i).id) == ability:
			return i
	return -1


func tick(m: ArenaMatch, player: ArenaUnit, now: float) -> void:
	if not unit.alive or player == null:
		return
	var move := Vector2.ZERO
	for i in behaviours.size():
		var b: Dictionary = behaviours[i]
		match str(b.get("do", "")):
			"hold_position":
				var home := unit.home - Vector2(unit.x, unit.z)
				if home.length() > 0.5:
					move = home
			"chase_melee":
				var to := Vector2(player.x - unit.x, player.z - unit.z)
				if to.length() > MELEE_RANGE:
					move = to
				if not unit.auto_on and unit.ability(0).get("auto", false):
					m.start_auto(unit, player.id)
			"cast_loop":
				if now >= float(_next.get(i, 0.0)) and _cast(m, str(b.ability), player, now):
					_next[i] = now + float(b.get("every", 2000.0))
			"heal_self":
				if unit.hp < unit.max_hp * float(b.get("below", 0.7)) and unit.cast.is_empty():
					m.cast_ability(unit, slot_of(unit, str(b.ability)), unit.x, unit.z, now, unit.id)
			"stun_on_cast":
				if not player.cast.is_empty() and now >= float(_next.get(i, 0.0)):
					m._cc(player, "stun", float(b.get("ms", 1500.0)), now)
					_next[i] = now + float(b.get("every", 4000.0))
			"trinket_when_cc":
				if now < unit.stun_until or now < unit.incap_until or now < unit.fear_until or now < unit.root_until or now < unit.silence_until:
					m.use_trinket(unit, now)
	m.input(unit, move.x, move.y, player.x, player.z)


## Casts an ability at the player. Refused like any cast (cooldown, range, line of sight): returns whether it started.
func _cast(m: ArenaMatch, ability: String, player: ArenaUnit, now: float) -> bool:
	if not unit.cast.is_empty() or not Rules.has_los(m.map, unit, player):
		return false
	return m.cast_ability(unit, slot_of(unit, ability), player.x, player.z, now, player.id)


## A trigger ordered this cast.
func order_cast(m: ArenaMatch, ability: String, player: ArenaUnit, now: float) -> bool:
	return _cast(m, ability, player, now)
