class_name Rules
extends RefCounted
## Pure game rules shared by server and client (port of shared/rules.ts).
## A "mover" is any object with x, z, vx, vz, dash_left, dash_vx, dash_vz.

const PLAYER_R := 0.5
const ACCEL := 50.0
const REVEAL_DIST := 3.2
const DR_RESET_MS := 18000.0  # WoW: a category resets 18 s after its last CC ends
const DR_MULT := [1.0, 0.5, 0.25, 0.0]


static func step_mover(m, dx: float, dz: float, dt: float, speed: float, can_move: bool, map: GameMap) -> void:
	if m.dash_left > 0:
		var t := minf(dt, m.dash_left)
		m.dash_left = maxf(0.0, m.dash_left - dt)
		m.x += m.dash_vx * t
		m.z += m.dash_vz * t
		m.vx = 0.0
		m.vz = 0.0
		collide(m, map)
		return
	if not can_move:
		m.vx = 0.0
		m.vz = 0.0
		return
	var dir := Vector2(dx, dz)
	var target := dir.normalized() * speed if dir.length() > 1e-6 else Vector2.ZERO
	var dv := target - Vector2(m.vx, m.vz)
	var max_dv := ACCEL * dt
	if dv.length() > max_dv:
		dv = dv.normalized() * max_dv
	m.vx += dv.x
	m.vz += dv.y
	m.x += m.vx * dt
	m.z += m.vz * dt
	collide(m, map)


## Signed distance from a point to a shape (negative inside).
static func sdf(o: Dictionary, x: float, z: float) -> float:
	if o.k == "c":
		return sqrt((x - o.x) * (x - o.x) + (z - o.z) * (z - o.z)) - o.r
	var dx: float = x - o.x
	var dz: float = z - o.z
	var lx: float = dx * o.c + dz * o.s
	var lz: float = -dx * o.s + dz * o.c
	var qx: float = absf(lx) - o.hx
	var qz: float = absf(lz) - o.hz
	var out := sqrt(maxf(qx, 0.0) * maxf(qx, 0.0) + maxf(qz, 0.0) * maxf(qz, 0.0))
	return out + minf(maxf(qx, qz), 0.0)


## Smallest distance to any currently solid shape.
static func sdf_all(map: GameMap, x: float, z: float) -> float:
	var best := INF
	for o in map.obstacles:
		best = minf(best, sdf(o, x, z))
	return best


## Pushes `m` out of every solid shape and back inside the arena bounds.
static func collide(m, map: GameMap, r: float = PLAYER_R) -> void:
	for o in map.obstacles:
		if o.k == "c":
			var dx: float = m.x - o.x
			var dz: float = m.z - o.z
			var d := sqrt(dx * dx + dz * dz)
			var min_d: float = o.r + r
			if d >= min_d:
				continue
			if d < 1e-6:
				m.x = o.x + min_d
				continue
			m.x = o.x + dx / d * min_d
			m.z = o.z + dz / d * min_d
		else:
			var ddx: float = m.x - o.x
			var ddz: float = m.z - o.z
			var lx: float = ddx * o.c + ddz * o.s
			var lz: float = -ddx * o.s + ddz * o.c
			var nx := clampf(lx, -o.hx, o.hx)
			var nz := clampf(lz, -o.hz, o.hz)
			var px := lx - nx
			var pz := lz - nz
			var d2 := sqrt(px * px + pz * pz)
			var push_x := 0.0
			var push_z := 0.0
			if d2 > 1e-6:
				if d2 >= r:
					continue
				push_x = px / d2 * (r - d2)
				push_z = pz / d2 * (r - d2)
			else:  # centre inside the box: leave through the nearest face
				var ex: float = o.hx - absf(lx)
				var ez: float = o.hz - absf(lz)
				if ex < ez:
					push_x = signf(lx if lx != 0.0 else 1.0) * (ex + r)
				else:
					push_z = signf(lz if lz != 0.0 else 1.0) * (ez + r)
			m.x += push_x * o.c - push_z * o.s
			m.z += push_x * o.s + push_z * o.c
	var lim_x: float = map.half_x - r
	var lim_z: float = map.half_z - r
	m.x = clampf(m.x, -lim_x, lim_x)
	m.z = clampf(m.z, -lim_z, lim_z)


static func separate(units: Array) -> void:
	for i in units.size():
		for j in range(i + 1, units.size()):
			var a = units[i]
			var b = units[j]
			var dx: float = b.x - a.x
			var dz: float = b.z - a.z
			var d := sqrt(dx * dx + dz * dz)
			if d >= PLAYER_R * 2:
				continue
			if d < 1e-6:
				dx = 1.0
				dz = 0.0
				d = 1.0
			var push := (PLAYER_R * 2 - minf(d, PLAYER_R * 2)) / 2
			a.x -= dx / d * push
			a.z -= dz / d * push
			b.x += dx / d * push
			b.z += dz / d * push


## Parametric t in [0, 1] where segment AB first touches the circle, or -1.
static func segment_circle(ax: float, az: float, bx: float, bz: float, cx: float, cz: float, r: float) -> float:
	var dx := bx - ax
	var dz := bz - az
	var fx := ax - cx
	var fz := az - cz
	var a := dx * dx + dz * dz
	var c := fx * fx + fz * fz - r * r
	if c <= 0:
		return 0.0
	if a < 1e-12:
		return -1.0
	var b := 2 * (fx * dx + fz * dz)
	var disc := b * b - 4 * a * c
	if disc < 0:
		return -1.0
	var t := (-b - sqrt(disc)) / (2 * a)
	return t if t >= 0.0 and t <= 1.0 else -1.0


## Parametric t in [0, 1] where segment AB hits an oriented box grown by `pad`, or -1.
static func segment_box(ax: float, az: float, bx: float, bz: float, o: Dictionary, pad: float) -> float:
	var ox: float = ax - o.x
	var oz: float = az - o.z
	var la_x: float = ox * o.c + oz * o.s
	var la_z: float = -ox * o.s + oz * o.c
	var dx: float = bx - ax
	var dz: float = bz - az
	var ld_x: float = dx * o.c + dz * o.s
	var ld_z: float = -dx * o.s + dz * o.c
	var hx: float = o.hx + pad
	var hz: float = o.hz + pad
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var p: float = la_x if axis == 0 else la_z
		var d: float = ld_x if axis == 0 else ld_z
		var h: float = hx if axis == 0 else hz
		if absf(d) < 1e-9:
			if absf(p) > h:
				return -1.0
		else:
			var ta := (-h - p) / d
			var tb := (h - p) / d
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return -1.0
	return t0


## First solid line-blocking shape on segment AB (t in [0,1]) or -1. Shapes with los=false (sunken pillars) are skipped.
static func obstacle_hit(map: GameMap, ax: float, az: float, bx: float, bz: float, pad: float = 0.0) -> float:
	var best := -1.0
	for o in map.obstacles:
		if not o.los:
			continue
		var t := segment_circle(ax, az, bx, bz, o.x, o.z, o.r + pad) if o.k == "c" else segment_box(ax, az, bx, bz, o, pad)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


static func has_los(map: GameMap, a, b) -> bool:
	return obstacle_hit(map, a.x, a.z, b.x, b.z) < 0.0 and not map.level_los_blocked(a.x, a.z, b.x, b.z)


static func _inside(list: Array, x: float, z: float) -> int:
	for i in list.size():
		if Vector2(x - list[i].x, z - list[i].z).length() < list[i].r:
			return i
	return -1


static func bush_at(map: GameMap, x: float, z: float) -> int:
	return _inside(map.bushes, x, z)


static func in_pool(map: GameMap, x: float, z: float) -> bool:
	return not hazard_at(map, x, z).is_empty()


## {dps, hps} of the damaging/healing floor under a point, or {}.
static func hazard_at(map: GameMap, x: float, z: float) -> Dictionary:
	for h in map.hazards:
		if absf(x - h.x) <= h.hx and absf(z - h.z) <= h.hz:
			return h
	var i := _inside(map.pools, x, z)
	return map.pools[i] if i >= 0 else {}


## Bush stealth: hidden enemies are seen up close, from the same bush, or once revealed.
static func can_see(map: GameMap, viewer, target, revealed: bool) -> bool:
	if viewer.team == target.team or revealed:
		return true
	var bush := bush_at(map, target.x, target.z)
	if bush < 0:
		return true
	if Vector2(viewer.x - target.x, viewer.z - target.z).length() < REVEAL_DIST:
		return true
	return bush_at(map, viewer.x, viewer.z) == bush


static func _is_free(map: GameMap, x: float, z: float) -> bool:
	if absf(x) > map.half_x - PLAYER_R or absf(z) > map.half_z - PLAYER_R:
		return false
	return sdf_all(map, x, z) >= PLAYER_R


## Furthest free landing spot along the direction, up to dist. Teleports pass over obstacles.
static func blink_target(map: GameMap, x: float, z: float, dir_x: float, dir_z: float, dist: float) -> Vector2:
	var u := Vector2(dir_x, dir_z)
	u = u.normalized() if u.length() > 0 else Vector2(0, 1)
	var d := dist
	while d > 0:
		var p := Vector2(x, z) + u * d
		if _is_free(map, p.x, p.y):
			return p
		d -= 0.2
	return Vector2(x, z)


## WoW-style diminishing returns: 100%, 50%, 25%, then immune until it resets.
## dr is {level, reset_at} or {}; returns {ms, dr}.
static func apply_dr(dr: Dictionary, base_ms: float, now: float) -> Dictionary:
	var level: int = 0 if dr.is_empty() or now >= dr.reset_at else dr.level
	var ms: float = base_ms * DR_MULT[mini(level, DR_MULT.size() - 1)]
	return {"ms": ms, "dr": {"level": level + 1, "reset_at": now + ms + DR_RESET_MS}}


## WoW-style Dampening: after DAMP_START_MS of fight, healing received falls by DAMP_PER_S per second (capped at DAMP_MAX),
## so stalemates between healers end. Returns the fraction of healing removed (0..DAMP_MAX).
static func dampening(fight_ms: float) -> float:
	var C := GameData.C
	if fight_ms < C.DAMP_START_MS:
		return 0.0
	return minf(float(C.DAMP_MAX), (fight_ms - float(C.DAMP_START_MS)) / 1000.0 * float(C.DAMP_PER_S))
