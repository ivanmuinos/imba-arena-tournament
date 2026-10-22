class_name BotBrain
extends RefCounted
## Bot AI per class (port of server/bot.ts).

const SKILL := {"easy": [0.1, 0.3], "normal": [0.35, 0.55], "hard": [0.75, 0.95]}
const PREF_RANGE := {"mage": 12.0, "warlock": 14.0, "hunter": 15.0, "priest": 14.0, "druid": 14.0, "ct": 16.0, "ronin": 1.8, "crack": 11.0, "warrior": 1.6, "rogue": 1.6}
## Classes that play as the team healer (slots laid out alike: 1 cast heal, 2 protect, 4 heal over time, 5 dispel, 6 ult).
const HEALERS := ["priest", "druid"]

var diff: String
var skill: float
var next_think := 0.0
var strafe := 1.0
var strafe_until := 0.0
var wander = null  # Vector2 or null


func _init(p_diff := "normal") -> void:
	diff = p_diff
	var r: Array = SKILL.get(diff, SKILL.normal)
	skill = r[0] + randf() * (r[1] - r[0])
	strafe = 1.0 if randf() < 0.5 else -1.0


## Steers around obstacles, burning pools and walls.
func _blocked(map: GameMap, x: float, z: float, from_hazard := false) -> bool:
	if absf(x) > map.half_x - 1 or absf(z) > map.half_z - 1:
		return true
	if not from_hazard and Rules.in_pool(map, x, z) and Rules.hazard_at(map, x, z).get("dps", 0) > 0:
		return true
	return Rules.sdf_all(map, x, z) < Rules.PLAYER_R + 0.3


func _steer(map: GameMap, u: ArenaUnit, d: Vector2) -> Vector2:
	if d.length() < 1e-3:
		return Vector2.ZERO
	var base := atan2(d.x, d.y)
	for off in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var a: float = base + off
		var hz := Rules.in_pool(map, u.x, u.z)
		if not _blocked(map, u.x + sin(a) * 1.4, u.z + cos(a) * 1.4, hz):
			return Vector2(sin(a), cos(a))
	return d.normalized()


## Priest support: dispel, hymn, scream, shield, renew, flash heal. Returns "cast" (casting a heal: stand still),
## "instant" (used an instant spell this think) or "" (nothing to do: free to smite).
func _priest_heal(m: ArenaMatch, u: ArenaUnit, now: float, ab: Array, ready: Callable, try_cast: Callable, chance: Callable, dn: float) -> String:
	var pct := func(a: ArenaUnit) -> float: return a.hp / a.max_hp
	var allies := m.units.filter(func(a): return a.alive and a.team == u.team and Vector2(a.x - u.x, a.z - u.z).length() < ab[1].range \
		and (a == u or Rules.has_los(m.map, u, a)))
	allies.sort_custom(func(a, b): return pct.call(a) < pct.call(b))
	var lowest: ArenaUnit = allies[0] if not allies.is_empty() else null
	var controlled: ArenaUnit = null
	for a in allies:
		if now < a.stun_until or now < a.incap_until or now < a.fear_until or now < a.root_until:
			controlled = a
			break
	var hurt := allies.filter(func(a): return pct.call(a) < 0.5).size()
	if controlled != null and ready.call(5) and chance.call(0.8) and try_cast.call(5, controlled, controlled): return "instant"
	# Curses and burns are dispellable damage: clean the most cursed ally (worth a global when 2 curses or a big one is ticking)
	var cursed: ArenaUnit = null
	var cursed_dps := 0.0
	for a in allies:
		var dps := 0.0
		for cdot in a.curses.values():
			if now < cdot.until - 1500.0:
				dps += float(cdot.dps)
		if dps >= 9.0 and dps > cursed_dps:
			cursed = a
			cursed_dps = dps
	if cursed != null and ready.call(5) and try_cast.call(5, cursed, cursed): return "instant"
	if ready.call(6) and (hurt >= 2 or (lowest != null and pct.call(lowest) < 0.3)) and try_cast.call(6, u): return "instant"
	if u.cls == "priest" and dn < 5 and ready.call(3) and chance.call(0.8) and try_cast.call(3, u): return "instant"  # psychic scream
	if lowest == null:
		return ""
	var guarded := lowest.absorb > 0 if u.cls == "priest" else now < lowest.wall_until  # shield / ironbark already on
	if pct.call(lowest) < 0.6 and ready.call(2) and not guarded and try_cast.call(2, lowest, lowest): return "instant"
	if pct.call(lowest) < 0.85 and now >= lowest.hot_until and ready.call(4) and try_cast.call(4, lowest, lowest): return "instant"
	# Flash Heal: avoid hard-casting with a melee on you, unless someone is about to die.
	if pct.call(lowest) < 0.7 and (dn > 5 or pct.call(lowest) < 0.45) and ready.call(1) and try_cast.call(1, lowest, lowest): return "cast"
	return ""


## A hurt ally (not the priest) the priest can't heal from here (out of range or behind a pillar), or null.
func _ally_to_reach(m: ArenaMatch, u: ArenaUnit, range_m: float) -> ArenaUnit:
	var best: ArenaUnit = null
	for a in m.units:
		if a == u or not a.alive or a.team != u.team or a.hp / a.max_hp >= 0.9:
			continue
		if Vector2(a.x - u.x, a.z - u.z).length() <= range_m - 4.0 and Rules.has_los(m.map, u, a):
			continue
		if best == null or a.hp / a.max_hp < best.hp / best.max_hp:
			best = a
	return best


const STALEMATE_MS := 45000.0   # with nobody in sight for this long into a round, bots go hunting
const TEAM_LEASH := 14.0   # a healer keeps this close to (and in sight of) some ally


## Where a priest wants to stand when nobody needs healing right now: with the team, behind it relative to the enemies,
## and out of the line of sight of enemy ranged units (pillars). Returns a world point, or INF when it is fine where it is.
func _priest_post(m: ArenaMatch, u: ArenaUnit, enemies: Array, now: float) -> Vector2:
	var allies: Array = m.units.filter(func(a): return a != u and a.alive and a.team == u.team)
	if allies.is_empty():
		return Vector2.INF
	var me := Vector2(u.x, u.z)
	var near_ally: ArenaUnit = null
	var nd := INF
	for a in allies:
		var d := me.distance_to(Vector2(a.x, a.z))
		if d < nd:
			nd = d
			near_ally = a
	var has_sight := false
	for a in allies:
		if me.distance_to(Vector2(a.x, a.z)) < TEAM_LEASH + 2.0 and Rules.has_los(m.map, u, a):
			has_sight = true
			break
	if not has_sight:
		return Vector2(near_ally.x, near_ally.z)  # rejoin the team
	var ranged: Array = enemies.filter(func(e): return e.cls in ["mage", "warlock", "hunter", "priest", "druid", "ct", "crack"] and Rules.has_los(m.map, e, u))
	if not ranged.is_empty():
		# step behind cover: a nearby spot that no enemy caster sees but where an ally is still in sight
		var best := Vector2.INF
		var best_d := INF
		for ring in [3.0, 5.0, 7.0]:
			for k in 12:
				var a := TAU * k / 12.0
				var p: Vector2 = me + Vector2(sin(a), cos(a)) * ring
				if _blocked(m.map, p.x, p.y):
					continue
				var probe := {"x": p.x, "z": p.y}
				var seen := false
				for e in ranged:
					if Rules.has_los(m.map, e, probe):
						seen = true
						break
				if seen:
					continue
				var ally_ok := false
				for al in allies:
					if p.distance_to(Vector2(al.x, al.z)) < TEAM_LEASH + 2.0 and Rules.has_los(m.map, probe, al):
						ally_ok = true
						break
				if ally_ok and ring < best_d:
					best_d = ring
					best = p
			if best != Vector2.INF:
				break
		if best != Vector2.INF:
			return best
	if not enemies.is_empty():
		# stand behind the team relative to the enemies
		var ac := Vector2.ZERO
		for a in allies:
			ac += Vector2(a.x, a.z)
		ac /= allies.size()
		var ec := Vector2.ZERO
		for e in enemies:
			ec += Vector2(e.x, e.z)
		ec /= enemies.size()
		var back := (ac - ec).normalized()
		var spot := ac + back * 3.5
		if me.distance_to(spot) > 3.0 and not _blocked(m.map, spot.x, spot.y):
			return spot
	return Vector2.INF


func think(m: ArenaMatch, u: ArenaUnit, now: float) -> void:
	if not u.alive or m.phase != "fight":
		u.input = Vector2.ZERO
		u.aim_x = 0.0
		u.aim_z = 0.0
		return
	if not u.cast.is_empty():
		u.input = Vector2.ZERO
		return
	if now < next_think:
		return
	next_think = now + 90 + randf() * 90 + (1 - skill) * 150
	# PvP trinket: break a long stun or fear (sheep heal, so bots, like players, usually wait those out).
	var locked_ms := maxf(u.stun_until, u.fear_until) - now
	if locked_ms > 1500.0 and now >= u.trinket_ready and randf() < 0.15 + skill * 0.35:
		m.use_trinket(u, now)

	var ab: Array = u.spec().abilities
	var ready := func(slot: int) -> bool:
		if ArenaMatch.on_gcd(ab[slot]) and now < u.gcd_until:
			return false  # global cooldown
		return u.ult >= 100 if ab[slot].get("ult", false) else now >= u.cds[slot]
	var dist := func(e) -> float: return Vector2(e.x - u.x, e.z - u.z).length()
	var noise := func() -> float: return (randf() - 0.5) * 2 * (1 - skill) * 3.2
	var lead := func(e: ArenaUnit, speed: float) -> Vector2:
		var t: float = dist.call(e) / speed
		return Vector2(e.x + e.vx * t + noise.call(), e.z + e.vz * t + noise.call())
	var chance := func(p: float) -> bool: return randf() < p * (0.4 + skill * 0.6)
	# Hard bots name their target (homing spells); melee/targeted/friendly spells always do.
	var try_cast := func(slot: int, p, lock_on: ArenaUnit = null) -> bool:
		var a: Dictionary = ab[slot]
		var named: bool = diff == "hard" or a.get("melee", false) or a.get("friendly", false) or a.get("targeted", false)
		return m.cast_ability(u, slot, p.x, p.z if p is ArenaUnit else p.y, now, lock_on.id if named and lock_on != null else -1)

	var enemies := m.units.filter(func(e): return e.alive and e.team != u.team and m.team_can_see(u.team, e, now))
	var mv := Vector2.ZERO
	var target: ArenaUnit = null
	var best_score := INF
	for e in enemies:
		var s: float = e.hp / e.max_hp * 18 + dist.call(e) + (0.0 if Rules.has_los(m.map, u, e) else 12.0)
		if s < best_score:
			best_score = s
			target = e

	if target == null:
		if wander == null or dist.call({"x": wander.x, "z": wander.y}) < 1.5:
			var r := 14.0
			for _try in 12:
				var a := randf() * TAU
				wander = Vector2(sin(a), cos(a)) * r * randf()
				if not _blocked(m.map, wander.x, wander.y):
					break
		mv = Vector2(wander.x - u.x, wander.y - u.z)
		u.aim_x = wander.x
		u.aim_z = wander.y
		if now - m.fight_start > STALEMATE_MS:
			# Nobody has found anybody for a long time (everyone hiding or wandering): go and look for the enemy team.
			var foe_team := "blue" if u.team == "red" else "red"
			var sp: Array = m.map.spawns[foe_team]
			var seek := Vector2(sp[0].x, sp[0].z) * 0.5
			mv = m.map.waypoint(Vector2(u.x, u.z), seek) - Vector2(u.x, u.z)
			u.aim_x = seek.x
			u.aim_z = seek.y
		if u.cls in HEALERS:
			# No enemy in sight is the best moment to top the team up.
			var ally := _ally_to_reach(m, u, ab[1].range)
			if ally != null:
				mv = m.map.waypoint(Vector2(u.x, u.z), Vector2(ally.x, ally.z)) - Vector2(u.x, u.z)
			else:
				var post := _priest_post(m, u, enemies, now)
				if post != Vector2.INF:
					mv = m.map.waypoint(Vector2(u.x, u.z), post) - Vector2(u.x, u.z)
			if _priest_heal(m, u, now, ab, ready, try_cast, chance, INF) == "cast" or not u.cast.is_empty():
				u.input = Vector2.ZERO
				return
	else:
		var d: float = dist.call(target)
		var los := Rules.has_los(m.map, u, target)
		var to := Vector2(target.x - u.x, target.z - u.z) / maxf(d, 1e-3)
		var nearest: ArenaUnit = target
		for e in enemies:
			if dist.call(e) < dist.call(nearest):
				nearest = e
		var dn: float = dist.call(nearest)
		var melee := u.cls in ["warrior", "rogue", "ronin"]
		var pref: float = PREF_RANGE[u.cls]
		u.aim_x = target.x
		u.aim_z = target.z
		if now > strafe_until:
			strafe = -strafe
			strafe_until = now + 900 + randf() * 1800
		if not los or d > pref + (0.4 if melee else 2.0):
			var wp := m.map.waypoint(Vector2(u.x, u.z), Vector2(target.x, target.z))
			mv = (wp - Vector2(u.x, u.z)).normalized() if wp != Vector2(target.x, target.z) else to
		elif not melee and d < pref - 4:
			mv = -to
		mv += Vector2(-to.y, to.x) * strafe * (0.25 if melee else 0.8)
		if u.cls in HEALERS:
			# A healer positions on its team, not on the enemy: walk to whoever needs healing and is out of reach.
			var ally := _ally_to_reach(m, u, ab[1].range)
			if ally != null:
				var wp := m.map.waypoint(Vector2(u.x, u.z), Vector2(ally.x, ally.z))
				mv = wp - Vector2(u.x, u.z)
			else:
				var hurt_near := m.units.any(func(a): return a.alive and a.team == u.team and a.hp / a.max_hp < 0.85 and dist.call(a) < ab[1].range)
				var post := _priest_post(m, u, enemies, now)
				if not hurt_near and post != Vector2.INF:
					mv = m.map.waypoint(Vector2(u.x, u.z), post) - Vector2(u.x, u.z)

		var reaction := 1300 - skill * 1000
		var caster: ArenaUnit = null
		for e in enemies:
			if not e.cast.is_empty() and now - e.cast.start_at > reaction and dist.call(e) < 18 and Rules.has_los(m.map, u, e):
				caster = e
				break
		var low_hp := u.hp / u.max_hp < 0.55
		var ccd := func(e: ArenaUnit) -> bool: return now < e.stun_until or now < e.incap_until or now < e.fear_until
		var in_reach := func(e: ArenaUnit, slot: int) -> bool: return dist.call(e) <= ab[slot].range + 0.5 and Rules.has_los(m.map, u, e)
		var off: ArenaUnit = null
		for e in enemies:
			if e != target and not ccd.call(e) and Rules.has_los(m.map, u, e):
				off = e
				break
		var stop := false

		match u.cls:
			"warlock":
				var near_foes := enemies.filter(func(e): return dist.call(e) < 10.0).size()
				if (low_hp or (near_foes >= 2 and u.hp / u.max_hp < 0.8)) and u.hp > 70.0 and ready.call(4):
					stop = try_cast.call(4, u)  # dark pact when focused
				if not stop and low_hp and ready.call(5) and in_reach.call(target, 5) and not ccd.call(target):
					stop = try_cast.call(5, target, target)  # drain to heal up
				# fear: a healer first, else a melee on top of us
				var fear_target: ArenaUnit = null
				for e in enemies:
					if ccd.call(e) or e.curses.size() >= 3 or not in_reach.call(e, 3):
						continue
					if e.cls in HEALERS and dist.call(e) < 17.0:
						fear_target = e
						break
					if e.cls in ["warrior", "rogue", "ronin"] and dist.call(e) < 7.5 and fear_target == null:
						fear_target = e
				if not stop and fear_target != null and ready.call(3):
					stop = try_cast.call(3, fear_target, fear_target)
				if not stop and ready.call(6) and los and in_reach.call(target, 6) and not ccd.call(target) and target.hp / target.max_hp > 0.35:
					stop = try_cast.call(6, target, target)
				# keep both curses up on every enemy in reach (not on feared/stunned ones)
				if not stop:
					for slot in [1, 2]:
						if not ready.call(slot):
							continue
						for e in enemies:
							var key := "%d:%s" % [u.id, ab[slot].id]
							if now < e.fear_until or now < e.incap_until or not in_reach.call(e, slot):
								continue
							if float(e.curses.get(key, {}).get("until", 0)) < now + 1000:
								stop = try_cast.call(slot, e, e)
								if stop:
									break
						if stop:
							break
				if not stop and not ccd.call(target) and los:
					if ready.call(5) and in_reach.call(target, 5) and target.hp / target.max_hp < 0.5: stop = try_cast.call(5, target, target)
					elif ready.call(0) and in_reach.call(target, 0): try_cast.call(0, lead.call(target, ab[0].projSpeed), target)
			"mage", "hunter":
				if caster != null and ready.call(5) and chance.call(0.9):
					stop = try_cast.call(5, caster if u.cls == "mage" else lead.call(caster, ab[5].projSpeed), caster)
				if not stop and ready.call(6) and los:
					if u.cls == "mage" and d <= 16:
						stop = try_cast.call(6, Vector2(target.x + target.vx * 0.9, target.z + target.vz * 0.9))
					elif u.cls == "hunter" and d <= 9:
						stop = try_cast.call(6, target)
				if not stop and u.cls == "mage":
					var frost := u.spec_id == "frost"
					var rooted := now < target.root_until or (now < target.incap_until and target.incap_kind == "freeze")
					if frost and rooted and los and ready.call(1) and d <= ab[1].range: stop = try_cast.call(1, target, target)  # shatter combo
					elif dn < (4.5 if frost else 5.5) and ready.call(2): stop = try_cast.call(2, nearest)  # nova (root) / dragon's breath
					elif low_hp and dn < 6 and ready.call(4): stop = try_cast.call(4, Vector2(u.x - (nearest.x - u.x), u.z - (nearest.z - u.z)))
					elif off != null and dist.call(off) < 17 and ready.call(3) and chance.call(0.3): stop = try_cast.call(3, off, off)
				elif not stop:
					if dn < 5 and ready.call(2): stop = try_cast.call(2, u)
					elif dn < 4.5 and ready.call(4): stop = try_cast.call(4, nearest)
					elif d < 20 and los and ready.call(3) and chance.call(0.35): stop = try_cast.call(3, lead.call(target, ab[3].projSpeed), target)
				if not stop and los and d <= ab[0].range:
					var safe := dn > 8 and not low_hp
					var frost_mage := u.cls == "mage" and u.spec_id == "frost"
					if frost_mage:
						# frostbolt slows; the lance is a cheap instant filler between casts
						if ready.call(1) and chance.call(0.6) and d <= ab[1].range:
							stop = try_cast.call(1, target, target)
						elif ready.call(0) and randf() < 0.35 + skill * 0.65:
							try_cast.call(0, lead.call(target, ab[0].projSpeed), target)
					elif ready.call(1) and ((safe and chance.call(0.3)) or (u.cls == "mage" and ccd.call(target) and dn > 5 and chance.call(0.9))) and d <= ab[1].range:
						stop = try_cast.call(1, target, target)
					elif ready.call(0) and randf() < 0.35 + skill * 0.65:
						try_cast.call(0, lead.call(target, ab[0].projSpeed), target)
			"ct":
				# butt-stroke a caster on top of us, flash a healer or two foes, vest up when focused, snipe a weak target
				var foes_near := enemies.filter(func(e): return dist.call(e) < 9.0)
				var flash_on: ArenaUnit = null
				for e in enemies:
					if not ccd.call(e) and in_reach.call(e, 2) and (e.cls in HEALERS or enemies.filter(func(o): return Vector2(o.x - e.x, o.z - e.z).length() < 5.0).size() >= 2):
						flash_on = e
						break
				if caster != null and in_reach.call(caster, 5) and ready.call(5) and chance.call(0.9):
					stop = try_cast.call(5, caster, caster)
				if not stop and low_hp and ready.call(3) and not foes_near.is_empty():
					stop = try_cast.call(3, u)
				if not stop and (now < u.slow_until or now < u.root_until or (low_hp and dn < 5)) and ready.call(4):
					stop = try_cast.call(4, u)
				if not stop and flash_on != null and ready.call(2) and chance.call(0.5):
					stop = try_cast.call(2, Vector2(flash_on.x, flash_on.z))
				if not stop and los and ready.call(6) and d <= ab[6].range and dn > 7 and target.hp / target.max_hp < 0.6:
					stop = try_cast.call(6, target, target)
				if not stop and los and ready.call(1) and d <= ab[1].range and dn > 6 and chance.call(0.7):
					stop = try_cast.call(1, target, target)
				if not stop and los and d <= ab[0].range and ready.call(0) and randf() < 0.35 + skill * 0.65:
					try_cast.call(0, target, target)
			"crack":
				var buddy: ArenaUnit = null
				for a in m.units:
					if a != u and a.alive and a.team == u.team and dist.call(a) < ab[4].range and dist.call(a) > 6.0:
						buddy = a
						break
				if caster != null and in_reach.call(caster, 5) and ready.call(5) and chance.call(0.9) and try_cast.call(5, caster, caster): pass
				elif dn < 3.5 and not ccd.call(nearest) and ready.call(2) and chance.call(0.8) and try_cast.call(2, nearest, nearest): pass  # nutmeg whoever gets close
				elif low_hp and dn < 6 and buddy != null and ready.call(4) and try_cast.call(4, buddy, buddy): pass  # one-two out of trouble
				elif low_hp and dn < 6 and ready.call(3) and try_cast.call(3, Vector2(u.x - (nearest.x - u.x), u.z - (nearest.z - u.z))): pass
				elif los and ready.call(6) and d <= ab[6].range and target.hp / target.max_hp < 0.55 and dn > 5 and try_cast.call(6, target, target): stop = true
				elif los and ready.call(1) and d <= ab[1].range and chance.call(0.7) and try_cast.call(1, target, target): pass
				elif los and d <= ab[0].range and ready.call(0) and randf() < 0.35 + skill * 0.65: try_cast.call(0, target, target)
			"ronin":
				var shooters := enemies.filter(func(e): return e.cls in ["mage", "warlock", "hunter", "ct", "druid", "priest"] and not e.cast.is_empty() and dist.call(e) < 22.0)
				if caster != null and in_reach.call(caster, 5) and ready.call(5) and chance.call(0.9) and try_cast.call(5, caster, caster): pass
				elif not shooters.is_empty() and ready.call(2) and chance.call(0.6) and try_cast.call(2, shooters[0]): pass  # wind wall toward the caster
				elif ready.call(6) and in_reach.call(target, 6) and target.hp / target.max_hp < 0.45 and chance.call(0.8) and try_cast.call(6, target, target): pass
				elif low_hp and ready.call(4) and dn < 6 and try_cast.call(4, u): pass
				elif d > 3.0 and in_reach.call(target, 3) and ready.call(3) and chance.call(0.8) and try_cast.call(3, target, target): pass
				elif d <= ab[1].range and los and ready.call(1) and try_cast.call(1, target, target): pass
				elif in_reach.call(target, 0) and ready.call(0) and randf() < 0.35 + skill * 0.65: try_cast.call(0, target, target)
			"warrior":
				if caster != null and in_reach.call(caster, 5) and ready.call(5) and chance.call(0.9) and try_cast.call(5, caster, caster): pass
				elif ready.call(6) and enemies.any(func(e): return dist.call(e) < 4.2) and chance.call(0.8) and try_cast.call(6, u): pass
				elif d > 7 and d < ab[2].range and los and ready.call(2) and chance.call(0.8) and try_cast.call(2, target, target): pass
				elif low_hp and dn < 5 and ready.call(4) and try_cast.call(4, u): pass
				elif in_reach.call(target, 0):
					if ready.call(1) and try_cast.call(1, target, target): pass
					elif now >= target.slow_until and ready.call(3) and chance.call(0.6) and try_cast.call(3, target, target): pass
					elif ready.call(0) and randf() < 0.35 + skill * 0.65: try_cast.call(0, target, target)
			"rogue":
				if caster != null and in_reach.call(caster, 5) and ready.call(5) and chance.call(0.9) and try_cast.call(5, caster, caster): pass
				elif low_hp and dn < 6 and ready.call(4) and chance.call(0.7) and try_cast.call(4, u): pass
				elif d > 9 and ready.call(4) and ready.call(2) and chance.call(0.6) and try_cast.call(4, u): pass  # sprint in unseen
				elif off != null and in_reach.call(off, 3) and ready.call(3) and chance.call(0.35) and try_cast.call(3, off, off): pass
				elif ready.call(6) and target.hp / target.max_hp < 0.7 and in_reach.call(target, 6) and chance.call(0.8) and try_cast.call(6, target, target): pass
				elif in_reach.call(target, 0):
					if not ccd.call(target) and ready.call(2) and chance.call(0.7) and try_cast.call(2, target, target): pass
					elif ready.call(1) and try_cast.call(1, target, target): pass
					elif ready.call(0) and randf() < 0.35 + skill * 0.65: try_cast.call(0, target, target)
			"priest", "druid":
				# druid: cyclone a second enemy (not the one being focused) when the team is not in trouble
				if u.cls == "druid" and off != null and ready.call(3) and in_reach.call(off, 3) and u.hp / u.max_hp > 0.5 and chance.call(0.35):
					stop = try_cast.call(3, off, off)
				var heal := "cast" if stop else _priest_heal(m, u, now, ab, ready, try_cast, chance, dn)
				if heal == "cast":
					stop = true
				elif heal == "" and los and d <= ab[0].range and ready.call(0) and randf() < 0.35 + skill * 0.65:
					try_cast.call(0, lead.call(target, ab[0].projSpeed), target)
		if stop or not u.cast.is_empty():
			u.input = Vector2.ZERO
			return

	# Grab nearby power-ups (and go out of the way for a heal when hurt).
	var power = null
	var pd := INF
	for p in m.powers:
		var d: float = dist.call(p)
		if d < pd:
			pd = d
			power = p
	if power != null and (pd < 5 or (target == null and pd < 14) or (power.kind == "heal" and u.hp / u.max_hp < 0.5 and pd < 12)):
		mv = Vector2(power.x - u.x, power.z - u.z)
	u.input = _steer(m.map, u, mv)
