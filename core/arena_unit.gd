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
var team: String
## Network peer that controls this unit (0 = bot).
var peer := 0
var brain: BotBrain = null
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
		_kit = GameData.kit(cls, spec_id)
	return _kit


func ability(slot: int) -> Dictionary:
	return spec().abilities[slot]


## Combat effects cleared at the start of every round.
func reset_effects() -> void:
	curses.clear()
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
