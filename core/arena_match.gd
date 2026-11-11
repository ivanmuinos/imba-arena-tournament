class_name ArenaMatch
extends RefCounted
## Authoritative arena match simulation (port of server/match.ts).
## Network-agnostic: it fills `fx`, `broadcasts` and `errors`, and builds per-team snapshots;
## the network layer (ENet now, Steam later) just ships them. Times are in milliseconds.

## First round: players wait in their start rooms; later rounds are shorter.
const FIRST_PREP_MS := 10000.0
const ROUND_PREP_MS := 10000.0
## Abilities that may be used in the start room (buffs/shields).
const PREP_OK := ["pwshield", "renew", "shieldwall", "rejuv", "ironbark", "kevlar"]
const BETWEEN_MS := 4000.0
const OVER_MS := 7000.0
const INTERRUPT_LOCK_MS := 4000.0
const TEAMS := ["red", "blue"]
const ULTS := ["meteor", "volley", "bladestorm", "hymn", "deathmark"]

var mode: int
var diff: String
var map: GameMap
var units: Array[ArenaUnit] = []
var projs: Array = []
var aoes: Array = []
var traps: Array = []
var windwalls: Array = []  # ronin: {team, x0, z0, x1, z1, until}; enemy projectiles that cross one vanish
var powers: Array = []

var phase := "prep"
var phase_ends_at := 0.0
var fight_start := 0.0
var round_n := 1
var score := {"red": 0, "blue": 0}
var done := false
## Telemetry only (balance tools): rounds ended by the time limit, rounds ended without a winner, and, among limit
## rounds that had a winner and teams of different total max HP, how many the higher-max-HP team won.
var limit_rounds := 0
var draw_rounds := 0
var limit_decided := 0
var limit_hi_hp_wins := 0
## Telemetry only: among limit rounds that had a winner by absolute health, how many a percent-of-max-health rule would have
## decided for the other team (differs) or left tied (ties). Percent = current health of the living / max health of the whole team.
var limit_pct_decided := 0
var limit_pct_differs := 0
var limit_pct_ties := 0
## Practice arena ("Arena de práctica", offline): one endless fight against training dummies, no rounds, no dampening, instant respawn.
var practice := false
## Debug (`--god`, used by the real-input playtests): human players take no damage and cannot be crowd controlled,
## so a scenario about key presses is never ruined by dying or being stunned mid-test.
var god := false
## Practice: skip every cooldown of the human players ("modo sin cooldowns").
var nocd := false
var meters := {}  # unit id -> PracticeMeter

## Lesson only: the scenario driving this match (LessonStage; anything with step(match, now)) and the structured log of
## what happened, for objectives and medals. Both stay null in every other match, so they cost nothing there.
var stage: RefCounted = null
var journal = null  # Array of {e, at, ...} while a lesson runs, drained by the network layer

## Outgoing events for everyone in the match (drained by the network layer).
var fx: Array = []
var broadcasts: Array = []
## Per-player error messages: [{peer, text}].
var errors: Array = []

var _next_id := 1
var _first_round := true
var _next_power_at := 0.0
var _last_now := 0.0  # clock of the last tick, for commands that are not handed the time
var _dt := 1.0 / 60.0
var C: Dictionary


## entries: [{name, cls, team, peer}] (peer 0 = bot). Scripted matches add per unit: diff, skill, hp_mult, dmg_mult.
func _init(p_mode: int, entries: Array, now: float, p_diff := "normal", map_id := "bridge") -> void:
	GameData.ensure_loaded()
	C = GameData.C
	_dt = 1.0 / C.SIM_HZ
	mode = p_mode
	diff = p_diff
	map = GameMap.create(map_id)
	practice = map.id == GameMap.PRACTICE_ID or GameMap.is_lesson_map(map.id)
	for e in entries:
		var u := ArenaUnit.new()
		u.id = _next_id
		_next_id += 1
		u.name = e.name
		u.cls = e.cls
		u.spec_id = GameData.normalize_spec(u.cls, str(e.get("spec", "")))
		u.talents = Talents.normalize(u.cls, u.spec_id, e.get("talents", []))
		u.team = e.team
		u.peer = e.get("peer", 0)
		u.dummy = str(e.get("dummy", ""))
		u.diff = str(e.get("diff", ""))
		u.skill = float(e.get("skill", -1.0))
		u.dmg_mult = float(e.get("dmg_mult", 1.0))
		u.lesson_key = str(e.get("lesson_key", ""))
		u.mortal = bool(e.get("mortal", false))
		if u.peer == 0 and u.dummy == "" and not bool(e.get("no_brain", false)):
			u.brain = _new_brain(u)
		u.max_hp = float(e.hp) if u.dummy != "" else float(u.spec().hp) * float(e.get("hp_mult", 1.0))
		if u.dummy != "" or u.lesson_key != "":
			u.home = Vector2(float(e.x), float(e.z))
		if practice and u.peer != 0:
			meters[u.id] = PracticeMeter.new()
		u.hp = u.max_hp
		u.ult = C.ULT_START
		u.cds.resize(int(C.SLOT_COUNT))
		u.cds.fill(0.0)
		u.charges.clear()
		units.append(u)
	for u in units:
		synergies[u.team] = Synergies.effects(units.filter(func(o): return o.team == u.team and o.dummy == "").map(func(o): return o.cls))
	_reset_round(now)


func roster() -> Array:
	return units.map(func(u):
		var r := {"id": u.id, "name": u.name, "cls": u.cls, "spec": u.spec_id, "team": u.team, "bot": u.is_bot()}
		if u.talents.any(func(v): return v >= 0):
			r["talents"] = u.talents
		if u.dummy != "":
			r["dummy"] = u.dummy
			r["hp"] = u.max_hp
		elif not is_equal_approx(u.max_hp, float(u.spec().hp)):
			r["hp"] = u.max_hp  # scripted HP: GameData.entry_max_hp (the HUD) reads it from here
		return r)


func unit_for_peer(peer: int) -> ArenaUnit:
	for u in units:
		if u.peer == peer:
			return u
	return null


func unit_by_id(id: int) -> ArenaUnit:
	for u in units:
		if u.id == id:
			return u
	return null


## A human left mid-match: a bot takes over so the arena stays fair.
func leave(u: ArenaUnit) -> void:
	u.peer = 0
	u.brain = _new_brain(u)


## Bot brain of a unit: its own difficulty and fixed skill when scripted, else the match's.
func _new_brain(u: ArenaUnit) -> BotBrain:
	var b := BotBrain.new(u.diff if u.diff != "" else diff)
	if u.skill >= 0.0:
		b.skill = u.skill
	return b


# ---------------------------------------------------------------- rounds

func _reset_round(now: float) -> void:
	projs.clear()
	windwalls.clear()
	aoes.clear()
	traps.clear()
	powers.clear()
	for team in TEAMS:
		var spawns: Array = map.spawns[team]
		var i := 0
		for u in units:
			if u.team != team:
				continue
			if u.dummy != "":
				_reset_dummy(u, now)
				continue
			var s: Dictionary = spawns[i % spawns.size()]
			i += 1
			u.reset_effects()
			u.x = s.x
			u.z = s.z
			u.vx = 0.0
			u.vz = 0.0
			u.dash_left = 0.0
			Rules.ground(u, map)
			u.hp = u.max_hp
			u.alive = true
			u.rot = PI if team == "red" else 0.0
			u.aim_x = 0.0
			u.aim_z = 0.0
			u.cds.fill(0.0)
			u.charges.clear()
			u.gcd_until = 0.0
			u.trinket_ready = 0.0  # every round starts with everything ready, the trinket too (like Solo Shuffle)
	if practice:
		phase = "fight"  # no start room, no countdown: the yard is always live
		phase_ends_at = 0.0
		fight_start = now
		_first_round = false
		map.apply_state(true, 0.0)
		return
	phase = "prep"
	phase_ends_at = now + (FIRST_PREP_MS if _first_round else ROUND_PREP_MS)
	_first_round = false
	map.apply_state(false, 0.0)


func _end_round(winner: String, now: float) -> void:
	if phase != "fight":
		return
	if winner != "":
		score[winner] += 1
	else:
		draw_rounds += 1
	var over: bool = winner != "" and score[winner] >= C.ROUNDS_TO_WIN
	phase = "over" if over else "between"
	phase_ends_at = now + (OVER_MS if over else BETWEEN_MS)
	if over:
		broadcasts.append({
			"t": "end", "winner": winner, "score": score.duplicate(),
			"stats": units.map(func(u): return {"id": u.id, "dmg": roundi(u.dmg), "kills": u.kills, "deaths": u.deaths, "heal": roundi(u.healed)}),
		})


## A player abandoned a 1v1 against another human: the other team wins by walkover.
func forfeit(team: String, now: float) -> void:
	if phase == "over" or done:
		return
	var winner := "blue" if team == "red" else "red"
	score[winner] = maxi(int(score[winner]), int(C.ROUNDS_TO_WIN))
	phase = "over"
	phase_ends_at = now + OVER_MS
	broadcasts.append({
		"t": "end", "winner": winner, "score": score.duplicate(),
		"stats": units.map(func(u): return {"id": u.id, "dmg": roundi(u.dmg), "kills": u.kills, "deaths": u.deaths, "heal": roundi(u.healed)}),
	})


# ---------------------------------------------------------------- commands

func input(u: ArenaUnit, dx: float, dz: float, ax: float, az: float) -> void:
	u.input = Vector2(clampf(dx, -1, 1), clampf(dz, -1, 1))
	u.aim_x = clampf(ax, -map.half_x * 2, map.half_x * 2)
	u.aim_z = clampf(az, -map.half_z * 2, map.half_z * 2)


func set_target(u: ArenaUnit, id: int) -> void:
	var t := unit_by_id(id)
	if t != null and t.team != u.team:
		u.auto_target = id
	else:  # a friend, nothing or garbage: the auto-attack stops
		u.auto_target = -1
		u.auto_on = false


## Turns the auto-attack on against an enemy (melee classes and the hunter only; casters never auto-attack).
func start_auto(u: ArenaUnit, id: int) -> bool:
	if not u.alive or not u.ability(0).get("auto", false):
		return false
	var t := unit_by_id(id)
	if t == null or t.team == u.team or not t.alive:
		return false
	u.auto_target = id
	u.auto_on = true
	return true


func stop_auto(u: ArenaUnit) -> void:
	u.auto_on = false


## Esc: drops the cast in progress (no cooldown is applied).
func cancel_cast(u: ArenaUnit) -> void:
	if not u.cast.is_empty() and journal != null:
		_ev("cast_cancel", _last_now, {"u": u.id, "ability": str(u.ability(u.cast.slot).id), "why": "esc"})
	u.cast = {}


## A journal entry. Without a lesson it returns at once.
func _ev(kind: String, now: float, fields: Dictionary) -> void:
	if journal == null:
		return
	fields["e"] = kind
	fields["at"] = now
	journal.append(fields)


func jump(u: ArenaUnit, now: float) -> void:
	if not u.alive or u.dormant or not Rules.can_walk_in(phase) or now < u.stun_until or now < u.incap_until or now < u.root_until or now < u.fear_until:
		return
	if u.dash_left > 0.0 or not Rules.jump(u):
		return  # only from the ground: the jump is real (Rules.step_mover), not a timer
	if not u.cast.is_empty():
		_error(u, "%s cancelado: saltaste" % u.ability(u.cast.slot).name)
		_ev("cast_cancel", now, {"u": u.id, "ability": str(u.ability(u.cast.slot).id), "why": "jump"})
		u.cast = {}  # jumping cancels a cast, like moving does


func _can_act(u: ArenaUnit, spec: Dictionary, now: float) -> String:
	if now < u.stun_until: return "Estás aturdido"
	if now < u.incap_until: return "Estás incapacitado"
	if now < u.fear_until: return "Estás aterrorizado"
	if not spec.get("physical", false) and now < u.silence_until: return "Estás silenciado"
	return ""


func _error(u: ArenaUnit, text: String) -> void:
	if u.peer != 0:
		errors.append({"peer": u.peer, "text": text})


## Resolves a selected target: an enemy the team can currently see.
func _lock_target(u: ArenaUnit, id: int, now: float) -> ArenaUnit:
	if id < 0:
		return null
	var t := unit_by_id(id)
	return t if t != null and t.alive and t.team != u.team and team_can_see(u.team, t, now) else null


func _dist(a, b) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## WoW's global cooldown: auto attacks and the instant defensives/interrupts marked offGcd skip it.
static func on_gcd(spec: Dictionary) -> bool:
	return not spec.get("auto", false) and not spec.get("offGcd", false)


## 1.5 s, or the class's own (the rogue's is 1 s, like WoW's energy users).
static func gcd_ms(u: ArenaUnit) -> float:
	return float(u.spec().get("gcd", GameData.C.GCD_MS))


## PvP trinket (WoW's medallion): breaks stun, incapacitate, fear, root, silence and slows. Its own 2 min cooldown,
## off the global cooldown, usable while controlled (that is the point).
func use_trinket(u: ArenaUnit, now: float) -> bool:
	if not u.alive or phase != "fight":
		return false
	if now < u.trinket_ready:
		_error(u, "El abalorio todavía no está listo")
		return false
	u.trinket_ready = now + float(C.TRINKET_CD_MS)
	for f in ["stun_until", "incap_until", "fear_until", "root_until", "silence_until", "slow_until"]:
		if u.get(f) > now:
			u.set(f, now)
	_label(u, "ABALORIO", "#ffd166")
	fx.append({"k": "trinket", "id": u.id})
	_ev("trinket", now, {"u": u.id})
	return true


## Tries to use an ability; returns whether it started.
func cast_ability(u: ArenaUnit, slot: int, ax: float, az: float, now: float, target_id := -1) -> bool:
	if not u.alive or slot < 0 or slot >= C.SLOT_COUNT:
		return false
	if not u.cast.is_empty():
		return false  # repeating a key (or pressing another) never restarts or cancels the cast in progress
	var spec := u.ability(slot)
	if phase != "fight" and not (phase == "prep" and spec.id in PREP_OK):
		return false
	var is_ult: bool = spec.get("ult", false)
	if on_gcd(spec) and now < u.gcd_until and not (is_ult and u.ult < 100) and (is_ult or now >= u.cds[slot]):
		return false  # global cooldown: silent, the client queues the key until it ends
	if (is_ult and u.ult < 100) or (not is_ult and now < u.cds[slot]):
		if slot != 0:
			_error(u, "La ultimate no está cargada" if is_ult else "Todavía no está lista")
		return false
	var blocked := _can_act(u, spec, now)
	if blocked != "":
		if slot != 0:
			_error(u, blocked)
		return false
	if u.air and float(spec.get("cast", 0.0)) > 0.0 and not spec.get("castMove", false):
		if slot != 0:
			_error(u, "No podés lanzar en el aire")
		return false
	if (spec.id == "disengage" or spec.id == "charge") and now < u.root_until:
		_error(u, "Estás enraizado")
		return false
	var locked := _lock_target(u, target_id, now)
	var target := -1
	var lock := -1
	if spec.get("friendly", false):
		var f := _friend_target(u, target_id, spec.range, now)
		if f == null:
			_error(u, "Ningún aliado al alcance")
			return false
		target = f.id
	elif spec.get("melee", false):
		var t := _melee_target(u, locked, spec.range, now)
		if t == null:
			if slot != 0:
				_error(u, _melee_problem(u, locked, spec.range) if locked != null else "Ningún enemigo al alcance")
			return false
		target = t.id
	elif spec.get("targeted", false):
		var t: ArenaUnit = locked if locked != null else _find_target(u, ax, az, spec.range, now)
		if t == null:
			_error(u, "Sin objetivo a la vista")
			return false
		if _dist(t, u) > spec.range + 1:
			_error(u, "Fuera de alcance")
			return false
		if not Rules.has_los(map, u, t):
			_error(u, "No está en tu línea de visión")
			return false
		target = t.id
	elif locked != null and spec.has("projSpeed") and spec.id != "volley":
		# Homing spell on the selected target: needs range and line of sight, like WoW.
		if _dist(locked, u) > spec.range + 1:
			if slot != 0: _error(u, "Fuera de alcance")
			return false
		if not Rules.has_los(map, u, locked):
			if slot != 0: _error(u, "No está en tu línea de visión")
			return false
		lock = locked.id
		ax = locked.x
		az = locked.z
	elif locked != null and spec.id in ["meteor", "trap", "volley", "flashbang"]:
		ax = locked.x + locked.vx * 0.3
		az = locked.z + locked.vz * 0.3
	if target >= 0 and slot != 0 and (spec.get("melee", false) or spec.id == "charge") and u.ability(0).get("auto", false):
		u.auto_on = true  # a melee ability on your target also starts the auto-attack
		u.auto_target = target
	u.cast = {}
	if on_gcd(spec):
		u.gcd_until = now + gcd_ms(u)  # starts when the ability starts, cast time or not (WoW)
	var cast_ms := _cast_ms(u, spec, target if target >= 0 else lock, ax, az, now)
	if cast_ms > 0:
		u.cast = {"slot": slot, "start_at": now, "ends_at": now + cast_ms, "ax": ax, "az": az, "target_id": target, "lock": lock, "pushes": 0}
		u.vx = 0.0
		u.vz = 0.0
		return true
	_execute(u, slot, ax, az, target, now, lock)
	return true


const MELEE_LEEWAY := 0.8
const MELEE_MOVING_LEEWAY := 0.8


## Effective melee reach: range + leeway, a little more when either of you is moving (latency and closing speed).
func _melee_reach(u: ArenaUnit, e: ArenaUnit, range_m: float) -> float:
	var moving := Vector2(e.vx, e.vz).length() > 0.5 or Vector2(u.vx, u.vz).length() > 0.5
	return range_m + MELEE_LEEWAY + (MELEE_MOVING_LEEWAY if moving else 0.0)


## Generous 180 degree cone in front of the attacker.
func _facing(u: ArenaUnit, e: ArenaUnit, min_dot := 0.0) -> bool:
	var to := Vector2(e.x - u.x, e.z - u.z)
	if to.length() < 0.6:
		return true
	return Vector2(sin(u.rot), cos(u.rot)).dot(to.normalized()) >= min_dot


## "" when `e` can be hit in melee, else the reason shown to the player.
func _melee_problem(u: ArenaUnit, e: ArenaUnit, range_m: float) -> String:
	if _dist(e, u) > _melee_reach(u, e, range_m) or not Rules.has_los(map, u, e):
		return "Fuera de alcance"
	if not _facing(u, e):
		return "Tenés que mirar al objetivo"
	return ""


## Melee: the selected target if it can be hit, else the closest visible enemy that can.
func _melee_target(u: ArenaUnit, locked: ArenaUnit, range_m: float, now: float) -> ArenaUnit:
	if locked != null:
		return locked if _melee_problem(u, locked, range_m) == "" else null
	var best: ArenaUnit = null
	for e in units:
		if not e.alive or e.team == u.team or not team_can_see(u.team, e, now) or _melee_problem(u, e, range_m) != "":
			continue
		if best == null or _dist(e, u) < _dist(best, u):
			best = e
	return best


## Friendly spells: the chosen ally if valid, else the most wounded ally (or yourself) in range.
func _friend_target(u: ArenaUnit, id: int, range_m: float, now: float) -> ArenaUnit:
	var ok := func(a: ArenaUnit) -> bool:
		return a.alive and a.team == u.team and _dist(a, u) <= range_m + 1 and (a == u or Rules.has_los(map, u, a))
	var chosen := unit_by_id(id)
	if chosen != null and ok.call(chosen):
		return chosen
	var best: ArenaUnit = null
	for a in units:
		if ok.call(a) and (best == null or a.hp / a.max_hp < best.hp / best.max_hp):
			best = a
	return best


func _find_target(u: ArenaUnit, ax: float, az: float, range_m: float, now: float) -> ArenaUnit:
	var best: ArenaUnit = null
	var best_d := 4.0
	for e in units:
		if not e.alive or e.team == u.team or not team_can_see(u.team, e, now):
			continue
		if _dist(e, u) > range_m + 0.5 or not Rules.has_los(map, u, e):
			continue
		var d := Vector2(e.x - ax, e.z - az).length()
		if d < best_d:
			best = e
			best_d = d
	return best


func team_can_see(team: String, t: ArenaUnit, now: float) -> bool:
	if t.team == team or (practice and t.dummy != ""):
		return true
	if now < t.stealth_until:
		# Stealthed: only noticed when an enemy is practically on top of you.
		for m in units:
			if m.team == team and m.alive and _dist(m, t) < C.STEALTH_DETECT:
				return true
		return false
	var revealed := now < t.revealed_until
	for m in units:
		if m.team == team and m.alive and Rules.can_see(map, m, t, revealed):
			return true
	return false


# ---------------------------------------------------------------- talent mechanics

## Cast time of a spell after talent mechanics: Pyroblast is instant after `instantAfterCrits` crits, Shadow Bolt casts
## `curseHaste` faster on a target with your curse.
func _cast_ms(u: ArenaUnit, spec: Dictionary, target_id: int, ax: float, az: float, now: float) -> float:
	var ms := maxf(0.0, float(spec.cast))
	if ms <= 0.0:
		return 0.0
	var need := int(spec.get("instantAfterCrits", 0))
	if need > 0 and u.crit_streak >= need:
		u.crit_streak = 0
		_label(u, "¡RACHA CALIENTE!", "#ffb347")
		return 0.0
	if float(spec.get("curseHaste", 0.0)) > 0.0:
		var t := unit_by_id(target_id) if target_id >= 0 else _find_target(u, ax, az, spec.range, now)
		if t != null and t.curses.values().any(func(d): return int(d.owner) == u.id and now < float(d.until) and str(d.ability) != "poison"):
			ms *= 1.0 - float(spec.curseHaste)
	return ms


## Counts a cast of an "every Nth" ability; true when this one is the Nth (it is empowered).
func _count_nth(u: ArenaUnit, spec: Dictionary) -> bool:
	var n := int(spec.get("nth", 0))
	if n <= 1:
		return false
	var c := int(u.stacks.get(spec.id, 0)) + 1
	if c >= n:
		u.stacks[spec.id] = 0
		return true
	u.stacks[spec.id] = c
	return false


## Counters shown on the action bar (-1 = none): "every Nth" casts so far, or crits towards an instant Pyroblast.
func stacks_shown(u: ArenaUnit) -> Array:
	var out: Array = []
	for a in u.spec().abilities:
		if int(a.get("nth", 0)) > 1:
			out.append(int(u.stacks.get(a.id, 0)))
		elif int(a.get("instantAfterCrits", 0)) > 0:
			out.append(mini(u.crit_streak, int(a.instantAfterCrits)))
		else:
			out.append(-1)
	return out


## Damage multiplier of a talent condition: vs slowed/rooted targets (`vsSlowed`), from behind (`behind`).
func _talent_bonus(a: Dictionary, src: ArenaUnit, t: ArenaUnit, now: float) -> float:
	var m := 1.0
	if float(a.get("vsSlowed", 0.0)) > 0.0 and _hindered(t, now):
		m *= 1.0 + float(a.vsSlowed)
	if float(a.get("behind", 0.0)) > 0.0 and _behind(src, t):
		m *= 1.0 + float(a.behind)
	return m


func _synergy(team: String, field: String) -> float:
	return float(synergies.get(team, {}).get(field, 0.0))


## Team-synergy multiplier for a physical hit.
func _synergy_physical(src: ArenaUnit, t: ArenaUnit, now: float) -> float:
	var m := 1.0
	if now < t.root_until or (now < t.incap_until and t.incap_kind in ["poly", "freeze"]):
		m *= 1.0 + _synergy(src.team, "physicalVsControlled")
	if now < t.exposed_until:
		m *= 1.0 + t.exposed_pct
	return m


## A mage has left this target burning or slowed with a Frostbolt.
func _mage_softened(t: ArenaUnit, now: float) -> bool:
	return now < t.chill_until or (now < t.burn_until and t.burn_by != null and t.burn_by.cls == "mage")


func _hindered(t: ArenaUnit, now: float) -> bool:
	return now < t.slow_until or now < t.root_until


## The attacker stands in the target's back half.
func _behind(src: ArenaUnit, t: ArenaUnit) -> bool:
	var to := Vector2(src.x - t.x, src.z - t.z)
	return to.length_squared() > 0.0001 and Vector2(sin(t.rot), cos(t.rot)).dot(to.normalized()) < 0.0


## What a talented hit does after its damage lands: leech, healing an ally, cooldown cuts, poison, stacking slows,
## the warlock's mark, the Nth-hit freeze and resets on a kill.
func _after_hit(t: ArenaUnit, src: ArenaUnit, a: Dictionary, amount: float, now: float) -> void:
	if float(a.get("leech", 0.0)) > 0.0:
		_heal(src, amount * float(a.leech), src, now)
	if float(a.get("allyHeal", 0.0)) > 0.0:
		var low: ArenaUnit = null
		for o in units:
			if o.alive and o.team == src.team and o.hp < o.max_hp and (low == null or o.hp / o.max_hp < low.hp / low.max_hp):
				low = o
		if low != null:
			_heal(low, amount * float(a.allyHeal), src, now)
	if a.has("cdOf"):
		for cid in (a.cdOf if a.cdOf is Array else [a.cdOf]):
			var slot := _slot_of(src, str(cid))
			if slot >= 0:
				src.cds[slot] = maxf(now, src.cds[slot] - float(a.get("cdBy", 0.0)))
				break
	if float(a.get("poison", 0.0)) > 0.0 and t.alive:
		_apply_curse(t, src, {"id": "poison", "name": "Veneno", "dotDps": a.poison, "durationMs": a.get("poisonMs", 6000.0)}, now, true)
	if float(a.get("slowStack", 0.0)) > 0.0 and t.alive:
		var cap := float(a.slowStack) * float(a.get("slowStacks", 3))
		t.slow_pct = minf(cap, (t.slow_pct if now < t.slow_until else 0.0) + float(a.slowStack))
		t.slow_until = maxf(t.slow_until, now + float(a.get("slowMs", 3000.0)))
	if float(a.get("curseMark", 0.0)) > 0.0:
		t.curse_mark = float(a.curseMark)
		t.curse_mark_until = now + float(a.get("markMs", 6000.0))
	if _hit_emp and str(a.get("nthEffect", "")) == "freeze" and t.alive:
		_cc(t, "incap", float(a.get("nthMs", 1000.0)), now, "freeze")
	if t.hp <= 0.0 and a.has("killReset"):
		var slot := _slot_of(src, str(a.killReset))
		if slot >= 0:
			src.cds[slot] = now
			src.charges.erase(slot)
			_label(src, "¡REINICIADO!", "#ffd166")


func _slot_of(u: ArenaUnit, ability_id: String) -> int:
	var abilities: Array = u.spec().abilities
	for i in abilities.size():
		if str(abilities[i].id) == ability_id:
			return i
	return -1


## A projectile with `bounce` jumps once from the unit it hit to the nearest other enemy in reach, at that share of the damage.
func _bounce(p: Dictionary, t: ArenaUnit, now: float) -> void:
	var spec: Dictionary = p.spec
	if float(spec.get("bounce", 0.0)) <= 0.0 or p.get("bounced", false):
		return
	var best: ArenaUnit = null
	for e in units:
		if e == t or not e.alive or e.team == p.owner.team or not team_can_see(p.owner.team, e, now):
			continue
		var d := _dist(e, t)
		if d <= float(spec.get("bounceRange", 8.0)) and Rules.has_los(map, t, e) and (best == null or d < _dist(best, t)):
			best = e
	if best == null:
		return
	var s2: Dictionary = spec.duplicate()
	s2.dmg = float(spec.get("dmg", 0.0)) * float(spec.bounce)
	if s2.has("burnDps"): s2.burnDps = float(s2.burnDps) * float(spec.bounce)
	var dir := Vector2(best.x - t.x, best.z - t.z).normalized()
	projs.append({
		"id": _new_id(), "owner": p.owner, "spec": s2, "x": t.x + dir.x * 0.6, "z": t.z + dir.y * 0.6,
		"vx": dir.x * float(s2.projSpeed), "vz": dir.y * float(s2.projSpeed), "left": float(spec.get("bounceRange", 8.0)) + 6.0,
		"target": best, "bounced": true, "emp": false, "hits": [t.id],
	})
	fx.append({"k": "label", "id": t.id, "text": "¡REBOTE!", "color": "#ffd166"})


# ---------------------------------------------------------------- abilities

## One charge spent: the recharge starts with the first one and brings them back one at a time.
func _spend_charge(u: ArenaUnit, slot: int, spec: Dictionary, now: float) -> void:
	var st: Dictionary = u.charges.get(slot, {"left": int(spec.charges), "next": 0.0})
	st.left = maxi(0, int(st.left) - 1)
	if float(st.next) <= 0.0:
		st.next = now + float(spec.cd)
	u.charges[slot] = st
	u.cds[slot] = now if int(st.left) > 0 else float(st.next)


func _refill_charges(u: ArenaUnit, now: float) -> void:
	for slot in u.charges:
		var st: Dictionary = u.charges[slot]
		var spec := u.ability(slot)
		var most := int(spec.get("charges", 1))
		while float(st.next) > 0.0 and now >= float(st.next):
			st.left = mini(most, int(st.left) + 1)
			st.next = (float(st.next) + float(spec.cd)) if int(st.left) < most else 0.0
			u.cds[slot] = minf(u.cds[slot], now)


## Charges left per slot for the HUD (-1 = the ability has no charges).
func charges_left(u: ArenaUnit) -> Array:
	var out: Array = []
	for i in u.spec().abilities.size():
		var most := int(u.ability(i).get("charges", 1))
		out.append(int(u.charges.get(i, {"left": most}).left) if most > 1 else -1)
	return out


func _execute(u: ArenaUnit, slot: int, ax: float, az: float, target_id: int, now: float, lock_id := -1) -> void:
	var spec := u.ability(slot)
	if practice and u.peer != 0:
		meter_for(u).record_cast(spec.id, now)
	if spec.get("ult", false):
		u.ult = 0.0
	elif int(spec.get("charges", 1)) > 1:
		_spend_charge(u, slot, spec, now)
	else:
		var still := float(spec.get("stillCd", 0.0)) if u.input.length() < 0.1 else 0.0
		u.cds[slot] = now + spec.cd * (1.0 - still)
	_cast_emp = _count_nth(u, spec)
	_hit_emp = _cast_emp
	u.revealed_until = maxf(u.revealed_until, now + 1500)
	var from_stealth := now < u.stealth_until  # rogue openers hit harder from stealth
	u.stealth_until = 0.0  # attacking breaks stealth
	if spec.get("melee", false):
		fx.append({"k": "swing", "id": u.id, "heavy": slot != 0})
	var dir := Vector2(ax - u.x, az - u.z)
	var len := dir.length()
	dir = Vector2(sin(u.rot), cos(u.rot)) if len < 1e-3 else dir / len
	var aim_dist := minf(len, spec.range)
	var target := unit_by_id(target_id) if target_id >= 0 else null
	var lock := _lock_target(u, lock_id, now)
	if lock != null:
		dir = Vector2(lock.x - u.x, lock.z - u.z).normalized()
	fx.append({"k": "cast", "id": u.id, "ability": spec.id})
	_ev("cast", now, {"u": u.id, "ability": str(spec.id)})
	var id: String = spec.id

	match id:
		"smite", "fireball", "pyro", "shot", "aimed", "conc", "silence", "frostbolt", "icelance", "shadowbolt", "wrath", "rifle", "headshot", "awp", "pass", "chip", "golazo", "spark", "stunbolt", "disarm", "kiblast", "hammer":
			_spawn_proj(u, spec, dir, lock)
		"corruption", "agony", "soulrot":
			if target != null and target.alive:
				_damage(target, spec.get("dmg", 0.0), u, now, id)
				_apply_curse(target, u, spec, now)
				if float(spec.get("spread", 0.0)) > 0.0:
					for e in _enemies_within(u, target.x, target.z, float(spec.spread)):
						if e != target and team_can_see(u.team, e, now):
							_apply_curse(e, u, spec, now)
							break
		"fear":
			if target != null and target.alive and Rules.has_los(map, u, target) and _dist(target, u) <= spec.range + 1:
				target.fear_x = u.x
				target.fear_z = u.z
				_cc(target, "fear", spec.ccMs, now)
		"darkpact":
			u.hp -= minf(u.hp * 0.15, maxf(0.0, u.hp - 1.0))
			u.pact_absorb = float(spec.absorb)
			u.pact_until = now + float(spec.durationMs)
			_label(u, "PACTO OSCURO", "#b18ae8")
		"drainlife":
			if target != null and target.alive and Rules.has_los(map, u, target) and _dist(target, u) <= spec.range + 1:
				var before := target.hp
				_damage(target, spec.dmg, u, now, id)
				_heal(u, maxf(0.0, before - target.hp) * float(spec.get("drainHeal", 1.0)), u, now)
		"volley":
			var base := atan2(dir.x, dir.y)
			var spread := deg_to_rad(70)
			for i in range(-4, 5):
				var a := base + i / 4.0 * spread / 2
				_spawn_proj(u, spec, Vector2(sin(a), cos(a)))
		"frostblink":  # Frost Blink: a nova where you stood, then the blink
			fx.append({"k": "nova", "x": u.x, "z": u.z, "r": spec.aoe})
			for e in _enemies_within(u, u.x, u.z, spec.aoe):
				_damage(e, spec.dmg, u, now, id)
				_cc(e, "root", spec.ccMs, now)
			var bp := Rules.blink_target(map, u.x, u.z, dir.x, dir.y, spec.dist)
			fx.append({"k": "blink", "x0": u.x, "z0": u.z, "x1": bp.x, "z1": bp.y})
			u.root_until = 0.0
			u.dash_left = 0.0
			u.x = bp.x
			u.z = bp.y
		"nova":
			fx.append({"k": "nova", "x": u.x, "z": u.z, "r": spec.aoe})
			for e in _enemies_within(u, u.x, u.z, spec.aoe):
				_damage(e, spec.dmg, u, now, id)
				_cc(e, "root", spec.ccMs, now)
		"dragonbreath":
			var half := deg_to_rad(float(spec.cone))
			fx.append({"k": "breath", "id": u.id, "x": u.x, "z": u.z, "dx": dir.x, "dz": dir.y, "r": spec.range})
			for e in _enemies_within(u, u.x, u.z, spec.range):
				var to := Vector2(e.x - u.x, e.z - u.z)
				if to.length() > 0.6 and absf(dir.angle_to(to)) > half:
					continue
				_damage(e, spec.dmg, u, now, id)
				_cc(e, "incap", spec.ccMs, now, "disorient")  # after the damage, which would break it
		"blizzard":
			var bc := Vector2(u.x, u.z) + dir * aim_dist
			aoes.append({"id": _new_id(), "owner": u, "spec": spec, "kind": "blizzard", "x": bc.x, "z": bc.y, "at": now, "until": now + float(spec.durationMs), "next": now})
		"poly":
			if target != null and target.alive and Rules.has_los(map, u, target) and _dist(target, u) <= spec.range + 1:
				_cc(target, "incap", spec.ccMs, now, "poly")
			else:
				_error(u, "El objetivo escapó")
		"counter", "pummel", "kick", "bash", "upcut", "tackle":
			if target != null and target.alive:
				if not target.cast.is_empty():
					_interrupt(target, now)
					_cc(target, "silence", spec.ccMs, now)
				else:
					_label(target, "SIN EFECTO", "#999999")
		"blink":
			var p := Rules.blink_target(map, u.x, u.z, dir.x, dir.y, spec.dist)
			fx.append({"k": "blink", "x0": u.x, "z0": u.z, "x1": p.x, "z1": p.y})
			u.root_until = 0.0
			u.dash_left = 0.0
			u.x = p.x
			u.z = p.y
		"disengage":
			Rules.knock(u, -dir, float(spec.dist), Rules.LEAP_S)  # a backwards leap, in an arc
			u.knocked = false  # its own jump: the client predicts it
		"trap":
			var p := {"x": u.x + dir.x * aim_dist, "z": u.z + dir.y * aim_dist}
			Rules.collide(p, map, 0.3)
			traps = traps.filter(func(t): return t.owner != u)
			traps.append({"id": _new_id(), "owner": u, "x": p.x, "z": p.z, "armed_at": now + C.TRAP_ARM_MS, "expires_at": now + 60000})
		"meteor":
			var c := Vector2(u.x, u.z) + dir * aim_dist
			for i in 3:
				var a := randf() * TAU
				var off := 0.0 if i == 0 else 1.6
				aoes.append({"id": _new_id(), "owner": u, "spec": spec, "kind": "meteor", "x": c.x + sin(a) * off, "z": c.y + cos(a) * off, "at": now + 900 + i * 350})
		# ---- warrior
		"strike", "stab", "crusader":
			if target != null: _damage(target, spec.dmg, u, now, id)
		"eviscerate":
			if target != null: _damage(target, spec.dmg * (1.3 if from_stealth else 1.0), u, now, id)
		"mortal":
			if target != null:
				_damage(target, spec.dmg, u, now, id)
				target.mortal_until = now + 8000
				target.mortal_pct = float(spec.get("healCut", 0.5))
				_label(target, "HERIDA MORTAL", "#ff4d4d")
		"hamstring":
			if target != null:
				_damage(target, spec.dmg, u, now, id)
				target.slow_until = now + spec.ccMs
				target.slow_pct = spec.slowPct
				_label(target, "RALENTIZADO", "#4da3ff")
		"charge":
			if target != null:
				var d := _dist(target, u)
				var travel := maxf(0.0, d - 1.6)
				var speed := 30.0
				u.dash_left = travel / speed
				u.dash_vx = (target.x - u.x) / maxf(d, 1e-3) * speed
				u.dash_vz = (target.z - u.z) / maxf(d, 1e-3) * speed
				fx.append({"k": "charge", "id": u.id, "x0": u.x, "z0": u.z, "x1": target.x, "z1": target.z})
				var extra := _synergy(u.team, "chargeStunMs") if _mage_softened(target, now) else 0.0
				if extra > 0.0:
					_label(target, "¡SINERGIA!", "#ffd166")
				_cc(target, "stun", spec.ccMs + u.dash_left * 1000 + extra, now)
		"shieldwall":
			u.wall_until = now + spec.ccMs
			_label(u, "MURO DE ESCUDO", "#c9ced6")
		"bladestorm":
			u.storm_until = now + spec.ccMs
			u.storm_next = now
			u.root_until = 0.0
			u.slow_until = 0.0
			_label(u, "FILOTORMENTA", "#ffd166")
		# ---- priest
		"heal", "holylight", "layhands", "regrowth":
			if target != null:
				fx.append({"k": "healspell", "id": target.id, "ability": spec.id})  # always shown, even at full health
				_heal(target, spec.heal, u, now)
				if float(spec.get("hotHps", 0.0)) > 0.0:
					target.hot_until = now + float(spec.get("hotMs", 6000.0))
					target.hot_hps = float(spec.hotHps)
					target.hot_by = u
		"blessing":  # Blessing of Protection: no damage at all for a few seconds (the power-up bubble's shield_until)
			if target != null:
				target.shield_until = maxf(target.shield_until, now + float(spec.durationMs))
				_label(target, "BENDICIÓN DE PROTECCIÓN", "#ffe08a")
		"pwshield":
			if target != null:
				target.absorb = spec.heal
				target.absorb_until = now + 10000
				_label(target, "ESCUDO DIVINO", "#ffe08a")
		"renew":
			if target != null:
				target.hot_until = now + 6000
				target.hot_hps = spec.heal
				target.hot_by = u
				_label(target, "RENOVAR", "#5cff8a")
		"dispel", "naturescure", "cleanse":
			if target != null:
				target.curses.clear()
				for f in ["stun_until", "root_until", "silence_until", "incap_until", "fear_until", "slow_until", "mortal_until", "marked_until", "burn_until", "chill_until", "exposed_until"]:
					target.set(f, 0.0)
				_label(target, "DISIPADO", "#ffffff")
		"scream":
			fx.append({"k": "scream", "x": u.x, "z": u.z, "r": spec.aoe})
			for e in _enemies_within(u, u.x, u.z, spec.aoe):
				e.fear_x = u.x
				e.fear_z = u.z
				_cc(e, "fear", spec.ccMs, now)
		"hymn":
			fx.append({"k": "hymn", "x": u.x, "z": u.z, "r": spec.aoe})
			for a in units:
				if a.alive and a.team == u.team and _dist(a, u) <= spec.aoe:
					_heal(a, spec.heal, u, now)
		# ---- druid
		"rejuv":
			if target != null:
				target.hot_until = now + float(spec.durationMs)
				target.hot_hps = spec.heal
				target.hot_by = u
				_label(target, "REJUVENECIMIENTO", "#7ddc5a")
		"ironbark":
			if target != null:
				target.wall_until = maxf(target.wall_until, now + spec.ccMs)
				_label(target, "CORTEZA FÉRREA", "#b08a4a")
		"cyclone":
			if target != null and target.alive and Rules.has_los(map, u, target) and _dist(target, u) <= spec.range + 1:
				_cc(target, "incap", spec.ccMs, now, "cyclone")
			else:
				_error(u, "El objetivo escapó")
		"tranquility":
			fx.append({"k": "hymn", "x": u.x, "z": u.z, "r": spec.aoe})
			for a in units:
				if a.alive and a.team == u.team and _dist(a, u) <= spec.aoe:
					_heal(a, spec.heal, u, now)
					a.hot_until = maxf(a.hot_until, now + float(spec.durationMs))
					a.hot_hps = spec.hotHps
					a.hot_by = u
		# ---- ki fighter
		"punch":
			if target != null: _damage(target, spec.dmg, u, now, id)
		"flashstep":
			if target != null:
				var fp := {"x": target.x - sin(target.rot) * 1.3, "z": target.z - cos(target.rot) * 1.3}
				Rules.collide(fp, map)
				fx.append({"k": "blink", "x0": u.x, "z0": u.z, "x1": fp.x, "z1": fp.z})
				u.x = fp.x
				u.z = fp.z
				u.dash_left = 0.0
				u.rot = atan2(target.x - u.x, target.z - u.z)
		"kiguard":
			u.absorb = maxf(u.absorb, float(spec.absorb))
			u.absorb_until = now + float(spec.durationMs)
			_label(u, "GUARDIA DE KI", "#9fe8ff")
		"awaken":
			u.haste_until = maxf(u.haste_until, now + spec.ccMs)
			u.crit_until = maxf(u.crit_until, now + spec.ccMs)
			fx.append({"k": "awaken", "id": u.id, "ms": spec.ccMs})
			_label(u, "¡DESPERTAR!", "#ffd84a")
		"palm":
			if target != null:
				_damage(target, spec.dmg, u, now, id)
				if not target.cast.is_empty():
					_interrupt(target, now)
					_cc(target, "silence", spec.ccMs, now)
				var push := Vector2(target.x - u.x, target.z - u.z).normalized()
				Rules.knock(target, push, 6.0, 0.5)
		"kiwave":
			var beam: Vector2 = dir * float(spec.range)
			fx.append({"k": "beam", "x": u.x, "z": u.z, "dx": dir.x, "dz": dir.y, "r": spec.range})
			for e in _enemies_within(u, u.x + beam.x * 0.5, u.z + beam.y * 0.5, spec.range * 0.5 + 1.5):
				if Rules.segment_circle(u.x, u.z, u.x + beam.x, u.z + beam.y, e.x, e.z, Rules.PLAYER_R + 1.0) >= 0.0:
					_damage(e, spec.dmg, u, now, id)
		# ---- wizard (young duelist)
		"wardshield":
			u.absorb = maxf(u.absorb, float(spec.absorb))
			u.absorb_until = now + float(spec.durationMs)
			_label(u, "ESCUDO ENCANTADO", "#bfe0ff")
		"broom":
			var bt := 0.3
			u.dash_left = bt
			u.dash_vx = dir.x * spec.dist / bt
			u.dash_vz = dir.y * spec.dist / bt
			u.root_until = 0.0
			u.haste_until = maxf(u.haste_until, now + spec.ccMs)
			_label(u, "¡A LA ESCOBA!", "#ffd98a")
		"confuse":
			if target != null and target.alive and Rules.has_los(map, u, target) and _dist(target, u) <= spec.range + 1:
				_cc(target, "incap", spec.ccMs, now, "disorient")
			else:
				_error(u, "El objetivo escapó")
		"guardian":
			fx.append({"k": "hymn", "x": u.x, "z": u.z, "r": spec.aoe})
			fx.append({"k": "scream", "x": u.x, "z": u.z, "r": spec.aoe})
			for e in _enemies_within(u, u.x, u.z, spec.aoe):
				e.fear_x = u.x
				e.fear_z = u.z
				_cc(e, "fear", spec.ccMs, now)
			for a in units:
				if a.alive and a.team == u.team and _dist(a, u) <= spec.aoe * 2.0:
					_heal(a, spec.heal, u, now)
		# ---- crack (footballer)
		"nutmeg":
			if target != null:
				_damage(target, spec.dmg, u, now, id)
				var behind := {"x": target.x - sin(target.rot) * 1.4, "z": target.z - cos(target.rot) * 1.4}
				Rules.collide(behind, map)
				fx.append({"k": "blink", "x0": u.x, "z0": u.z, "x1": behind.x, "z1": behind.z})
				u.x = behind.x
				u.z = behind.z
				u.dash_left = 0.0
				_cc(target, "incap", spec.ccMs, now, "disorient")
				_label(target, "¡CAÑO!", "#7fc8ff")
		"dribble":
			var t := 0.24
			u.dash_left = t
			u.dash_vx = dir.x * spec.dist / t
			u.dash_vz = dir.y * spec.dist / t
			u.slow_until = 0.0
			u.haste_until = maxf(u.haste_until, now + spec.ccMs)
			_label(u, "GAMBETA", "#7fc8ff")
		"onetwo":
			if target != null:
				if target != u:
					var to := Vector2(target.x - u.x, target.z - u.z)
					var stop := maxf(0.0, to.length() - 1.4)
					u.dash_left = stop / 30.0
					u.dash_vx = to.normalized().x * 30.0
					u.dash_vz = to.normalized().y * 30.0
					target.haste_until = maxf(target.haste_until, now + spec.ccMs)
				u.haste_until = maxf(u.haste_until, now + spec.ccMs)
				_label(target, "¡PARED!", "#7fc8ff")
		# ---- ronin
		"tempest":
			var reach: Vector2 = dir * float(spec.range)
			for e in _enemies_within(u, u.x + reach.x * 0.5, u.z + reach.y * 0.5, spec.range * 0.5 + 1.0):
				if Rules.segment_circle(u.x, u.z, u.x + reach.x, u.z + reach.y, e.x, e.z, Rules.PLAYER_R + 0.6) >= 0.0:
					_damage(e, spec.dmg, u, now, id)
			fx.append({"k": "tempest", "x": u.x, "z": u.z, "dx": dir.x, "dz": dir.y, "r": spec.range})
			u.tempest_stacks = u.tempest_stacks + 1 if now - u.tempest_at < 6000.0 else 1
			u.tempest_at = now
			if u.tempest_stacks >= 3:
				u.tempest_stacks = 0
				_spawn_proj(u, TORNADO, dir)
				_label(u, "¡TORNADO!", "#9fe8ff")
		"windwall":
			var c := Vector2(u.x, u.z) + dir * 2.5
			var side := Vector2(-dir.y, dir.x) * 3.5
			windwalls.append({"team": u.team, "x0": c.x - side.x, "z0": c.y - side.y, "x1": c.x + side.x, "z1": c.y + side.y, "until": now + float(spec.durationMs)})
			fx.append({"k": "windwall", "x": c.x, "z": c.y, "dx": dir.x, "dz": dir.y, "hw": 3.5, "ms": spec.durationMs})
		"sweep":
			if target != null:
				_damage(target, spec.dmg, u, now, id)
				var through := Vector2(target.x - u.x, target.z - u.z).normalized()
				var end := {"x": target.x + through.x * 1.6, "z": target.z + through.y * 1.6}
				Rules.collide(end, map)
				fx.append({"k": "charge", "id": u.id, "x0": u.x, "z0": u.z, "x1": end.x, "z1": end.z})
				var travel := Vector2(end.x - u.x, end.z - u.z)
				u.dash_left = travel.length() / 34.0
				u.dash_vx = travel.x / maxf(u.dash_left, 1e-3)
				u.dash_vz = travel.y / maxf(u.dash_left, 1e-3)
		"flow":
			u.absorb = maxf(u.absorb, float(spec.absorb))
			u.absorb_until = now + float(spec.durationMs)
			_label(u, "ESCUDO DE VIENTO", "#9fe8ff")
		"lastbreath":
			if target != null:
				var p := {"x": target.x - sin(target.rot) * 1.2, "z": target.z - cos(target.rot) * 1.2}
				Rules.collide(p, map)
				fx.append({"k": "blink", "x0": u.x, "z0": u.z, "x1": p.x, "z1": p.z})
				u.x = p.x
				u.z = p.z
				u.dash_left = 0.0
				_damage(target, spec.dmg, u, now, id)
				_cc(target, "stun", spec.ccMs, now)
				_label(target, "¡AL AIRE!", "#9fe8ff")
		# ---- counter-terrorist
		"flashbang":
			var fp := {"x": u.x + dir.x * aim_dist, "z": u.z + dir.y * aim_dist}
			Rules.collide(fp, map, 0.3)
			fx.append({"k": "flash", "x": fp.x, "z": fp.z, "r": spec.aoe})
			for e in _enemies_within(u, fp.x, fp.z, spec.aoe):
				_cc(e, "incap", spec.ccMs, now, "blind")
		"kevlar":
			u.absorb = maxf(u.absorb, float(spec.absorb))
			u.absorb_until = now + float(spec.durationMs)
			_label(u, "KEVLAR", "#8fb4d8")
		"knife":
			u.haste_until = maxf(u.haste_until, now + spec.ccMs)
			u.root_until = 0.0
			u.slow_until = 0.0
			_label(u, "CUCHILLO EN MANO", "#d8e0ea")
		# ---- rogue
		"cheapshot":
			if target != null: _cc(target, "stun", spec.ccMs * (1.6 if from_stealth else 1.0), now)
		"blind":
			if target != null: _cc(target, "incap", spec.ccMs, now, "blind")
		"vanish":
			u.stealth_until = now + spec.ccMs
			u.revealed_until = 0.0
			u.root_until = 0.0
			u.slow_until = 0.0
			u.haste_until = maxf(u.haste_until, now + 4000)  # sprint out of stealth
		"deathmark":
			if target != null:
				# Shadowstep behind the target, then mark it.
				var p := {"x": target.x - sin(target.rot) * 1.3, "z": target.z - cos(target.rot) * 1.3}
				Rules.collide(p, map)
				fx.append({"k": "blink", "x0": u.x, "z0": u.z, "x1": p.x, "z1": p.z})
				u.x = p.x
				u.z = p.z
				u.dash_left = 0.0
				target.marked_until = now + spec.ccMs
				_label(target, "MARCADO", "#ff3b3b")
	_cast_emp = false
	_hit_emp = false


func _new_id() -> int:
	_next_id += 1
	return _next_id


func _spawn_proj(u: ArenaUnit, spec: Dictionary, dir: Vector2, target: ArenaUnit = null) -> void:
	var s: float = spec.projSpeed
	projs.append({
		"id": _new_id(), "owner": u, "spec": spec, "x": u.x + dir.x * 0.6, "z": u.z + dir.y * 0.6,
		"vx": dir.x * s, "vz": dir.y * s, "left": spec.range + (6.0 if target != null else 0.0), "target": target,
		"emp": _cast_emp, "hits": [],
	})


func _enemies_within(u: ArenaUnit, x: float, z: float, r: float) -> Array[ArenaUnit]:
	var out: Array[ArenaUnit] = []
	for e in units:
		if e.alive and e.team != u.team and Vector2(e.x - x, e.z - z).length() <= r + Rules.PLAYER_R:
			out.append(e)
	return out


# ---------------------------------------------------------------- combat

## True while a periodic effect (curse, burn) is dealing its tick: clients show the number but no flash, impact or sound.
var _dot_tick := false
## Ability combos that work for any team: Pyroblast crits a stunned target, a trap holds a feared target for a moment.
var combos := true
const COMBO_FREEZE_MS := 1000.0
## Warrior shield blocks: front hemisphere (including sides) 30%, rear 5%.
## Host-owned configuration; independent RNG so combat rolls cannot be supplied by clients.
var block_front := 0.30
var block_rear := 0.05
var block_rng := RandomNumberGenerator.new()
## Chance effects of abilities (Frostbolt's root).
var proc_rng := RandomNumberGenerator.new()
## Team -> effects of its class pairs (Synergies).
var synergies := {}
## The cast being executed is an "every Nth" one (its projectiles carry it), and the hit being dealt comes from one.
var _cast_emp := false
var _hit_emp := false


func block_chance(defender: ArenaUnit, attacker: ArenaUnit, now: float, ability: String) -> float:
	if defender.cls != "warrior" or attacker == null or attacker.team == defender.team or _dot_tick:
		return 0.0
	if now < defender.stun_until or now < defender.incap_until or now < defender.fear_until:
		return 0.0
	if not SpellSchools.explicit(ability) or SpellSchools.school_of(ability) != "physical":
		return 0.0
	var incoming := Vector2(attacker.x - defender.x, attacker.z - defender.z)
	if incoming.length_squared() < 0.0001:
		return 0.0
	var facing := Vector2(sin(defender.rot), cos(defender.rot))
	var bonus := float(defender.spec().get("block", 0.0))
	return clampf((block_front if facing.dot(incoming.normalized()) >= 0.0 else block_rear) + bonus, 0.0, 1.0)


## Crit chance of a unit: the global base plus its class/spec bonus (assassins crit a lot).
func crit_chance(u: ArenaUnit) -> float:
	return float(C.CRIT_CHANCE) + float(u.spec().get("crit", 0.0))


func _damage(t: ArenaUnit, amount: float, src: ArenaUnit, now: float, ability := "") -> void:
	if not t.alive or amount <= 0 or phase != "fight":
		return
	if god and t.peer != 0:
		return
	if src != null and src.dmg_mult != 1.0:
		amount *= src.dmg_mult
	if now < t.shield_until:
		if src != null: fx.append({"k": "absorb", "id": t.id})
		_ev("absorb", now, {"t": t.id, "by": src.id if src != null else -1, "ability": ability})
		return
	var chance := block_chance(t, src, now, ability)
	if chance > 0.0 and block_rng.randf() < chance:
		fx.append({"k": "block", "id": t.id, "by": src.id})
		_ev("block", now, {"t": t.id, "by": src.id, "ability": ability})
		return
	var crit := false
	var a: Dictionary = src.ability_by_id(ability) if src != null and ability != "" and not _dot_tick else {}
	if src != null:
		if not a.is_empty():
			amount *= _talent_bonus(a, src, t, now)
		crit = now < src.crit_until or randf() < crit_chance(src)
		if not a.is_empty() and not crit:
			crit = (_hit_emp and str(a.get("nthEffect", "")) == "crit") or (a.get("critVsSlowed", false) and _hindered(t, now)) or (combos and ability == "pyro" and now < t.stun_until)
		if crit: amount *= C.CRIT_MULT
		if crit and not _dot_tick: src.crit_streak += 1
		if not _dot_tick and t.team != src.team and SpellSchools.explicit(ability) and SpellSchools.school_of(ability) == "physical":
			amount *= _synergy_physical(src, t, now)
		var armor := float(t.spec().get("armor", 0.0))
		if armor > 0.0 and SpellSchools.explicit(ability) and SpellSchools.school_of(ability) == "physical":
			amount *= 1.0 - armor  # armor: physical hits only (not magic, not periodic effects)
		t.stealth_until = 0.0  # getting hit breaks stealth
		if now < t.wall_until: amount *= 0.4
		if now < t.marked_until: amount *= 1.4
		if t.pact_absorb > 0 and now < t.pact_until:
			var soaked := minf(t.pact_absorb, amount)
			t.pact_absorb -= soaked
			amount -= soaked
			if amount <= 0:
				fx.append({"k": "absorb", "id": t.id})
				_ev("absorb", now, {"t": t.id, "by": src.id, "ability": ability})
				return
		if t.absorb > 0 and now < t.absorb_until:
			var soaked := minf(t.absorb, amount)
			t.absorb -= soaked
			amount -= soaked
			if amount <= 0:
				fx.append({"k": "absorb", "id": t.id})
				_ev("absorb", now, {"t": t.id, "by": src.id, "ability": ability})
				return
		if now < t.fear_until:
			t.fear_dmg += amount
			if t.fear_dmg > 40:
				t.fear_until = 0.0  # fear breaks after enough damage
				_ev("cc_break", now, {"t": t.id, "cat": "fear", "by": src.id})
	t.hp -= amount
	_ev("dmg", now, {"t": t.id, "by": src.id if src != null else -1, "amt": amount, "ability": ability, "dot": _dot_tick, "crit": crit})
	if now < t.incap_until and now >= t.incap_solid_until:
		t.incap_until = 0.0  # sheep / freeze / blind break on damage
		_ev("cc_break", now, {"t": t.id, "cat": "incap", "by": src.id if src != null else -1})
	if not t.cast.is_empty() and int(t.cast.get("pushes", 0)) < int(C.PUSHBACK_MAX) and not t.ability(t.cast.slot).get("noPushback", false):
		t.cast.ends_at += float(C.PUSHBACK_MS)  # WoW pushback: each hit delays the cast, at most twice
		t.cast.pushes = int(t.cast.get("pushes", 0)) + 1
	if src != null:
		src.dmg += amount
		src.ult = minf(100, src.ult + amount * C.ULT_PER_DAMAGE * float(a.get("ultGain", 1.0)))
		t.ult = minf(100, t.ult + amount * C.ULT_PER_DAMAGE_TAKEN)
		t.last_hit_by = src.id
		t.last_hit_at = now
		t.revealed_until = maxf(t.revealed_until, now + 1000)
		fx.append({"k": "hit", "id": t.id, "amt": roundi(amount), "x": t.x, "z": t.z, "crit": crit, "by": src.id, "ability": ability, "dot": _dot_tick})
		if practice and src.peer != 0 and t.dummy != "" and t.team != src.team:
			meter_for(src).record_damage(ability, amount, crit, now)
		if not a.is_empty() and t.team != src.team:
			_after_hit(t, src, a, amount, now)
	if t.hp <= 0:
		if practice:
			_practice_down(t, now)
			return
		_die(t, now)


## Like in WoW, a sheep quickly regains health (POLY_HEAL_PCT of its max per second, after Mortal Strike and dampening):
## the price of a long, safe crowd control. Nobody gets credit or ultimate charge for it.
func _sheep_heal(u: ArenaUnit, now: float) -> void:
	if not u.alive or phase != "fight":
		return
	var amount := u.max_hp * float(C.POLY_HEAL_PCT) * _dt
	if now < u.mortal_until: amount *= 1.0 - u.mortal_pct
	amount *= 1.0 - _damp(now)
	var real := minf(u.max_hp - u.hp, amount)
	if real > 0.0:
		u.hp += real
		u.poly_heal_acc += real
	u.poly_heal_t += _dt
	if u.poly_heal_t >= 1.0:
		_sheep_heal_number(u)


func _sheep_heal_number(u: ArenaUnit) -> void:
	if u.poly_heal_acc >= 1.0:
		fx.append({"k": "heal", "id": u.id, "amt": roundi(u.poly_heal_acc)})
	u.poly_heal_acc = 0.0
	u.poly_heal_t = 0.0


func _heal(t: ArenaUnit, amount: float, src: ArenaUnit, now: float, quiet := false) -> void:
	if not t.alive or phase != "fight":
		return
	amount *= 1.0 + _synergy(t.team, "heal_%s_%s" % [src.cls, t.cls])
	if now < t.mortal_until: amount *= 1.0 - t.mortal_pct  # Mortal Strike
	amount *= 1.0 - _damp(now)
	var real := minf(t.max_hp - t.hp, amount)
	if real <= 0:
		return
	t.hp += real
	src.healed += real
	if practice and src.peer != 0:
		meter_for(src).record_heal(real, now)
	src.ult = minf(100, src.ult + real * C.ULT_PER_DAMAGE * 0.5)
	if not quiet: fx.append({"k": "heal", "id": t.id, "amt": roundi(real)})
	_ev("heal", now, {"t": t.id, "by": src.id, "amt": real})


func _die(t: ArenaUnit, now: float) -> void:
	t.alive = false
	t.deaths += 1
	t.hp = 0.0
	t.cast = {}
	t.dash_left = 0.0
	if t.dummy == "crate":
		t.dormant = true  # gone: no corpse
		fx.append({"k": "crate_break", "id": t.id, "x": t.x, "z": t.z})
	else:
		fx.append({"k": "death", "id": t.id})
	_ev("death", now, {"t": t.id})
	for o in units:
		if o.auto_target == t.id:
			o.auto_on = false
	if practice:
		return  # no rounds and no kill feed in a lesson
	var killer: ArenaUnit = null
	if t.last_hit_by >= 0 and now - t.last_hit_at < 8000:
		killer = unit_by_id(t.last_hit_by)
	if killer != null: killer.kills += 1
	broadcasts.append({
		"t": "kill", "killer": killer.name if killer else null, "killerTeam": killer.team if killer else null,
		"victim": t.name, "victimTeam": t.team,
	})
	var red_alive := units.any(func(u): return u.team == "red" and u.alive)
	var blue_alive := units.any(func(u): return u.team == "blue" and u.alive)
	if not red_alive or not blue_alive:
		_end_round("red" if red_alive else ("blue" if blue_alive else ""), now)


const CC_LABEL := {
	"stun": ["ATURDIDO", "#ffd166"], "root": ["ENRAIZADO", "#7fdbff"], "silence": ["SILENCIADO", "#c77dff"],
	"incap": ["INCAPACITADO", "#ffffff"], "fear": ["ATERRORIZADO", "#c77dff"],
}
const INCAP_LABEL := {"disorient": ["DESORIENTADO", "#ffb060"], "poly": ["¡OVEJA!", "#ffffff"], "freeze": ["CONGELADO", "#9be7ff"], "blind": ["CEGADO", "#b0a8c0"], "cyclone": ["CICLÓN", "#9fe8a0"]}


func _cc(t: ArenaUnit, cat: String, base_ms: float, now: float, incap_kind := "poly") -> void:
	if not t.alive or (god and t.peer != 0) or t.dummy == "crate":
		return
	if now < t.shield_until or now < t.storm_until:
		_label(t, "INMUNE", "#7fdbff")
		_ev("cc_immune", now, {"t": t.id, "cat": cat, "why": "shield" if now < t.shield_until else "storm"})
		return
	var r := Rules.apply_dr(t.dr.get(cat, {}), base_ms, now)
	t.dr[cat] = r.dr
	var ms: float = r.ms
	if ms <= 0:
		_label(t, "INMUNE", "#aaaaaa")
		_ev("cc_immune", now, {"t": t.id, "cat": cat, "why": "dr"})
		return
	_ev("cc", now, {"t": t.id, "cat": cat, "kind": incap_kind if cat == "incap" else "", "ms": ms, "dr": ms / base_ms})
	var until := now + ms
	match cat:
		"stun": t.stun_until = maxf(t.stun_until, until)
		"root": t.root_until = maxf(t.root_until, until)
		"silence": t.silence_until = maxf(t.silence_until, until)
		"incap":
			t.incap_until = maxf(t.incap_until, until)
			t.incap_kind = incap_kind
		"fear":
			t.fear_until = maxf(t.fear_until, until)
			t.fear_dmg = 0.0
	if cat != "silence": t.dash_left = 0.0
	if cat != "root" and not t.cast.is_empty(): _interrupt(t, now)
	var lbl: Array = INCAP_LABEL[incap_kind] if cat == "incap" else CC_LABEL[cat]
	_label(t, lbl[0], lbl[1])


func _interrupt(t: ArenaUnit, now: float) -> void:
	if t.cast.is_empty():
		return
	if t.dummy == "caster":
		t.dummy_next = now + PracticeYard.INTERRUPT_GAP_MS
	t.cds[t.cast.slot] = maxf(t.cds[t.cast.slot], now + INTERRUPT_LOCK_MS)
	_ev("interrupt", now, {"t": t.id, "ability": str(t.ability(t.cast.slot).id)})
	t.cast = {}
	_label(t, "INTERRUMPIDO", "#ff6b6b")


func _label(t: ArenaUnit, text: String, color: String) -> void:
	fx.append({"k": "label", "id": t.id, "text": text, "color": color})


## WoW-style auto-attack: needs the toggle, a visible hostile target in reach and in front of you.
func _auto_attack(u: ArenaUnit, now: float) -> void:
	if not u.auto_on:
		return
	var t := _lock_target(u, u.auto_target, now)
	if t == null:
		u.auto_on = false  # target died, vanished or is no longer valid
		return
	if not u.cast.is_empty() or now < u.cds[0] or now < u.stealth_until:
		return
	var spec := u.ability(0)
	var melee: bool = spec.get("melee", false)
	var problem := ""
	if melee:
		problem = _melee_problem(u, t, spec.range)
	elif _dist(t, u) > spec.range + 1 or not Rules.has_los(map, u, t):
		problem = "Fuera de alcance"
	elif not _facing(u, t, -0.3):
		problem = "Tenés que mirar al objetivo"
	if problem != "":
		if now - u.auto_warn_at > 1500.0:  # the auto-attack is on but cannot land: say why, softly, not every swing
			u.auto_warn_at = now
			_error(u, problem)
		return
	cast_ability(u, 0, t.x, t.z, now, t.id)


# ---------------------------------------------------------------- simulation

func tick(now: float) -> void:
	_last_now = now
	for u in units:
		if u.brain != null:
			u.brain.think(self, u, now)
	if practice:
		_practice_pre(now)
	if stage != null:
		stage.step(self, now)
	if phase == "prep" and now >= phase_ends_at:
		phase = "fight"
		fight_start = now
		_next_power_at = now + C.POWER_FIRST_MS
	elif phase == "between" and now >= phase_ends_at:
		round_n += 1
		_reset_round(now)
	elif phase == "over" and now >= phase_ends_at:
		done = true
		return
	var fighting := phase == "fight"
	var dt := _dt
	map.apply_state(phase != "prep", (now - fight_start) if fighting else 0.0)

	for u in units:
		if not u.alive:
			continue
		if not u.charges.is_empty():
			_refill_charges(u, now)
		if fighting:
			u.ult = minf(100, u.ult + C.ULT_PER_SECOND * dt)
			if not u.cast.is_empty() and u.dummy == "": _progress_cast(u, now)
			if u.brain == null and u.dummy == "": _auto_attack(u, now)
		var frozen := now < u.stun_until or now < u.incap_until
		var feared := now < u.fear_until
		var can_move := Rules.can_walk_in(phase) and not frozen and now >= u.root_until and (u.cast.is_empty() or feared)
		var movement := u.input
		if feared:
			# Panicked: run away from where the scream came from.
			u.cast = {}
			movement = Vector2(u.x - u.fear_x, u.z - u.fear_z)
			if movement.length() < 0.01: movement = Vector2(0.01, 0)
		var speed: float = u.spec().speed * (1.0 - u.slow_pct if now < u.slow_until else 1.0) * (C.HASTE_MULT if now < u.haste_until else 1.0)
		# Players walk backwards slower. Bots and dummies always look at their target, so their facing says nothing
		# about how they would really run: they keep full speed.
		if u.brain == null and u.dummy == "" and not feared:
			speed *= Rules.facing_speed(movement, u.rot)
		Rules.step_mover(u, movement.x, movement.y, dt, speed, can_move, map)
		if feared: u.rot = atan2(u.x - u.fear_x, u.z - u.fear_z)
		elif not frozen: u.rot = atan2(u.aim_x - u.x, u.aim_z - u.z)
		if fighting:
			_step_effects(u, now)
			if u.spec().has("barrier"): _step_barrier(u, now)
	var alive_units := units.filter(func(u): return u.alive)
	Rules.separate(alive_units)
	for u in alive_units:
		Rules.collide(u, map)

	if fighting and not practice and now - fight_start > float(C.ROUND_LIMIT_MS):
		# Stalled round (someone hiding or unreachable): the team with more health left wins; equal health is a draw.
		var hp := {"red": 0.0, "blue": 0.0}
		for u in alive_units:
			hp[u.team] += u.hp
		var limit_winner: String = "red" if hp.red > hp.blue + 1.0 else ("blue" if hp.blue > hp.red + 1.0 else "")
		limit_rounds += 1
		if limit_winner != "":
			var team_max := {"red": 0.0, "blue": 0.0}
			for u in units:
				team_max[u.team] += u.max_hp
			var pr: float = hp.red / maxf(team_max.red, 1.0)
			var pb: float = hp.blue / maxf(team_max.blue, 1.0)
			limit_pct_decided += 1
			if absf(pr - pb) < 0.001:
				limit_pct_ties += 1
			elif ("red" if pr > pb else "blue") != limit_winner:
				limit_pct_differs += 1
			var mx := {"red": 0.0, "blue": 0.0}
			for u in units:
				mx[u.team] += u.max_hp
			if absf(mx.red - mx.blue) > 1.0:
				limit_decided += 1
				if (mx[limit_winner] > mx.red + mx.blue - mx[limit_winner]):
					limit_hi_hp_wins += 1
		_end_round(limit_winner, now)
		return
	if fighting:
		for u in alive_units:
			var hz := Rules.hazard_at(map, u.x, u.z)
			if not hz.is_empty():
				if hz.dps > 0: _damage(u, hz.dps * dt, null, now)
				if hz.hps > 0: u.hp = minf(u.max_hp, u.hp + hz.hps * dt)
		_step_projectiles(now)
		_step_aoes(now)
		_step_traps(now)
		_step_powers(now)


## Heal-over-time and Bladestorm pulses.
func _step_effects(u: ArenaUnit, now: float) -> void:
	for key in u.curses.keys():
		var dot: Dictionary = u.curses[key]
		if now >= dot.until:
			u.curses.erase(key)
			continue
		if now >= dot.next:
			dot.next += 500.0
			_dot_tick = true
			var mark := (1.0 + u.curse_mark) if now < u.curse_mark_until and dot.ability != "poison" else 1.0
			_damage(u, dot.dps * 0.5 * mark, unit_by_id(dot.owner), now, dot.ability)
			_dot_tick = false
			if not u.alive: return
	if now < u.burn_until and u.burn_by != null and now >= u.burn_next:
		u.burn_next += 500.0
		_dot_tick = true
		_damage(u, u.burn_dps * 0.5, u.burn_by, now, "burn")
		_dot_tick = false
		if not u.alive:
			return
	if now < u.hot_until and u.hot_by != null:
		_heal(u, u.hot_hps * _dt, u.hot_by, now, true)
	if now < u.incap_until and u.incap_kind == "poly":
		_sheep_heal(u, now)
	elif u.poly_heal_t > 0.0:
		_sheep_heal_number(u)  # the sheep ended or broke: show what it healed
	if now < u.storm_until and now >= u.storm_next:
		u.storm_next = now + 500
		var spec := u.ability(int(C.ULT_SLOT))
		fx.append({"k": "swing", "id": u.id, "heavy": true})
		for e in _enemies_within(u, u.x, u.z, spec.range):
			_damage(e, spec.dmg, u, now, spec.id)


## Frost mage passive: an absorb shield that comes back `cdMs` after it breaks (up at the start of every round).
func _step_barrier(u: ArenaUnit, now: float) -> void:
	var b: Dictionary = u.spec().barrier
	if u.barrier_on:
		if u.absorb <= 0.0 or now >= u.absorb_until:
			u.barrier_on = false
			u.barrier_ready = now + float(b.cdMs)
		return
	if now >= u.barrier_ready:
		u.barrier_on = true
		u.absorb = maxf(u.absorb if now < u.absorb_until else 0.0, float(b.absorb))
		u.absorb_until = maxf(u.absorb_until, now + 600000.0)
		_label(u, "ESCUDO DE ESCARCHA", "#9be7ff")


func _apply_curse(t: ArenaUnit, src: ArenaUnit, spec: Dictionary, now: float, quiet := false) -> void:
	if not t.alive or now < t.shield_until: return
	var key := "%d:%s" % [src.id, spec.id]
	var old: Dictionary = t.curses.get(key, {})
	t.curses[key] = {"owner": src.id, "ability": spec.id, "dps": float(spec.dotDps),
		"until": now + float(spec.durationMs),
		"next": old.next if not old.is_empty() and now < old.until else now + 500.0}
	if not quiet: _label(t, spec.name.to_upper(), "#b18ae8")


func _progress_cast(u: ArenaUnit, now: float) -> void:
	var c := u.cast
	var spec := u.ability(c.slot)
	var moving: bool = u.input.length() > 0.1 and not spec.get("castMove", false)
	if moving or _can_act(u, spec, now) != "":
		u.cast = {}
		if moving and now >= u.fear_until:
			_error(u, "%s cancelado: te moviste" % spec.name)
			_ev("cast_cancel", now, {"u": u.id, "ability": str(spec.id), "why": "moved"})
		return
	if c.lock >= 0:
		var t := _lock_target(u, c.lock, now)
		if t != null:
			c.ax = t.x
			c.az = t.z
		else:
			c.lock = -1  # target vanished: released as a skillshot
	if c.target_id >= 0:
		var t := unit_by_id(c.target_id)
		if t == null or not t.alive or not team_can_see(u.team, t, now):
			u.cast = {}
			_error(u, "Perdiste el objetivo")
			return
		c.ax = t.x
		c.az = t.z
	if now >= c.ends_at:
		u.cast = {}
		_execute(u, c.slot, c.ax, c.az, c.target_id, now, c.lock)


func _step_projectiles(now: float) -> void:
	var keep: Array = []
	for p in projs:
		var spec: Dictionary = p.spec
		var t_lock: ArenaUnit = p.target
		if t_lock != null:
			if t_lock.alive and team_can_see(p.owner.team, t_lock, now):
				var to: Vector2 = Vector2(t_lock.x - p.x, t_lock.z - p.z).normalized() * spec.projSpeed
				p.vx = to.x
				p.vz = to.y
			else:
				p.target = null  # lost (stealth, bush, death): keeps flying straight
		var nx: float = p.x + p.vx * _dt
		var nz: float = p.z + p.vz * _dt
		if _blocked_by_windwall(p.owner.team, p.x, p.z, nx, nz, now):
			fx.append({"k": "absorb_wall", "x": nx, "z": nz})
			continue
		var wall_t := Rules.obstacle_hit(map, p.x, p.z, nx, nz, spec.projR * 0.4)
		var hit: ArenaUnit = null
		var hit_t := INF
		for u in units:
			if not u.alive or u.team == p.owner.team or u.id in p.get("hits", []):
				continue
			var t := Rules.segment_circle(p.x, p.z, nx, nz, u.x, u.z, Rules.PLAYER_R + spec.projR)
			if t >= 0 and t < hit_t:
				hit = u
				hit_t = t
		if hit != null and (wall_t < 0 or hit_t <= wall_t):
			_hit_emp = p.get("emp", false)
			_on_proj_hit(p, hit, now)
			var pierce: bool = _hit_emp and str(spec.get("nthEffect", "")) == "pierce"
			_hit_emp = false
			if not pierce:
				continue
			p.hits.append(hit.id)  # piercing shot: keeps flying through
			p.target = null
		if wall_t >= 0:
			if spec.id in ["fireball", "pyro", "frostbolt", "icelance"]:
				fx.append({"k": "boom", "x": p.x + (nx - p.x) * wall_t, "z": p.z + (nz - p.z) * wall_t, "r": 0.8, "kind": spec.id})
			continue
		p.x = nx
		p.z = nz
		p.left -= spec.projSpeed * _dt
		if p.left > 0 and absf(p.x) < map.half_x and absf(p.z) < map.half_z:
			keep.append(p)
	projs = keep


## Ronin's Steel Tempest tornado: a slow, wide projectile that leaves the first enemy it reaches in the air.
const TORNADO := {"id": "tornado", "name": "Tornado", "range": 12, "dmg": 26, "projSpeed": 22, "projR": 0.7, "ccMs": 1000, "physical": true}


## A projectile of `team` crossing an enemy wind wall this step (segment against segment).
func _blocked_by_windwall(team: String, ax: float, az: float, bx: float, bz: float, now: float) -> bool:
	if windwalls.is_empty():
		return false
	windwalls = windwalls.filter(func(w): return now < w.until)
	for w in windwalls:
		if w.team == team:
			continue
		var p := Vector2(ax, az)
		var r := Vector2(bx - ax, bz - az)
		var q := Vector2(w.x0, w.z0)
		var s := Vector2(w.x1 - w.x0, w.z1 - w.z0)
		var den := r.cross(s)
		if absf(den) < 1e-6:
			continue
		var t := (q - p).cross(s) / den
		var u := (q - p).cross(r) / den
		if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
			return true
	return false


func _on_proj_hit(p: Dictionary, t: ArenaUnit, now: float) -> void:
	var spec: Dictionary = p.spec
	match spec.id:
		"fireball", "pyro":
			fx.append({"k": "boom", "x": t.x, "z": t.z, "r": 1.6 if spec.id == "pyro" else 0.9, "kind": spec.id})
		"silence", "disarm":
			_interrupt(t, now)
			_cc(t, "silence", spec.ccMs, now)
		"stunbolt", "hammer":
			_cc(t, "stun", spec.ccMs, now)
		"conc":
			t.slow_until = now + spec.ccMs
			t.slow_pct = spec.slowPct
			var exposed := _synergy(p.owner.team, "concExposed")
			if exposed > 0.0:
				t.exposed_until = t.slow_until
				t.exposed_pct = exposed
			_label(t, "EXPUESTO" if exposed > 0.0 else "RALENTIZADO", "#4da3ff")
		"frostbolt":
			t.slow_pct = maxf(t.slow_pct if now < t.slow_until else 0.0, float(spec.slowPct))
			t.slow_until = maxf(t.slow_until, now + float(spec.ccMs))
			t.chill_until = t.slow_until
			if float(spec.get("rootChance", 0.0)) > 0.0 and proc_rng.randf() < float(spec.rootChance):
				_cc(t, "root", float(spec.rootMs), now)  # labels ENRAIZADO itself (and sets up Ice Lance's shatter)
			else:
				_label(t, "RALENTIZADO", "#4da3ff")
		"icelance":
			if now < t.root_until or (now < t.incap_until and t.incap_kind == "freeze"):
				_damage(t, float(spec.dmg) * float(spec.shatter), p.owner, now, spec.id)
				_label(t, "¡ASTILLADO!", "#bff4ff")
				_bounce(p, t, now)
				return
		"headshot", "awp":
			_label(t, "¡A LA CABEZA!", "#ff5a4a")
		"golazo":
			var kv := Vector2(p.vx, p.vz).normalized()
			Rules.knock(t, kv, 3.6, 0.42)
			_cc(t, "stun", spec.ccMs, now)
			_label(t, "¡GOLAZO!", "#ffd166")
			fx.append({"k": "boom", "x": t.x, "z": t.z, "r": 1.2, "kind": "golazo"})
		"tornado":
			_cc(t, "stun", spec.ccMs, now)
			_label(t, "¡AL AIRE!", "#9fe8ff")
		"volley":
			var v := Vector2(p.vx, p.vz).normalized()
			Rules.knock(t, v, 1.44, 0.28)
			if not t.cast.is_empty(): _interrupt(t, now)
	_damage(t, spec.get("dmg", 0.0), p.owner, now, spec.id)
	if spec.has("burnDps") and t.alive:
		t.burn_until = now + float(spec.burnMs)
		t.burn_dps = float(spec.burnDps)
		t.burn_next = now + 500.0
		t.burn_by = p.owner
	_bounce(p, t, now)


func _step_aoes(now: float) -> void:
	var keep: Array = []
	for a in aoes:
		var spec: Dictionary = a.spec
		if a.get("kind", "meteor") == "blizzard":
			if now >= a.until:
				continue
			if now >= a.next:
				a.next += float(spec.tickMs)
				for e in _enemies_within(a.owner, a.x, a.z, spec.aoe):
					_damage(e, spec.dmg, a.owner, now, spec.id)
					e.slow_pct = maxf(e.slow_pct if now < e.slow_until else 0.0, float(spec.slowPct))
					e.slow_until = maxf(e.slow_until, now + float(spec.ccMs))
			keep.append(a)
			continue
		if now < a.at:
			keep.append(a)
			continue
		fx.append({"k": "boom", "x": a.x, "z": a.z, "r": spec.aoe, "kind": spec.id})
		for e in _enemies_within(a.owner, a.x, a.z, spec.aoe):
			_damage(e, spec.dmg, a.owner, now, spec.id)
			_cc(e, "stun", spec.ccMs, now)
	aoes = keep


func _step_traps(now: float) -> void:
	var keep: Array = []
	for tr in traps:
		if now > tr.expires_at:
			continue
		if now < tr.armed_at:
			keep.append(tr)
			continue
		var victim: ArenaUnit = null
		for u in units:
			if u.alive and u.team != tr.owner.team and Vector2(u.x - tr.x, u.z - tr.z).length() < C.TRAP_RADIUS + Rules.PLAYER_R:
				victim = u
				break
		if victim == null:
			keep.append(tr)
			continue
		fx.append({"k": "trap", "x": tr.x, "z": tr.z})
		var trap: Dictionary = tr.owner.ability_by_id("trap")  # the owner's kit: talents may change the freeze
		var feared := combos and now < victim.fear_until
		_cc(victim, "incap", (trap if not trap.is_empty() else GameData.find_ability("hunter", "trap")).ccMs, now, "freeze")
		if feared and now < victim.incap_until:
			victim.incap_solid_until = now + COMBO_FREEZE_MS
			_label(victim, "¡COMBO!", "#ffd166")
	traps = keep


# ---------------------------------------------------------------- power-ups

func spawn_power(kind: String, x: float, z: float) -> void:
	powers.append({"id": _new_id(), "kind": kind, "x": x, "z": z})


func _step_powers(now: float) -> void:
	if now >= _next_power_at:
		_next_power_at = now + C.POWER_EVERY_MS
		var free := map.power_spots.filter(func(p): return not powers.any(func(q): return Vector2(q.x - p.x, q.z - p.z).length() < 1))
		if powers.size() < C.POWER_MAX and not free.is_empty():
			# Mirrored pairs so neither side is favoured.
			var kinds := GameData.powers.keys()
			var kind: String = kinds[randi() % kinds.size()]
			var spot: Dictionary = free[randi() % free.size()]
			spawn_power(kind, spot.x, spot.z)
			for p in free:
				if absf(p.x + spot.x) < 1e-6 and absf(p.z + spot.z) < 1e-6 and powers.size() < C.POWER_MAX:
					spawn_power(kind, p.x, p.z)
	var keep: Array = []
	for p in powers:
		var taker: ArenaUnit = null
		for u in units:
			if u.alive and Vector2(u.x - p.x, u.z - p.z).length() < 1.1:
				taker = u
				break
		if taker == null:
			keep.append(p)
		else:
			_apply_power(taker, p.kind, now)
	powers = keep


func _apply_power(u: ArenaUnit, kind: String, now: float) -> void:
	fx.append({"k": "power", "id": u.id, "kind": kind})
	_ev("gem", now, {"u": u.id, "kind": kind})
	if kind == "heal":
		var amt := minf(u.max_hp - u.hp, u.max_hp * 0.35)
		u.hp += amt
		fx.append({"k": "heal", "id": u.id, "amt": roundi(amt)})
		return
	var until: float = now + GameData.powers[kind].ms
	match kind:
		"crit": u.crit_until = until
		"stealth": u.stealth_until = until
		"shield": u.shield_until = until
		"haste": u.haste_until = until


# ---------------------------------------------------------------- practice arena

## Dampening is a round mechanic: the yard never has it, and a lesson only when it teaches it.
func _damp(now: float) -> float:
	if practice and (stage == null or not stage.damp):
		return 0.0
	return Rules.dampening(now - fight_start)


func meter_for(u: ArenaUnit) -> PracticeMeter:
	if not meters.has(u.id):
		meters[u.id] = PracticeMeter.new()
	return meters[u.id]


func _reset_dummy(u: ArenaUnit, now: float) -> void:
	u.reset_effects()
	u.alive = true
	u.x = u.home.x
	u.z = u.home.y
	u.vx = 0.0
	u.vz = 0.0
	u.dash_left = 0.0
	Rules.ground(u, map)
	u.hp = u.max_hp * (PracticeYard.ALLY_START if u.dummy == "ally" else 1.0)
	u.rot = 0.0 if u.team == "red" else PI
	u.patrol_dir = 1.0
	u.dummy_next = now + 1500.0
	u.cds.fill(0.0)
	u.charges.clear()


## A fighter "reaches 0": dummies refill (they never die), the player gets back up at the start point at once.
func _practice_down(t: ArenaUnit, now: float) -> void:
	if t.mortal:
		_die(t, now)
		return
	if t.dummy == "":
		_ev("down", now, {"t": t.id})
	if t.dummy != "":
		t.hp = t.max_hp * (PracticeYard.ALLY_START if t.dummy == "ally" else 1.0)
		return
	t.reset_effects()
	t.hp = t.max_hp
	t.alive = true
	var s: Dictionary = map.spawns[t.team][0]
	t.x = s.x
	t.z = s.z
	t.vx = 0.0
	t.vz = 0.0
	t.dash_left = 0.0
	Rules.ground(t, map)
	t.cds.fill(0.0)
	t.charges.clear()
	_label(t, "REAPARECISTE", "#ffd166")


## Scripted behaviour of the dummies (before the physics step): face the player, patrol, cast, drain the ally.
func _practice_pre(now: float) -> void:
	var focus: ArenaUnit = null
	for u in units:
		if u.peer != 0 and u.dummy == "" and u.alive:
			focus = u
			break
	for u in units:
		if u.dummy == "":
			if nocd and u.peer != 0:
				u.cds.fill(0.0)
				u.charges.clear()
			continue
		if focus != null and u.dummy != "crate":
			u.aim_x = focus.x
			u.aim_z = focus.z
		u.input = Vector2.ZERO
		match u.dummy:
			"patrol":
				var goal := PracticeYard.PATROL_TO if u.patrol_dir > 0.0 else PracticeYard.PATROL_FROM
				if absf(u.x - goal) < 0.6:
					u.patrol_dir = -u.patrol_dir
				u.input = Vector2(goal - u.x, PracticeYard.PATROL_Z - u.z)
			"caster":
				_dummy_caster(u, now)
				_stay_home(u)
			"ally":
				u.hp = maxf(u.max_hp * PracticeYard.ALLY_FLOOR, u.hp - u.max_hp * PracticeYard.ALLY_DRAIN_PER_S * _dt) if u.hp > u.max_hp * PracticeYard.ALLY_FLOOR else u.hp
				_stay_home(u)
			_:
				_stay_home(u)


func _stay_home(u: ArenaUnit) -> void:
	var to := u.home - Vector2(u.x, u.z)
	if to.length() > 0.5:
		u.input = to


func _dummy_caster(u: ArenaUnit, now: float) -> void:
	var controlled := now < u.stun_until or now < u.incap_until or now < u.fear_until or now < u.silence_until
	if not u.cast.is_empty():
		if controlled:
			u.cast = {}
			u.dummy_next = now + 2000.0
		elif now >= u.cast.ends_at:
			u.cast = {}
			u.dummy_next = now + PracticeYard.CAST_GAP_MS
			_label(u, "¡LANZÓ!", "#ff9a5a")
		return
	if controlled or now < u.dummy_next or now < u.cds[1]:
		return
	u.cast = {"slot": 1, "start_at": now, "ends_at": now + PracticeYard.CAST_MS, "ax": u.aim_x, "az": u.aim_z, "target_id": -1, "lock": -1}


## Practice controls: "reset" (meter, dummies, cooldowns), "nocd" (on/off) and "ult" (ultimate ready).
func practice_command(u: ArenaUnit, cmd: String, on: bool, now: float) -> void:
	if not practice or not u.alive or stage != null:  # a lesson has no practice controls: medals could be faked with them
		return
	match cmd:
		"reset":
			meter_for(u).reset(now)
			projs.clear()  # a fireball still flying must not land after the reset and refill the meter
			aoes.clear()
			traps.clear()
			for d in units:
				if d.dummy != "":
					_reset_dummy(d, now)
			u.cast = {}
			u.cds.fill(0.0)
			u.charges.clear()
			u.hp = u.max_hp
		"nocd":
			nocd = on
			if on:
				u.cds.fill(0.0)
				u.charges.clear()
		"ult":
			u.ult = 100.0
		"stun":  # tutorial: a long stun to break with the trinket
			u.trinket_ready = 0.0
			u.stun_until = now + 6000.0
			_label(u, "ATURDIDO", "#ffd166")


# ---------------------------------------------------------------- snapshots

func _snap_unit(u: ArenaUnit, now: float) -> Dictionary:
	var left := func(until: float) -> int: return maxi(0, roundi(until - now))
	var cc := {}
	for dot in u.curses.values():
		if now < dot.until:
			cc[dot.ability] = maxi(int(cc.get(dot.ability, 0)), left.call(dot.until))
	if now < u.stun_until: cc.stun = left.call(u.stun_until)
	if now < u.root_until: cc.root = left.call(u.root_until)
	if now < u.silence_until: cc.silence = left.call(u.silence_until)
	if now < u.incap_until:
		cc.incap = left.call(u.incap_until)
		cc.incapKind = u.incap_kind
	if now < u.slow_until: cc.slow = left.call(u.slow_until)
	if now < u.fear_until: cc.fear = left.call(u.fear_until)
	if now < u.mortal_until: cc.mortal = left.call(u.mortal_until)
	if now < u.burn_until: cc.burn = left.call(u.burn_until)
	if now < u.marked_until: cc.marked = left.call(u.marked_until)
	var buffs := {}
	if u.pact_absorb > 0 and now < u.pact_until: buffs.darkpact = left.call(u.pact_until)
	if now < u.crit_until: buffs.crit = left.call(u.crit_until)
	if now < u.stealth_until: buffs.stealth = left.call(u.stealth_until)
	if now < u.shield_until: buffs.shield = left.call(u.shield_until)
	if now < u.haste_until: buffs.haste = left.call(u.haste_until)
	if now < u.wall_until: buffs.wall = left.call(u.wall_until)
	if u.absorb > 0 and now < u.absorb_until: buffs.absorb = left.call(u.absorb_until)
	if now < u.hot_until: buffs.hot = left.call(u.hot_until)
	if now < u.storm_until: buffs.storm = left.call(u.storm_until)
	var cast = null
	if not u.cast.is_empty():
		cast = {"slot": u.cast.slot, "total": u.cast.ends_at - u.cast.start_at, "left": maxf(0.0, u.cast.ends_at - now), "tid": int(u.cast.get("target_id", -1))}
	return {
		"id": u.id, "x": u.x, "z": u.z, "rot": u.rot, "hp": ceili(u.hp), "alive": u.alive, "cast": cast,
		"cc": cc, "buffs": buffs, "dashing": u.dash_left > 0 or u.knocked, "y": u.y, "air": u.air,
	}


## What one player is allowed to see: their team's vision only (hidden enemies are never sent).
func snapshot_for(viewer: ArenaUnit, now: float) -> Dictionary:
	var snap := _snapshot(viewer, now)
	# Charges and talent counters only travel for kits that have them (the packet is tight in a 3v3).
	var ch := charges_left(viewer)
	if ch.any(func(v): return v >= 0): snap.you.ch = ch
	var st := stacks_shown(viewer)
	if st.any(func(v): return v >= 0): snap.you.st = st
	if stage != null: snap.you.lesson = stage.client_state(self)
	return snap


func _snapshot(viewer: ArenaUnit, now: float) -> Dictionary:
	var abilities: Array = viewer.spec().abilities
	return {
		"t": "state",
		"phase": phase,
		"phaseLeft": 0.0 if phase == "fight" else maxf(0.0, phase_ends_at - now),
		"round": round_n,
		"score": score.duplicate(),
		"damp": _damp(now) if phase == "fight" else 0.0,
		"gates": map.gates_open,
		"ft": (now - fight_start) if phase == "fight" else 0.0,
		"units": units.filter(func(u): return not u.dormant and team_can_see(viewer.team, u, now)).map(func(u): return _snap_unit(u, now)),
		"projs": projs.map(func(p): return {"id": p.id, "kind": p.spec.id, "x": p.x, "z": p.z, "vx": p.vx, "vz": p.vz}),
		"aoes": aoes.map(func(a): return {"id": a.id, "kind": a.get("kind", "meteor"), "x": a.x, "z": a.z, "r": a.spec.aoe, "left": maxf(0.0, (a.until if a.get("kind", "meteor") == "blizzard" else a.at) - now)}),
		"traps": traps.filter(func(t): return t.owner.team == viewer.team).map(func(t): return {"id": t.id, "x": t.x, "z": t.z, "armed": now >= t.armed_at}),
		"powers": powers.duplicate(),
		"you": {
			"cds": range(abilities.size()).map(func(i): return 0 if abilities[i].get("ult", false) else maxi(0, roundi(maxf(viewer.cds[i], viewer.gcd_until if on_gcd(abilities[i]) else 0.0) - now))),
			"trinket": maxi(0, roundi(viewer.trinket_ready - now)),
			"ult": floori(viewer.ult),
			"auto": viewer.auto_on,
			"inBush": Rules.bush_at(map, viewer.x, viewer.z) >= 0,
			"practice": practice,
			"nocd": nocd,
			"meter": meter_for(viewer).snapshot(now) if practice and meters.has(viewer.id) else {},
		},
	}
