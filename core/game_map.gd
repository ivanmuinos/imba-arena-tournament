class_name GameMap
extends RefCounted
## The four hand-designed, point-symmetric arenas (replaces the random forest maps).
##
## Layout (z is the long axis; red starts at +z, blue at -z, rooms are mirrored through the origin):
##   arena interior  x in [-26, 26], z in [-22, 22]
##   start rooms     |x| <= 8, 22 < |z| <= 33, closed by a gate (12 m wide) in the end wall at |z| = 22
## Shapes are dictionaries: circle {k:"c", x, z, r}, oriented box {k:"b", x, z, hx, hz, c, s} (c/s = cos/sin of
## the rotation), plus `los` (blocks vision/projectiles) and optional `wall`/`gate` flags.
## `obstacles` is the list of *currently solid* shapes; it is rebuilt by apply_state() when gates or the
## living pillars change, so every rule (collision, LoS, blink...) just reads `obstacles`.

const IDS := ["bridge", "pillars", "tomb", "living", "spire"]
## Offline-only training ground ("Arena de práctica"): not part of the random pool or the lobby catalog.
const PRACTICE_ID := "yard"
const W := 26.0
const A := 22.0
const R := 33.0
const ROOM_HW := 8.0
const GATE_HW := 6.0
const BRIDGE_HW := 2.0
## Living pillar cycle (seconds): telegraph, rise, up, sink; one cycle every PERIOD.
const WARN_S := 2.0
const RISE_S := 0.8
const UP_S := 7.0
const SINK_S := 0.8
const PERIOD_S := 24.0

var id: String
var name := ""
var half_x := W
var half_z := R
var half: float:
	get: return maxf(half_x, half_z)
var spawns := {"red": [], "blue": []}
var statics: Array = []
var gate_shapes: Array = []
var dyn_pillars: Array = []  # {x, z, r, start (s: moment it finishes rising the first time), group}
var hazards: Array = []      # damaging/healing floor boxes {k:"b", ..., dps, hps}
var pools: Array = []        # legacy circular hazards (none in the new maps)
var bushes: Array = []
var power_spots: Array = []
var obstacles: Array = []
var gates_open := false
var ft := 0.0
var _sig := ""


static func create(map_id: String) -> GameMap:
	GameData.ensure_loaded()
	var m := GameMap.new()
	m.id = map_id
	m.name = GameData.maps.get(map_id, {}).get("name", map_id)
	match map_id:
		"bridge": m._build_bridge()
		"pillars": m._build_pillars()
		"tomb": m._build_tomb()
		"living": m._build_living()
		"spire": m._build_spire()
		"yard": m._build_yard()
		_:
			m.id = "test"
			m._build_test()
	m.apply_state(false, 0.0)
	return m


## Kept for old call sites: maps are cheap now, and each match owns its mutable gate/pillar state.
static func get_map(map_id: String) -> GameMap:
	return create(map_id)


static func generate(map_id: String = "bridge", _seed_value: int = -1) -> GameMap:
	return create(map_id)


## Deterministic random arena for a seed (the host picks the seed; clients receive the result).
static func pick_id(seed_value: int) -> String:
	var r := Rng.new(seed_value * 2654435761 + 12345)
	r.next()
	return IDS[int(r.next() * IDS.size()) % IDS.size()]


# ---------------------------------------------------------------- shapes

static func circle(x: float, z: float, r: float, extra := {}) -> Dictionary:
	var d := {"k": "c", "x": x, "z": z, "r": r, "los": true}
	d.merge(extra, true)
	return d


static func box(x: float, z: float, hx: float, hz: float, deg := 0.0, extra := {}) -> Dictionary:
	var a := deg_to_rad(fposmod(deg, 180.0))  # canonical angle: a box is the same after 180 degrees
	var d := {"k": "b", "x": x, "z": z, "hx": hx, "hz": hz, "c": cos(a), "s": sin(a), "los": true}
	d.merge(extra, true)
	return d


func _mirror_add(list: Array, shape: Dictionary) -> void:
	list.append(shape)
	var m := shape.duplicate()
	m.x = 0.0 if shape.x == 0.0 else -shape.x
	m.z = 0.0 if shape.z == 0.0 else -shape.z
	if m.x == shape.x and m.z == shape.z:
		return
	list.append(m)


## Rooms, end walls and the gates shared by the four arenas.
func _base() -> void:
	half_x = W
	half_z = R
	for sz in [1.0, -1.0]:
		for sx in [1.0, -1.0]:
			var cx: float = sx * (W + GATE_HW) / 2.0
			statics.append(box(cx, sz * A, (W - GATE_HW) / 2.0, 0.7, 0.0, {"wall": true}))
			statics.append(box(sx * ROOM_HW, sz * (A + R) / 2.0, 0.7, (R - A) / 2.0, 0.0, {"wall": true}))
		statics.append(box(0.0, sz * R, ROOM_HW, 0.7, 0.0, {"wall": true}))
		gate_shapes.append(box(0.0, sz * A, GATE_HW, 0.7, 0.0, {"gate": true}))
	spawns = {
		"red": [{"x": -4.0, "z": 28.0}, {"x": 0.0, "z": 27.0}, {"x": 4.0, "z": 28.0}],
		"blue": [{"x": 4.0, "z": -28.0}, {"x": 0.0, "z": -27.0}, {"x": -4.0, "z": -28.0}],
	}


func _powers(list: Array) -> void:
	for p in list:
		power_spots.append({"x": p[0], "z": p[1]})


func _build_bridge() -> void:
	_base()
	var lava: Dictionary = GameData.maps.get("bridge", {}).get("pool", {"dps": 15, "hps": 0})
	for sx in [1.0, -1.0]:
		hazards.append(box(sx * 11.0, 0.0, 9.0, 9.0, 0.0, {"dps": lava.dps, "hps": lava.hps}))
		hazards.append(box(sx * 23.0, 0.0, 3.0, 4.0, 0.0, {"dps": lava.dps, "hps": lava.hps}))
	for p in [[12.0, 15.0], [-12.0, 15.0]]:
		_mirror_add(statics, circle(p[0], p[1], 1.6))
	_powers([[0, 16], [0, -16], [19, 15], [-19, -15], [-19, 15], [19, -15]])


func _build_pillars() -> void:
	_base()
	for p in [[10.0, 8.0], [10.0, -8.0]]:
		_mirror_add(statics, circle(p[0], p[1], 2.6))
	# Diagonal corner walls make the hall read as round.
	for sx in [1.0, -1.0]:
		for sz in [1.0, -1.0]:
			statics.append(box(sx * (W - 4.0), sz * (A - 4.0), 7.0, 0.8, 45.0 if sx * sz < 0 else 135.0, {"wall": true}))
	_powers([[0, 14], [0, -14], [17, 0], [-17, 0]])


func _build_tomb() -> void:
	_base()
	statics.append(circle(0.0, 0.0, 3.8, {"statue": true}))
	_mirror_add(statics, box(6.0, 16.0, 0.7, 0.35))
	_mirror_add(statics, circle(16.0, 0.0, 1.2))
	_powers([[0, 12], [0, -12], [14, 7], [-14, -7]])


func _build_living() -> void:
	_base()
	for g in [[9.0, 7.0, 12.0, 0], [9.0, -7.0, 24.0, 1]]:
		for sgn in [1.0, -1.0]:
			dyn_pillars.append({"x": g[0] * sgn, "z": g[1] * sgn, "r": 2.6, "start": g[2], "group": g[3]})
	dyn_pillars.append({"x": 0.0, "z": 0.0, "r": 2.4, "start": 18.0, "group": 2})
	_powers([[0, 13], [0, -13], [17, 0], [-17, 0]])


## Elven city plaza: a sun fountain in the centre (blocks sight), four arcane crystal spires on the diagonals and a
## marble arch in front of each gate to break the first volley.
func _build_spire() -> void:
	_base()
	statics.append(circle(0.0, 0.0, 3.2, {"fountain": true}))
	for p in [[11.0, 9.0], [11.0, -9.0]]:
		_mirror_add(statics, circle(p[0], p[1], 1.3, {"crystal": true}))
	_mirror_add(statics, box(0.0, 15.0, 4.0, 0.6, 0.0, {"arch": true}))
	_powers([[0, 9], [0, -9], [19, 0], [-19, 0]])


## Training yard: one open field (no start rooms, no gates), a pillar for line-of-sight practice and a second one to hide behind.
func _build_yard() -> void:
	half_x = W
	half_z = A
	for sz in [1.0, -1.0]:
		statics.append(box(0.0, sz * A, W, 0.7, 0.0, {"wall": true}))
	statics.append(circle(-7.5, 7.0, 2.2))
	statics.append(circle(9.0, -11.0, 1.8))
	spawns = {"red": [{"x": 0.0, "z": 17.5}, {"x": -3.0, "z": 17.5}, {"x": 3.0, "z": 17.5}], "blue": [{"x": 0.0, "z": -17.0}]}


## Hidden open field (bush + no gates) used by the unit tests; not part of the catalog.
func _build_test() -> void:
	half_x = 48.0
	half_z = 48.0
	spawns = {"red": [{"x": -5.0, "z": 36.0}, {"x": 0.0, "z": 37.0}, {"x": 5.0, "z": 36.0}], "blue": [{"x": 5.0, "z": -36.0}, {"x": 0.0, "z": -37.0}, {"x": -5.0, "z": -36.0}]}
	bushes = [{"x": 0.0, "z": 12.0, "r": 2.5}, {"x": 0.0, "z": -12.0, "r": 2.5}]
	_powers([[12, 0], [-12, 0]])


# ---------------------------------------------------------------- dynamic state

## {state: down|warn|rise|up|sink, h: 0..1, warn: 0..1} of living pillar `i` at `fight_ms` since the fight began.
func pillar_info(i: int, fight_ms: float) -> Dictionary:
	var p: Dictionary = dyn_pillars[i]
	var t: float = fight_ms / 1000.0 - (p.start - WARN_S)
	if t < 0.0:
		return {"state": "down", "h": 0.0, "warn": 0.0}
	var k := fmod(t, PERIOD_S)
	if k < WARN_S:
		return {"state": "warn", "h": 0.0, "warn": k / WARN_S}
	k -= WARN_S
	if k < RISE_S:
		return {"state": "rise", "h": k / RISE_S, "warn": 0.0}
	k -= RISE_S
	if k < UP_S:
		return {"state": "up", "h": 1.0, "warn": 0.0}
	k -= UP_S
	if k < SINK_S:
		return {"state": "sink", "h": 1.0 - k / SINK_S, "warn": 0.0}
	return {"state": "down", "h": 0.0, "warn": 0.0}


## Gates open/closed and the living pillars at `fight_ms`; rebuilds `obstacles` only when something changed.
func apply_state(open: bool, fight_ms: float) -> void:
	gates_open = open
	ft = fight_ms
	var sig := "g1" if open else "g0"
	for i in dyn_pillars.size():
		var info := pillar_info(i, fight_ms)
		sig += "|%d" % roundi(info.h * 40.0)
	if sig == _sig:
		return
	_sig = sig
	obstacles = statics.duplicate()
	if not open:
		obstacles.append_array(gate_shapes)
	for i in dyn_pillars.size():
		var info := pillar_info(i, fight_ms)
		if info.h > 0.02:
			var p: Dictionary = dyn_pillars[i]
			var e: float = info.h * info.h * (3.0 - 2.0 * info.h)  # smoothstep: radius grows as it rises, so players are pushed out gradually
			obstacles.append(circle(p.x, p.z, p.r * e, {"los": info.h >= 0.55, "dyn": true}))


# ---------------------------------------------------------------- terrain & levels (bridge map)

static func _bump(d: float, r: float) -> float:
	return 0.0 if d >= r else (1.0 + cos(PI * d / r)) / 2.0


static func _smooth_box(x: float, z: float, hx: float, hz: float, soft: float) -> float:
	var ex := clampf((hx - absf(x)) / soft + 0.5, 0.0, 1.0)
	var ez := clampf((hz - absf(z)) / soft + 0.5, 0.0, 1.0)
	return ex * ez


## Floor height (view and camera only; gameplay is 2D).
func height_at(x: float, z: float) -> float:
	match id:
		"bridge":
			var chasm := maxf(_smooth_box(absf(x) - 11.0, z, 9.0, 9.0, 1.4), _smooth_box(absf(x) - 23.0, z, 3.0, 4.0, 1.0))
			var h := 3.0 - 5.0 * chasm
			# Ramps climb out of the chasm at both ends: floor rises from -2 at |z|=4 to 3 at |z|=9.
			var w := clampf(absf(x) - 20.0, 0.0, 1.0)
			if w > 0.0:
				h = lerpf(h, lerpf(-2.0, 3.0, clampf((absf(z) - 4.0) / 5.0, 0.0, 1.0)), w)
			var deck := clampf((BRIDGE_HW + 0.5 - absf(x)) / 0.5, 0.0, 1.0)
			if absf(z) < 9.5:
				h = lerpf(h, 3.0, deck)
			return h
		"tomb":
			return 0.7 * _bump(Vector2(x, z).length(), 8.5)
	return 0.0


## Chasm floor: below the cliffs, so cut off from the high ground (plateaus and bridge).
func is_low(x: float, z: float) -> bool:
	for h in hazards:
		if absf(x - h.x) <= h.hx and absf(z - h.z) <= h.hz:
			return true
	return false


## Cliff walls and bridge supports hide the high ground from anyone in the chasm (and vice versa).
func level_los_blocked(ax: float, az: float, bx: float, bz: float) -> bool:
	if hazards.is_empty():
		return false
	return is_low(ax, az) != is_low(bx, bz)


## Next point a bot should head for when going from `from` to `to` (routes around the chasm over the bridge).
func waypoint(from: Vector2, to: Vector2) -> Vector2:
	if id != "bridge":
		return to
	if is_low(from.x, from.y):  # fell in: climb the nearest ramp
		return Vector2(signf(from.x) * 22.5, signf(to.y) * 12.0 if absf(from.y) < 1.0 else signf(from.y) * 12.0)
	var across := from.y * to.y < 0.0 and (absf(from.y) > 3.0 or absf(to.y) > 3.0)
	if not across:
		return to
	var entry := Vector2(0.0, signf(from.y) * 10.5)
	if absf(from.y) >= 9.5 and absf(from.x) > 1.2:
		return entry  # line up with the bridge first
	return Vector2(0.0, signf(to.y) * 11.0)
