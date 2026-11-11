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
## The Academia's arena: a line of rooms joined by doors (see _build_academy). Not in `IDS` nor in data/maps.json, so
## MatchConfig.normalize refuses it and only the local lesson branch of GameServer can start it.
const ACADEMY_ID := "academy"
## The Academia's valley: one open map with zones joined by paths, where lessons are given as quests. Like `academy`, it is
## outside `IDS` and data/maps.json, so only the local lesson branch of GameServer can start it.
const VALLEY_ID := "valley"
const VALLEY_NAME := "Valle de Brasas"
const VALLEY_H := 72.0
const RIVER_Z := -18.0
const RIVER_HZ := 3.0
## The two fords of the lava river (x of their centres) and half their width.
const FORDS := [-28.0, 28.0]
const FORD_HW := 6.0
const POND := Vector3(-46.0, -46.0, 7.5)  # x, z, radius
## Places of the valley: flat ground, a name on the minimap and on screen when you walk in.
const VALLEY_ZONES := [
	{"id": "camp", "name": "Campamento de Tizón", "x": 0.0, "z": 54.0, "r": 13.0, "icon": "home"},
	{"id": "yard", "name": "Patio de práctica", "x": -38.0, "z": 26.0, "r": 12.0, "icon": "dummy"},
	{"id": "ruins", "name": "Ruinas de los pilares", "x": 38.0, "z": 14.0, "r": 13.0, "icon": "ruin"},
	{"id": "river", "name": "Río de lava", "x": 0.0, "z": -18.0, "r": 9.0, "icon": "lava"},
	{"id": "grove", "name": "Bosque viejo", "x": -44.0, "z": -36.0, "r": 11.0, "icon": "tree"},
	{"id": "quarry", "name": "Cantera de cristal", "x": 48.0, "z": -44.0, "r": 12.0, "icon": "crystal"},
	{"id": "arena", "name": "Arena del duelo", "x": 0.0, "z": -50.0, "r": 15.0, "icon": "swords"},
]
## Dirt paths, as lines of points [x, z].
const VALLEY_PATHS := [
	[[0, 56], [0, 34], [-20, 28], [-38, 26]],
	[[0, 34], [20, 22], [38, 14]],
	[[0, 34], [0, 8], [-28, -6], [-28, -28], [-8, -31], [0, -31]],
	[[0, 8], [28, -6], [28, -28], [8, -31], [0, -31], [0, -50]],
	[[-28, -28], [-46, -40]],
	[[28, -28], [46, -40]],
]
const PATH_HW := 1.7
## Plates of the first quests, after the one of each zone (so they are 7, 8, 9...): left and right of the camp's yard,
## the way out, behind where you arrive, and the crossroads.
const VALLEY_QUEST_PLATES := [[-8.0, 45.0], [8.0, 45.0], [0.0, 40.0], [-6.0, 61.5], [0.0, 34.0]]
const TIZON_AT := Vector2(2.8, 53.2)
const ACADEMY_HX := 18.0
const ACADEMY_HZ := 54.0
const ROOM_DEPTH := 18.0
const ROOM_COUNT := 6
const DOOR_HW := 4.0
## The door you can see and shoot through (`los` off).
const GRATE_DOOR := 1
const PILLAR_ROOM := 3
const LAVA_ROOM := 4
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
var doors: Array = []        # academy: door shapes, solid while their bit in door_mask is off
var door_mask := 0
var zones: Array = []        # valley: named places {id, name, x, z, r, icon}
var plates: Array = []       # academy: floor plates {x, z, r}; the lesson stage decides which ones count
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
		"academy": m._build_academy()
		"valley": m._build_valley()
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


## Centre (z) of an academy room; room 0 is the first one, at +z.
func room_z(room: int) -> float:
	return ACADEMY_HZ - ROOM_DEPTH * (room + 0.5)


## Six rooms in a line, one door between each. Every room has the same four plates (left, right, near its exit, near its
## entrance), so any lesson can use any room without the client needing to be told where they are.
func _build_academy() -> void:
	name = "Academia"
	half_x = ACADEMY_HX
	half_z = ACADEMY_HZ
	for sz in [1.0, -1.0]:
		statics.append(box(0.0, sz * ACADEMY_HZ, ACADEMY_HX, 0.7, 0.0, {"wall": true}))
	for sx in [1.0, -1.0]:
		statics.append(box(sx * ACADEMY_HX, 0.0, 0.7, ACADEMY_HZ, 0.0, {"wall": true}))
	for i in ROOM_COUNT - 1:
		var z := ACADEMY_HZ - ROOM_DEPTH * (i + 1)
		var side := (ACADEMY_HX + DOOR_HW) / 2.0
		var half := (ACADEMY_HX - DOOR_HW) / 2.0
		for sx in [1.0, -1.0]:
			statics.append(box(sx * side, z, half, 0.7, 0.0, {"wall": true}))
		doors.append(box(0.0, z, DOOR_HW, 0.7, 0.0, {"door": i, "los": i != GRATE_DOOR}))
	for room in ROOM_COUNT:
		var c := room_z(room)
		for p in [[-10.0, 0.0], [10.0, 0.0], [0.0, -6.0], [0.0, 6.0]]:
			plates.append({"x": p[0], "z": c + p[1], "r": 1.8})
	var pillars := room_z(PILLAR_ROOM)
	statics.append(circle(-7.0, pillars, 2.2))
	statics.append(circle(7.0, pillars, 2.2))
	var lava: Dictionary = GameData.maps.get("bridge", {}).get("pool", {"dps": 15, "hps": 0})
	hazards.append(box(0.0, room_z(LAVA_ROOM) + 3.5, 13.0, 1.0, 0.0, {"dps": lava.dps, "hps": lava.hps}))
	spawns = {"red": [{"x": 0.0, "z": room_z(0) + 3.0}], "blue": [{"x": 0.0, "z": room_z(ROOM_COUNT - 1)}]}


## Whether a map belongs to the Academia (lessons only, one local player).
static func is_lesson_map(map_id: String) -> bool:
	return map_id == ACADEMY_ID or map_id == VALLEY_ID


## The valley: zones on flat ground, a river of lava with two fords, trees and rocks to walk around. The edge is the
## map's own limit (half_x, half_z): the mountains beyond it are only drawn.
func _build_valley() -> void:
	name = VALLEY_NAME
	half_x = VALLEY_H
	half_z = VALLEY_H
	zones = VALLEY_ZONES.duplicate(true)
	spawns = {"red": [{"x": 0.0, "z": 57.0}], "blue": [{"x": 0.0, "z": -56.0}]}
	# lava river, cut by the two fords
	var edges: Array = [-VALLEY_H]
	for f in FORDS:
		edges.append(float(f) - FORD_HW)
		edges.append(float(f) + FORD_HW)
	edges.append(VALLEY_H)
	var lava: Dictionary = GameData.maps.get("bridge", {}).get("pool", {"dps": 15, "hps": 0})
	for i in range(0, edges.size(), 2):
		var from := float(edges[i])
		var to := float(edges[i + 1])
		hazards.append(box((from + to) / 2.0, RIVER_Z, (to - from) / 2.0, RIVER_HZ, 0.0, {"dps": lava.dps, "hps": lava.hps}))
	# camp: a broken wall behind the fire and four braziers
	statics.append(box(0.0, 67.0, 9.0, 0.7, 0.0, {"wall": true}))
	for sx in [-1.0, 1.0]:
		statics.append(box(sx * 11.5, 62.0, 0.7, 3.0, 0.0, {"wall": true}))
		statics.append(circle(sx * 7.0, 49.0, 0.5, {"art": "torch", "los": false}))
		statics.append(circle(sx * 9.0, 60.0, 0.5, {"art": "torch", "los": false}))
	statics.append(circle(0.0, 63.5, 1.4, {"art": "statue"}))
	statics.append(circle(4.6, 51.0, 0.6, {"art": "torch", "los": false}))
	# yard: corner posts
	for c in [[-48.0, 17.0], [-28.0, 17.0], [-48.0, 35.0], [-28.0, 35.0]]:
		statics.append(circle(c[0], c[1], 0.9, {"art": "broken_column"}))
	# ruins: pillars to hide behind, and fallen stones
	for c in [[32.0, 9.0], [44.0, 10.0], [42.0, 24.0], [31.0, 24.0], [46.0, 21.0]]:
		statics.append(circle(c[0], c[1], 2.0, {"art": "pillar"}))
	for c in [[36.0, 4.0], [48.0, 15.0], [27.0, 14.0]]:
		statics.append(circle(c[0], c[1], 1.0, {"art": "broken_column"}))
	# arena: a square of walls with a gap on each side, a pillar on each corner
	var ax := 0.0
	var az := -50.0
	var half := 14.0
	var gap := 4.0
	var piece := (half - gap) / 2.0
	for s in [-1.0, 1.0]:
		for t in [-1.0, 1.0]:
			statics.append(box(ax + t * (gap + piece), az + s * half, piece, 0.7, 0.0, {"wall": true}))
			statics.append(box(ax + s * half, az + t * (gap + piece), 0.7, piece, 0.0, {"wall": true}))
			statics.append(circle(ax + s * half, az + t * half, 1.5, {"art": "pillar"}))
	# quarry: crystals and boulders
	for c in [[51.0, -36.0, 1.2], [52.0, -42.0, 1.6], [47.0, -50.0, 1.3], [55.0, -50.0, 1.0], [41.0, -47.0, 0.9]]:
		statics.append(circle(c[0], c[1], c[2], {"art": "crystal", "los": false}))
	# trees and rocks everywhere else, the same on every machine
	var r := Rng.new(20261)
	var placed := 0
	var tries := 0
	while placed < 150 and tries < 4000:
		tries += 1
		var x := (r.next() * 2.0 - 1.0) * (VALLEY_H - 2.0)
		var z := (r.next() * 2.0 - 1.0) * (VALLEY_H - 2.0)
		var kind := r.next()
		var size := 0.6 + r.next() * 0.5
		var deep := Vector2(x - POND.x, z - POND.y).length() < 26.0  # the old forest is thick
		if not deep and r.next() < 0.45 and maxf(absf(x), absf(z)) < VALLEY_H - 14.0:
			continue  # open meadows in the middle, thicker toward the edges
		if not _valley_free(x, z, size + 2.2):
			continue
		var art: String = (["tree_a", "tree_b", "tree_c"][int(kind * 3.0) % 3]) if kind < 0.74 or deep else (["rock_a", "rock_b", "rock_c"][int(kind * 30.0) % 3])
		statics.append(circle(x, z, size if art.begins_with("tree") else size * 1.5, {"art": art, "sc": 0.85 + r.next() * 0.7, "rot": r.next() * TAU}))
		placed += 1
	# lesson plates: one in front of each zone's centre, toward the camp
	for zn in zones:
		plates.append({"x": float(zn.x), "z": float(zn.z) + (0.0 if str(zn.id) == "camp" else 4.0), "r": 2.2})
	for p in VALLEY_QUEST_PLATES:
		plates.append({"x": float(p[0]), "z": float(p[1]), "r": 1.8})


## Room for something of that radius: off the paths, the zones, the river, the pond and what is already there.
func _valley_free(x: float, z: float, r: float) -> bool:
	if path_weight(x, z) > 0.0 or absf(z - RIVER_Z) < RIVER_HZ + 3.0 + r:
		return false
	if Vector2(x - POND.x, z - POND.y).length() < POND.z + r:
		return false
	for zn in VALLEY_ZONES:
		if str(zn.id) != "grove" and Vector2(x - float(zn.x), z - float(zn.z)).length() < float(zn.r) + r:
			return false
	for o in statics:
		if o.k == "c" and Vector2(x - o.x, z - o.z).length() < o.r + r:
			return false
	return true


## 1 on a dirt path, fading to 0 at its edge. Only the valley has paths.
func path_weight(x: float, z: float) -> float:
	if id != VALLEY_ID:
		return 0.0
	var best := 1e9
	var p := Vector2(x, z)
	for line in VALLEY_PATHS:
		for i in line.size() - 1:
			var a := Vector2(line[i][0], line[i][1])
			var b := Vector2(line[i + 1][0], line[i + 1][1])
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
	return clampf((PATH_HW + 1.2 - best) / 1.2, 0.0, 1.0)


## The zone a point is in ({} outside all of them).
func zone_at(x: float, z: float) -> Dictionary:
	for zn in zones:
		if Vector2(x - float(zn.x), z - float(zn.z)).length() <= float(zn.r):
			return zn
	return {}


## What the ground is made of at a point, for the minimap and the terrain: lava, water, path, stone (a zone's floor) or grass.
func ground_kind(x: float, z: float) -> String:
	if not Rules.hazard_at(self, x, z).is_empty():
		return "lava"
	if id != VALLEY_ID:
		return "stone"
	if Vector2(x - POND.x, z - POND.y).length() < POND.z - 1.0:
		return "water"
	if path_weight(x, z) > 0.5:
		return "path"
	var zn := zone_at(x, z)
	if not zn.is_empty() and str(zn.id) in ["camp", "arena", "yard"] and Vector2(x - float(zn.x), z - float(zn.z)).length() < float(zn.r) - 2.0:
		return "stone"
	return "grass"


## Opens exactly the doors whose bit is on. Maps without doors ignore it.
func set_doors(mask: int) -> void:
	if doors.is_empty():
		return
	door_mask = mask
	_rebuild()


func door_open(i: int) -> bool:
	return door_mask & (1 << i) != 0


## Index of the plate at a point (-1: none).
func plate_at(x: float, z: float) -> int:
	for i in plates.size():
		var p: Dictionary = plates[i]
		if Vector2(x - p.x, z - p.z).length() <= p.r:
			return i
	return -1


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
	if not doors.is_empty():
		sig += "|d%d" % door_mask
	if sig == _sig:
		return
	_sig = sig
	obstacles = statics.duplicate()
	for i in doors.size():
		if not door_open(i):
			obstacles.append(doors[i])
	if not open:
		obstacles.append_array(gate_shapes)
	for i in dyn_pillars.size():
		var info := pillar_info(i, fight_ms)
		if info.h > 0.02:
			var p: Dictionary = dyn_pillars[i]
			var e: float = info.h * info.h * (3.0 - 2.0 * info.h)  # smoothstep: radius grows as it rises, so players are pushed out gradually
			obstacles.append(circle(p.x, p.z, p.r * e, {"los": info.h >= 0.55, "dyn": true}))


func _rebuild() -> void:
	apply_state(gates_open, ft)


# ---------------------------------------------------------------- terrain & levels (bridge map)

static func _bump(d: float, r: float) -> float:
	return 0.0 if d >= r else (1.0 + cos(PI * d / r)) / 2.0


static func _smooth_box(x: float, z: float, hx: float, hz: float, soft: float) -> float:
	var ex := clampf((hx - absf(x)) / soft + 0.5, 0.0, 1.0)
	var ez := clampf((hz - absf(z)) / soft + 0.5, 0.0, 1.0)
	return ex * ez


## Floor height: units stand on it, fall to it and cannot climb its cliffs (see Rules.step_mover).
## Whether the floor has any height at all (flat maps skip the terrain checks).
var relief: bool:
	get: return id == "bridge" or id == "tomb" or id == VALLEY_ID


## Gradient of the floor (rise per metre along x and z): its length is the steepness, it points uphill.
func slope_at(x: float, z: float) -> Vector2:
	const E := 0.05
	return Vector2(height_at(x + E, z) - height_at(x - E, z), height_at(x, z + E) - height_at(x, z - E)) / (2.0 * E)


func height_at(x: float, z: float) -> float:
	match id:
		"bridge":
			var chasm := maxf(_smooth_box(absf(x) - 11.0, z, 9.0, 9.0, 1.4), _smooth_box(absf(x) - 22.0, z, 4.0, 4.0, 1.0))  # the two pits overlap: no ridge between them
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
		"valley":
			return _valley_height(x, z)
	return 0.0


## Rolling meadows, flat where things happen (zones, the river banks), a channel for the lava and a hollow for the pond.
func _valley_height(x: float, z: float) -> float:
	var roll := 1.3 * sin(x * 0.071 + 1.3) * cos(z * 0.063 - 0.4) + 0.7 * sin((x + z) * 0.043 + 2.0)
	var flat := clampf((RIVER_HZ + 9.0 - absf(z - RIVER_Z)) / 6.0, 0.0, 1.0)
	for zn in VALLEY_ZONES:
		flat = maxf(flat, clampf((float(zn.r) + 7.0 - Vector2(x - float(zn.x), z - float(zn.z)).length()) / 7.0, 0.0, 1.0))
	flat = flat * flat * (3.0 - 2.0 * flat)
	var hgt := roll * (1.0 - flat)
	var channel := 0.0
	for hz in hazards:
		channel = maxf(channel, _smooth_box(x - hz.x, z - hz.z, hz.hx, hz.hz, 1.6))
	hgt -= 0.9 * channel
	hgt -= 0.8 * _bump(Vector2(x - POND.x, z - POND.y).length(), POND.z)
	return hgt


## Chasm floor: below the cliffs, so cut off from the high ground (plateaus and bridge).
func is_low(x: float, z: float) -> bool:
	for h in hazards:
		if absf(x - h.x) <= h.hx and absf(z - h.z) <= h.hz:
			return true
	return false


## Cliff walls and bridge supports hide the high ground from anyone in the chasm (and vice versa).
func level_los_blocked(ax: float, az: float, bx: float, bz: float) -> bool:
	if hazards.is_empty() or is_lesson_map(id):  # the Academia's lava is shallow: nothing to climb out of
		return false
	return is_low(ax, az) != is_low(bx, bz)


## Next point a bot should head for when going from `from` to `to` (routes around the chasm over the bridge).
func waypoint(from: Vector2, to: Vector2) -> Vector2:
	if id != "bridge":
		return to
	if is_low(from.x, from.y):  # fell in: the cliffs cannot be climbed, so walk to the foot of the nearest ramp, then up it
		var sx := signf(from.x) if from.x != 0.0 else 1.0
		var sz := signf(to.y) if absf(from.y) < 1.0 else signf(from.y)
		if absf(from.x) < 21.8:
			return Vector2(sx * 23.2, clampf(from.y, -2.0, 2.0))
		return Vector2(sx * 23.2, sz * 12.0)
	if absf(from.x) > 20.0 and absf(from.y) < 9.6 and absf(from.y) >= 4.0:
		return Vector2(signf(from.x) * 23.2, signf(from.y) * 12.0)  # on a ramp: finish the climb before turning
	var across := from.y * to.y < 0.0 and (absf(from.y) > 3.0 or absf(to.y) > 3.0)
	if not across:
		return to
	var entry := Vector2(0.0, signf(from.y) * 10.5)
	if absf(from.y) >= 9.5 and absf(from.x) > 1.2:
		return entry  # line up with the bridge first
	return Vector2(0.0, signf(to.y) * 11.0)
