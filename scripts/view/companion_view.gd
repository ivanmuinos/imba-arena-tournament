class_name CompanionView
extends Node3D
## A class companion (wolf, puma, fairy, imp...) that follows its fighter around. Purely visual: the server knows nothing
## about it; every client draws one next to each unit, from the "companion" block of data/classes.json (a specialization
## may bring its own). Models: assets/third_party/quaternius_animals (CC0); the fairy and the frost crystal are built here.

## Where it walks relative to its owner (metres to the right and behind; flyers slightly ahead so they never hang
## between the camera and the player), and how far it may fall behind before it simply reappears next to them
## (Blink, Disengage, Charge, a respawn).
const SIDE := 1.0
const BACK := 0.35
const FLY_SIDE := 1.05
const FLY_BACK := -0.2
## The goal leads the owner by this much of their velocity, so a running pet keeps up beside them instead of trailing.
const LEAD_S := 0.3
const SNAP_DIST := 7.0
const DEATH_FADE_S := 1.4
const MODELS := "res://assets/third_party/quaternius_animals/%s.glb"
## Reactions to what its owner does (client-side, from the same fx events the unit views use): length in seconds and
## the minimum gap before the same one can play again, so a flurry of hits or casts does not make it twitch.
const REACT_S := {"cast": 0.45, "heal": 0.5, "pounce": 0.35, "hurt": 0.3}
const REACT_GAP_S := 0.6
## A stronger reaction may cut a weaker one short; a weaker one never interrupts.
const REACT_RANK := {"heal": 0, "cast": 1, "pounce": 2, "hurt": 3}

var def: Dictionary
var _world: ArenaWorld
var _player: AnimationPlayer = null
var _clip := ""
var _parts: Array[MeshInstance3D] = []
var _wings: Array[Node3D] = []
var _orbit: Node3D = null
var _fly := 0.0
var _base_scale := 1.0
var _vel := Vector2.ZERO
var _spot := Vector2.ZERO  # where it stands; position adds the reaction's lunge or recoil on top
var _heading := 0.0
var _placed := false
var _pop := 1.0
var _dead_t := 0.0
var _fade := -1.0
var _phase := 0.0
var _act := ""
var _act_t := 0.0
var _act_last := {}
var _clock := 0.0


## The companion of a class (and specialization), {} when it has none.
static func def_for(cls: String, spec := "") -> Dictionary:
	GameData.ensure_loaded()
	if not GameData.classes.has(cls):
		return {}
	return GameData.kit(cls, GameData.normalize_spec(cls, spec)).get("companion", {})


## Menu setting "Compañeros" (on unless the player turned them off).
static func enabled() -> bool:
	return bool(SettingsStore.shared().get_value("companions"))


## Spot beside the owner. `rot` follows the unit views: facing (sin rot, cos rot) on the ground plane.
static func follow_point(owner: Vector2, rot: float, flying := false, owner_vel := Vector2.ZERO) -> Vector2:
	var fwd := Vector2(sin(rot), cos(rot))
	var right := Vector2(-fwd.y, fwd.x)
	return owner + owner_vel * LEAD_S + right * (FLY_SIDE if flying else SIDE) - fwd * (FLY_BACK if flying else BACK)


## Too far to walk there: reappear next to the owner instead.
static func should_snap(cur: Vector2, goal: Vector2) -> bool:
	return cur.distance_to(goal) > SNAP_DIST


## Offset of a reaction `t` seconds into it: x = metres forward along its heading, y = metres up, z = extra turn
## (radians), w = squash (1 = none). Walkers hop, pounce forward and shy back; flyers swoop up and twirl instead.
static func reaction_offset(kind: String, t: float, flying := false) -> Vector4:
	var len_s: float = REACT_S.get(kind, 0.0)
	if len_s <= 0.0 or t < 0.0 or t >= len_s:
		return Vector4(0, 0, 0, 1)
	var u := t / len_s
	var arc := sin(u * PI)  # 0 -> 1 -> 0
	match kind:
		"cast":
			return Vector4(0, arc * 0.35, u * TAU, 1) if flying else Vector4(0, arc * 0.32, 0, 1.0 + arc * 0.08)
		"heal":
			return Vector4(0, arc * 0.2, u * TAU, 1) if flying else Vector4(0, absf(sin(u * TAU)) * 0.16, 0, 1)
		"pounce":
			return Vector4(arc * 0.3, arc * 0.12, 0, 1) if flying else Vector4(arc * 0.55, arc * 0.18, 0, 1)
		"hurt":
			return Vector4(-arc * 0.3, arc * (0.15 if flying else 0.05), 0, 1.0 - arc * 0.18)
	return Vector4(0, 0, 0, 1)


## Plays a reaction to its owner: "cast" (owner cast a spell), "heal" (owner was healed), "pounce" (owner swung a melee
## attack) or "hurt" (owner took a hit). Ignored while hidden, dead or too soon after the same one.
func react(kind: String) -> void:
	if not REACT_S.has(kind) or not visible or _dead_t > 0.0:
		return
	if _clock - float(_act_last.get(kind, -INF)) < REACT_GAP_S:
		return
	if _act != "" and int(REACT_RANK[kind]) < int(REACT_RANK[_act]):
		return
	_act_last[kind] = _clock
	_act = kind
	_act_t = 0.0
	if kind == "hurt" and _player != null and def.has("hit") and _player.has_animation(str(def.hit)):
		_clip = str(def.hit)
		_player.play(_clip, 0.05)


func setup(p_def: Dictionary, team: Color, world: ArenaWorld) -> void:
	def = p_def
	_world = world
	_fly = float(def.get("fly", 0.0))
	_phase = randf() * TAU
	match str(def.get("kind", "model")):
		"fairy": _build_fairy()
		"crystal": _build_crystal()
		_: _build_model()
	_team_mark(team)


# ---------------------------------------------------------------- models

func _build_model() -> void:
	var scene := load(MODELS % str(def.model)) as PackedScene
	var inner: Node3D = scene.instantiate()
	add_child(inner)
	var tint: Dictionary = def.get("tint", {})
	var glow := Color(str(def.get("glow", "#000000")))
	for mi in inner.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		_parts.append(m)
		for s in m.mesh.get_surface_count():
			var src: Material = m.get_active_material(s)
			if not src is StandardMaterial3D:
				continue
			var sm := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			var key := String(src.resource_name)
			if tint.has(key):
				sm.albedo_color = Color(str(tint[key]))
			sm.roughness = 0.85
			sm.metallic = 0.0
			if def.has("glow") and key in ["Eyes", "Belly", "Wings", "Head"]:
				sm.emission_enabled = true
				sm.emission = sm.albedo_color.lerp(glow, 0.5)
				sm.emission_energy_multiplier = 1.6 if key == "Eyes" else 0.35
			if CharacterRig.outlines:
				sm.next_pass = CharacterRig._outline_mat()
			m.set_surface_override_material(s, sm)
	_fit(inner, float(def.get("len", 1.0)))
	var players := inner.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_player = players[0]
		for clip in [str(def.get("idle", "")), str(def.get("move", ""))]:
			if _player.has_animation(clip):
				_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_play(str(def.get("idle", "")))
	if def.has("glow"):
		_motes(glow, 10 if _fly > 0.0 else 6, 0.18)


## Scales the imported model so its longest ground extent is `length` metres and stands it on its feet.
func _fit(inner: Node3D, length: float) -> void:
	var box := AABB()
	var first := true
	for mi in inner.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != inner:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var b: AABB = t * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var k := length / maxf(maxf(box.size.x, box.size.z), 1e-3)
	inner.scale = Vector3.ONE * k
	inner.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	_base_scale = 1.0


## Priest: a tiny sun with four fluttering wings and a sparkle trail.
func _build_fairy() -> void:
	var glow := Color(str(def.get("glow", "#ffe9a8")))
	var core := UnitModels.std(glow, glow, 3.2)
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add(MeshBuilder.sphere(0.075, 10, 6), core)
	var halo := UnitModels.std(Color(glow, 0.22), glow, 1.0)
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add(MeshBuilder.sphere(0.17, 12, 8), halo)
	var wing_mat := UnitModels.std(Color(1.0, 0.97, 0.88, 0.55), glow, 0.8)
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		for upper in [true, false]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.04, 0.02 if upper else -0.03, -0.02)
			pivot.set_meta("side", side)
			add_child(pivot)
			var w := MeshInstance3D.new()
			w.mesh = MeshBuilder.sphere(0.1 if upper else 0.07, 8, 4)
			w.material_override = wing_mat
			w.scale = Vector3(1.0, 0.12, 0.62)
			w.position = Vector3(side * (0.1 if upper else 0.07), 0.05 if upper else -0.03, 0)
			w.rotation.z = side * (0.5 if upper else -0.3)
			pivot.add_child(w)
			_parts.append(w)
			_wings.append(pivot)
	_motes(glow, 14, 0.06)


## Frost mage: a floating ice shard with three smaller shards circling it.
func _build_crystal() -> void:
	var glow := Color(str(def.get("glow", "#7fd8ff")))
	var ice := UnitModels.std(Color(0.72, 0.93, 1.0, 0.82), glow, 1.1, 0.0, 0.08)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var core := _add(MeshBuilder.sphere(0.15, 4, 2), ice)
	core.scale = Vector3(1.0, 1.9, 1.0)
	_orbit = Node3D.new()
	add_child(_orbit)
	for i in 3:
		var a := TAU * i / 3.0
		var shard := MeshInstance3D.new()
		shard.mesh = MeshBuilder.sphere(0.05, 4, 2)
		shard.material_override = ice
		shard.scale = Vector3(1.0, 2.2, 1.0)
		shard.position = Vector3(cos(a) * 0.32, sin(a * 2.0) * 0.06, sin(a) * 0.32)
		_orbit.add_child(shard)
		_parts.append(shard)
	_motes(glow, 10, 0.12)


func _add(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	add_child(m)
	_parts.append(m)
	return m


## Drifting glowing specks (sparkles, embers, frost) left behind as it moves. Off in headless runs.
func _motes(color: Color, amount: int, spread: float) -> void:
	if not UnitView.live_params:
		return
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.gravity = Vector3(0, -0.25, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var mat := UnitModels.std(color, color, 3.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.mesh = MeshBuilder.sphere(0.022, 4, 2)  # cached and shared: the colour goes in the override
	p.material_override = mat
	p.position.y = 0.0 if _fly > 0.0 else 0.35
	add_child(p)


## A small team-coloured ring under walking pets, so in a 3v3 it is clear whose pet it is (flyers hover by their owner).
func _team_mark(team: Color) -> void:
	if _fly > 0.0:
		return
	var ring := MeshInstance3D.new()
	ring.mesh = MeshBuilder.ring(0.2, 0.27, 28)
	var m := UnitModels.std(Color(team, 0.6), team, 1.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	ring.name = "TeamMark"
	add_child(ring)


func _play(clip: String) -> void:
	if _player == null or clip == _clip or not _player.has_animation(clip):
		return
	_clip = clip
	_player.play(clip, 0.25)


# ---------------------------------------------------------------- per frame

## Called by the owner's UnitView every frame. `shown`: the owner is drawn (not stealthed away, not out of sight).
func track(dt: float, now_s: float, owner: Vector3, owner_rot: float, owner_vel: Vector2, shown: bool, alive: bool, see_through: float) -> void:
	_clock += dt
	if not alive:
		_dead_t += dt
	else:
		_dead_t = 0.0
	visible = shown and _dead_t < DEATH_FADE_S
	if not visible:
		_placed = false  # when it shows again (stealth over, back in sight, respawn) it appears next to the owner
		_act = ""
		return
	var goal := follow_point(Vector2(owner.x, owner.z), owner_rot, _fly > 0.0, owner_vel if alive else Vector2.ZERO)
	var cur := _spot
	if not _placed or should_snap(cur, goal):
		cur = goal
		_vel = Vector2.ZERO
		_heading = owner_rot
		_placed = true
		_pop = 0.0
	elif alive:
		var to := goal - cur
		var d := to.length()
		var want := to / d * minf(d * 5.0, maxf(owner_vel.length() * 1.5, 3.0)) if d > 0.05 else Vector2.ZERO
		_vel = _vel.lerp(want, 1.0 - exp(-10.0 * dt))
		cur += _vel * dt
	else:
		_vel = Vector2.ZERO
	_spot = cur
	var spd := _vel.length()
	if spd > 0.35:
		_heading = lerp_angle(_heading, atan2(_vel.x, _vel.y), 1.0 - exp(-10.0 * dt))
	else:
		_heading = lerp_angle(_heading, owner_rot, 1.0 - exp(-3.0 * dt))
	var off := Vector4(0, 0, 0, 1)
	if _act != "":
		_act_t += dt
		off = reaction_offset(_act, _act_t, _fly > 0.0)
		if _act_t >= float(REACT_S[_act]):
			_act = ""
	rotation.y = _heading + off.z + deg_to_rad(float(def.get("yaw", 0.0)))
	position.x = cur.x + sin(_heading) * off.x
	position.z = cur.y + cos(_heading) * off.x
	var ground := _world.h(cur.x, cur.y) if _world != null else 0.0
	position.y = ground + off.y + (_fly + sin(now_s * 2.3 + _phase) * 0.1 if _fly > 0.0 else 0.0)
	var mark := get_node_or_null("TeamMark") as Node3D
	if mark != null:
		mark.position.y = -(position.y - ground) + 0.04
	_pop = minf(1.0, _pop + dt * 4.0)
	var squash := off.w
	scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash)) * _base_scale * (0.4 + 0.6 * ease(_pop, 0.4))

	if _player != null and not (_act == "hurt" and _clip == str(def.get("hit", ""))):
		var moving := spd > 0.4 and alive
		_play(str(def.get("move" if moving else "idle", "")))
		_player.speed_scale = clampf(spd / float(def.get("walk", 1.6)), 0.7, 2.6) if moving and _fly <= 0.0 else 1.0
	for w in _wings:
		var side: float = w.get_meta("side")
		w.rotation.y = side * (0.25 + sin(now_s * 30.0 + _phase) * 0.55)
	if _orbit != null:
		_orbit.rotation.y = now_s * 1.6

	var want_fade := clampf(_dead_t / DEATH_FADE_S, 0.0, 1.0) if not alive else see_through
	if absf(want_fade - _fade) > 0.01:
		_fade = want_fade
		for p in _parts:
			p.transparency = want_fade
