class_name TargetLogic
extends RefCounted
## WoW-style tab targeting over plain unit dictionaries {id, team, x, z, alive, visible, incap?}.


static func visible_enemies(units: Array, team: String) -> Array:
	return units.filter(func(u): return u.team != team and u.alive and u.visible)


## Tab: nearest-to-crosshair first, then cycles outward. Returns the new target id or -1.
static func cycle(units: Array, team: String, pos: Vector2, fwd: Vector2, current: int) -> int:
	var list := visible_enemies(units, team)
	if list.is_empty():
		return -1
	var score := func(u: Dictionary) -> float:
		var d := Vector2(u.x - pos.x, u.z - pos.y)
		var dist := maxf(d.length(), 1e-6)
		return acos(clampf(d.dot(fwd) / dist, -1.0, 1.0)) * 20.0 + dist
	list.sort_custom(func(a, b): return score.call(a) < score.call(b))
	var idx := -1
	for i in list.size():
		if list[i].id == current:
			idx = i
	return list[(idx + 1) % list.size()].id


## Picks a target when there is none: the closest visible enemy, preferring those in front.
static func acquire(units: Array, team: String, pos: Vector2, fwd: Vector2, max_range := 40.0) -> int:
	var best := -1
	var best_score := INF
	for u in visible_enemies(units, team):
		var d := Vector2(u.x - pos.x, u.z - pos.y)
		var dist := maxf(d.length(), 1e-6)
		if dist >= max_range:
			continue
		var s := dist - (d.dot(fwd) / dist) * 12.0
		if s < best_score:
			best_score = s
			best = u.id
	return best


## Melee: if the current target is out of reach but someone is right next to you, switch.
## Returns the new id, or -1 when no switch is needed/possible.
static func melee_swap(units: Array, team: String, pos: Vector2, range_m: float, current: int) -> int:
	for u in units:
		if u.id == current and u.alive and u.visible and Vector2(u.x - pos.x, u.z - pos.y).length() <= range_m + 1.0:
			return -1
	var best := -1
	var best_d := INF
	for u in visible_enemies(units, team):
		var d := Vector2(u.x - pos.x, u.z - pos.y).length()
		if d <= range_m + 0.8 and not u.get("incap", false) and d < best_d:
			best_d = d
			best = u.id
	return best
