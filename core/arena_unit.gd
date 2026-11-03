class_name ArenaUnit
extends RefCounted
## A fighter in a match (port of the Unit interface in server/match.ts). Times are in ms.

var id: int
var name: String
var cls: String
## Specialization id ("" for classes without any).
var spec_id := "":
	set(v):
		spec_id = v
		_kit = {}
var _kit := {}
## Talent picks (Talents: one index per row, -1 = none), applied to the kit.
var talents: Array = []:
	set(v):
		talents = v
		_kit = {}
var team: String
## Network peer that controls this unit (0 = bot).
var peer := 0
var brain: BotBrain = null
## Scripted matches: this unit's own bot difficulty ("" = the match's), fixed skill (< 0 = drawn from the difficulty) and
## outgoing damage multiplier. The defaults leave a normal match untouched.
var diff := ""
var skill := -1.0
var dmg_mult := 1.0
## Practice arena only: dummy kind ("" for real fighters), its home position and the next scripted action (ms).
var dummy := ""
var home := Vector2.ZERO
var dummy_next := 0.0
var patrol_dir := 1.0

var x := 0.0
var z := 0.0
var vx := 0.0
var vz := 0.0
var dash_left := 0.0
var dash_vx := 0.0
var dash_vz := 0.0
var rot := 0.0
var aim_x := 0.0
var aim_z := 0.0
var input := Vector2.ZERO

var hp := 0.0
var max_hp := 0.0
var alive := true
var cds: Array[float] = []
## Abilities with charges (ability.charges > 1, e.g. Frost Blink): slot -> {left, next}. `next` is when the next
## charge comes back (0 = all charges in). cds[slot] still says when the slot is usable (now while a charge is left).
var charges := {}
## Global cooldown (WoW): after an ability, every other on-GCD ability waits until this.
var gcd_until := 0.0
## PvP trinket: breaks every loss-of-control effect, ready again at this time.
var trinket_ready := 0.0
var ult := 0.0
## {slot, start_at, ends_at, ax, az, target_id, lock} or {}
var cast := {}

var stun_until := 0.0
var root_until := 0.0
var silence_until := 0.0
var incap_until := 0.0
var incap_kind := "poly"
var slow_until := 0.0
var slow_pct := 0.0
var fear_until := 0.0
var fear_x := 0.0
var fear_z := 0.0
var fear_dmg := 0.0
var dr := {}
var revealed_until := 0.0
var last_hit_by := -1
var last_hit_at := 0.0

var crit_until := 0.0
var stealth_until := 0.0
var shield_until := 0.0
var haste_until := 0.0
var absorb := 0.0
var absorb_until := 0.0
var pact_absorb := 0.0
var pact_until := 0.0
var wall_until := 0.0
var marked_until := 0.0
var mortal_until := 0.0
## Healing taken is cut by this much while Mortal Strike lasts (talents can raise it).
var mortal_pct := 0.5
## Talent mechanics: "every Nth cast" counters (ability id -> casts so far), crits towards an instant Pyroblast,
## and the warlock's mark (curse ticks deal +curse_mark until curse_mark_until).
var stacks := {}
## Passive barrier (kit "barrier", Frost mage): up while barrier_on, back at barrier_ready after it breaks.
var barrier_on := false
var barrier_ready := 0.0
var crit_streak := 0
var curse_mark := 0.0
var curse_mark_until := 0.0
## Healed while a sheep (Polymorph), shown as one number per second.
var poly_heal_acc := 0.0
var poly_heal_t := 0.0
var hot_until := 0.0
var hot_hps := 0.0
var hot_by: ArenaUnit = null
var storm_until := 0.0
var storm_next := 0.0
var burn_until := 0.0
var burn_dps := 0.0
var burn_next := 0.0
var burn_by: ArenaUnit = null
## Independent periodic effects keyed by source id + ability id (never reuse mage burn).
var curses := {}
var tempest_stacks := 0  # ronin: Steel Tempest casts in a row (the third one throws a tornado)
var tempest_at := -1e9
var jump_at := -1e9
var auto_target := -1
## Auto-attack toggled on (melee classes and the hunter only).
var auto_on := false
var auto_warn_at := -1e9

var dmg := 0.0
var healed := 0.0
var kills := 0
var deaths := 0


func is_bot() -> bool:
	return peer == 0


func spec() -> Dictionary:
	if _kit.is_empty():
		_kit = Talents.kit(cls, spec_id, talents)
	return _kit


func ability(slot: int) -> Dictionary:
	return spec().abilities[slot]


## The ability with this id in this unit's kit ({} when it is not equipped).
func ability_by_id(ability_id: String) -> Dictionary:
	for a in spec().abilities:
		if str(a.id) == ability_id:
			return a
	return {}


## Puts one of this class's abilities (kit or reserve) on `slot` for this unit only; false if it has no such ability.
func equip(slot: int, ability_id: String) -> bool:
	var a := GameData.find_ability(cls, ability_id, spec_id)
	if a.is_empty() or slot < 0 or slot >= spec().abilities.size():
		return false
	_kit = spec().duplicate()
	_kit.abilities = (_kit.abilities as Array).duplicate()
	_kit.abilities[slot] = a
	return true


## Combat effects cleared at the start of every round.
func reset_effects() -> void:
	curses.clear()
	charges.clear()
	stacks.clear()
	barrier_on = false
	barrier_ready = 0.0
	crit_streak = 0
	curse_mark = 0.0
	curse_mark_until = 0.0
	mortal_pct = 0.5
	tempest_stacks = 0
	cast = {}
	auto_on = false
	stun_until = 0.0
	root_until = 0.0
	silence_until = 0.0
	incap_until = 0.0
	slow_until = 0.0
	fear_until = 0.0
	fear_dmg = 0.0
	dr = {}
	revealed_until = 0.0
	last_hit_by = -1
	crit_until = 0.0
	stealth_until = 0.0
	shield_until = 0.0
	haste_until = 0.0
	absorb = 0.0
	absorb_until = 0.0
	pact_absorb = 0.0
	pact_until = 0.0
	wall_until = 0.0
	marked_until = 0.0
	mortal_until = 0.0
	hot_until = 0.0
	hot_hps = 0.0
	hot_by = null
	storm_until = 0.0
	storm_next = 0.0
	burn_until = 0.0
	burn_by = null
