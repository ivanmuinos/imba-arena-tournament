class_name UnitView
extends Node3D
## A fighter in the 3D scene: model, status visuals (sheep, ice, stars, shields...), animations
## (port of UnitView in src/units.ts). Nameplates live in the HUD layer, not here.

const TEAM_COLOR := {"red": Color("#ff4d4d"), "blue": Color("#4da3ff")}
const JUMP_MS := 650.0
## Characters are drawn at this fraction of the model size relative to the arena (gameplay radii and ranges are unchanged:
## PLAYER_R stays 0.5 m, which now matches the model's body). Heights of everything attached to a unit scale with it.
const VS := 0.73

## Changing shader parameters at runtime trips the headless dummy renderer (smoke runs); visuals are irrelevant there.
static var live_params := DisplayServer.get_name() != "headless"

signal landed(pos: Vector3)

var entry: Dictionary
var snap: Dictionary = {}
var is_me := false
var predicted := false
var shown := false
var near_camera := false
## Local player only: facing taken from the camera instead of the server.
var facing_override := NAN

var _world: ArenaWorld
var _body := Node3D.new()
var _model: Dictionary
var _rig: CharacterRig = null
var _companion: CompanionView = null
var _sheep: Node3D
var _ice: MeshInstance3D
var _stars := Node3D.new()
var _spikes := Node3D.new()
var _ring: MeshInstance3D
var _target_ring: MeshInstance3D
var _bubble: MeshInstance3D
var _aura: MeshInstance3D
var _cloud: MeshInstance3D
var _cyclone: Node3D  # druid's Cyclone: a spinning funnel of wind and leaves around the unit
var _cast_orb: MeshInstance3D
var _cast_mat: ShaderMaterial
var _slow_ring: MeshInstance3D
var _cast_school := ""
var _aura_mat: ShaderMaterial
var _bubble_mat: ShaderMaterial
var _marker := Node3D.new()
var _parts: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var _ring_mat: ShaderMaterial
var _rim_mat: ShaderMaterial
var _target_mode := ""
var _swing_t := 0.0
var swing_count := 0
var _swing_heavy := false
var _flash_t := 0.0
var _walk := 0.0
var _cast_pose := 0.0
var _death_t := 0.0
var _speed := 0.0
var _local_jump_at := -1.0
var _was_jumping := false
var _fade := -1.0
var _last_pos := Vector2.ZERO
var _vel := Vector2.ZERO


func setup(p_entry: Dictionary, p_is_me: bool, p_world: ArenaWorld) -> void:
	entry = p_entry
	is_me = p_is_me
	_world = p_world
	var team: Color = TEAM_COLOR[entry.team]
	if CharacterRig.available(entry.cls):
		_rig = CharacterRig.new()
		_rig.setup(entry.cls, team)
		_body.add_child(_rig.root)
		_body.scale = Vector3.ONE * VS
		for p in _rig.parts:
			_parts.append(p)
	else:  # fallback: primitive placeholder models
		_model = UnitModels.build(entry.cls, team)
		_body.add_child(_model.root)
		_body.scale = Vector3.ONE * 0.92 * VS
		_collect_parts(_model.root)
	add_child(_body)
	var pet := CompanionView.def_for(entry.cls, str(entry.get("spec", ""))) if CompanionView.enabled() and not entry.has("dummy") else {}
	if not pet.is_empty():
		_companion = CompanionView.new()
		_companion.setup(pet, team, _world)
		_world.add_child(_companion)  # beside the unit, not under it: it walks on its own
		tree_exiting.connect(func(): if is_instance_valid(_companion): _companion.queue_free())
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.82, 0.74, 0.7)  # white-hot flash on being hit
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_sheep = UnitModels.sheep()
	_sheep.scale = Vector3.ONE * 0.95
	_sheep.visible = false
	add_child(_sheep)
	_ice = MeshInstance3D.new()
	var ice_mesh := BoxMesh.new()
	ice_mesh.size = Vector3(0.95, 1.85, 0.95) * VS
	_ice.mesh = ice_mesh
	var ice_mat := StandardMaterial3D.new()
	ice_mat.albedo_color = Color(0.61, 0.91, 1.0, 0.5)
	ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice_mat.emission_enabled = true
	ice_mat.emission = Color(0.16, 0.56, 0.75)
	ice_mat.emission_energy_multiplier = 0.7
	ice_mat.roughness = 0.1
	_ice.material_override = ice_mat
	_ice.position.y = 0.92 * VS
	_ice.visible = false
	add_child(_ice)

	var star_mat := UnitModels.std(Color("#ffd23a"), Color("#ffb000"), 1.6)
	for i in 3:
		var a := TAU * i / 3.0
		var st := MeshInstance3D.new()
		st.mesh = MeshBuilder.sphere(0.1, 4, 2)
		st.material_override = star_mat
		st.position = Vector3(cos(a) * 0.4, 0, sin(a) * 0.4)
		_stars.add_child(st)
	_stars.position.y = 2.05 * VS
	_stars.visible = false
	add_child(_stars)
	var ice_spike := UnitModels.std(Color("#bff4ff"), Color("#3ab0ff"), 0.9)
	for i in 8:
		var a := TAU * i / 8.0
		var c := MeshInstance3D.new()
		c.mesh = MeshBuilder.cylinder(0.0, 0.1, 0.55, 5)
		c.material_override = ice_spike
		c.position = Vector3(cos(a) * 0.55, 0.22, sin(a) * 0.55)
		c.rotation = Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4)
		_spikes.add_child(c)
	_spikes.visible = false
	add_child(_spikes)

	_ring = _flat_ring(0.62, 0.8 if is_me else 0.72, Color("#ffd27a") if is_me else team, 0.85)
	_ring.position.y = 0.1
	add_child(_ring)
	_target_ring = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.6, 3.6)
	_target_ring.mesh = pm
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load("res://assets/shaders/target_ring.gdshader")
	_target_ring.material_override = _ring_mat
	_target_ring.position.y = 0.14
	_target_ring.visible = false
	_target_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_target_ring)
	_rim_mat = ShaderMaterial.new()
	_rim_mat.shader = load("res://assets/shaders/rim.gdshader")
	_aura = _ground_decal(1.25, Color("#ffb000"), 0.16)
	_aura_mat = _aura.material_override as ShaderMaterial
	_aura.position.y = 0.14
	_aura.visible = false
	add_child(_aura)

	_bubble = MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 1.1 * VS
	bm.height = 2.2 * VS
	_bubble.mesh = bm
	if live_params:
		_bubble_mat = ShaderMaterial.new()
		_bubble_mat.shader = load("res://assets/shaders/spell_aura.gdshader")
		_bubble.material_override = _bubble_mat
	_bubble.position.y = 0.95 * VS
	_bubble.visible = false
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bubble)
	_cloud = MeshInstance3D.new()
	_cloud.mesh = MeshBuilder.sphere(0.45, 7, 4)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.16, 0.14, 0.2, 0.75)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud.material_override = cmat
	_cloud.position.y = 1.5 * VS
	_cloud.visible = false
	add_child(_cloud)
	_cyclone = Node3D.new()
	var wind := StandardMaterial3D.new()
	wind.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wind.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wind.albedo_color = Color(0.8, 1.0, 0.82, 0.35)
	wind.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 6:  # rings widen as they rise: a funnel
		var ring := MeshInstance3D.new()
		ring.mesh = MeshBuilder.torus(0.45 + i * 0.16, 0.05, 20, 4)
		ring.material_override = wind
		ring.position = Vector3(sin(i * 1.7) * 0.08, (0.15 + i * 0.42) * VS, cos(i * 1.7) * 0.08)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cyclone.add_child(ring)
	var leaf_mat := UnitModels.std(Color("#6fcf4a"), Color("#4f9a3a"), 0.4)
	for i in 8:  # leaves caught in the wind
		var leaf := MeshInstance3D.new()
		leaf.mesh = MeshBuilder.box(Vector3(0.16, 0.03, 0.1))
		leaf.material_override = leaf_mat
		var a := TAU * i / 8.0
		leaf.position = Vector3(sin(a) * (0.6 + 0.1 * (i % 3)), (0.4 + 0.3 * i) * VS, cos(a) * (0.6 + 0.1 * (i % 3)))
		leaf.rotation = Vector3(a, a * 2.0, 0.4)
		_cyclone.add_child(leaf)
	_cyclone.visible = false
	add_child(_cyclone)

	_slow_ring = _ground_decal(1.1, Color("#5fc8ff"), 0.2)
	_slow_ring.position.y = 0.16
	_slow_ring.visible = false
	add_child(_slow_ring)
	_cast_orb = MeshInstance3D.new()
	_cast_orb.mesh = MeshBuilder.sphere(0.2, 10, 5)
	if live_params:
		_cast_mat = ShaderMaterial.new()
		_cast_mat.shader = load("res://assets/shaders/spell_orb.gdshader")
		_cast_mat.set_shader_parameter("noise_tex", Textures.spell_noise())
		_cast_mat.set_shader_parameter("energy", 1.8)
		_cast_orb.material_override = _cast_mat
	_cast_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cast_orb.visible = false
	_body.add_child(_cast_orb)

	# Red arrow over the selected target, drawn on top of everything.
	var arrow := StandardMaterial3D.new()
	arrow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow.albedo_color = Color("#ff2a2a")
	arrow.no_depth_test = true
	arrow.render_priority = 10
	var tip := MeshInstance3D.new()
	tip.mesh = MeshBuilder.cylinder(0.32, 0.0, 0.6, 4)
	tip.material_override = arrow
	var stem := MeshInstance3D.new()
	stem.mesh = MeshBuilder.box(Vector3(0.16, 0.4, 0.16))
	stem.material_override = arrow
	stem.position.y = 0.45
	_marker.add_child(tip)
	_marker.add_child(stem)
	_marker.position.y = 3.35 * VS
	_marker.visible = false
	add_child(_marker)
	visible = false


func _flat_ring(inner: float, outer: float, color: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshBuilder.ring(inner, outer, 36)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Flat animated ground decal (spell_ground shader) of radius `r`.
func _ground_decal(r: float, color: Color, fill: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	mi.mesh = pm
	if live_params:
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/spell_ground.gdshader")
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("fill", fill)
		m.set_shader_parameter("energy", 1.4)
		mi.material_override = m
	mi.scale = Vector3(r, 1, r)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _collect_parts(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_parts.append(c)
		_collect_parts(c)


# ---------------------------------------------------------------- state in

## Position/rotation from the interpolation buffer + the newest unit snapshot.
func apply(sample: Dictionary) -> void:
	var s: Dictionary = sample.unit
	if not snap.is_empty() and snap.alive and not s.alive:
		_death_t = 0.001
	if not snap.is_empty() and not snap.alive and s.alive:
		_death_t = 0.0
	snap = s
	if not predicted:
		position.x = sample.x
		position.z = sample.z
	_target_rot = sample.rot
	set_shown(true)


var _target_rot := 0.0


func set_shown(v: bool) -> void:
	shown = v
	visible = v


func set_hidden() -> void:
	set_shown(false)


## Local player: position from client-side prediction.
func drive(x: float, z: float, vx: float, vz: float) -> void:
	position.x = x
	position.z = z
	_speed = Vector2(vx, vz).length()
	_vel = Vector2(vx, vz)


## Local player: start the hop at once instead of waiting for the server.
func jump_now(now_s: float) -> void:
	_local_jump_at = now_s


## Forwards a moment of the fight to the companion (see CompanionView.react).
func companion_react(kind: String) -> void:
	if _companion != null:
		_companion.react(kind)


func swing(heavy: bool) -> void:
	_swing_t = 0.42 if heavy else 0.25
	_swing_heavy = heavy
	companion_react("pounce")
	if _rig != null:
		_rig.swing(Time.get_ticks_msec() / 1000.0, heavy, 1.5)


## Cast gesture right when the server reports an instant cast (channelled casts use the cast loop instead).
func cast_gesture() -> void:
	companion_react("cast")
	if _rig != null and snap.get("cast") == null and snap.get("alive", false):
		_rig.swing(Time.get_ticks_msec() / 1000.0, false, 1.3)


func flash() -> void:
	_flash_t = 0.14
	companion_react("hurt")
	if _rig != null and snap.get("cast") == null:
		_rig.once("hit", Time.get_ticks_msec() / 1000.0, 1.4)
	_refresh_overlay()


## Selection visuals: big animated ring + rim light (hostile = red, friendly = green, hover = faint white) and the arrow.
func set_targeted(mode: String) -> void:
	var alive: bool = not snap.is_empty() and snap.alive and shown
	_target_ring.visible = mode != "" and alive
	_marker.visible = (mode == "lock" or mode == "friend") and alive
	if mode == _target_mode:
		return
	_target_mode = mode
	var c := Color("#5cff8a") if mode == "friend" else (Color("#ffffff") if mode == "hover" else Color("#ff2a2a"))
	_ring_mat.set_shader_parameter("ring_color", c)
	_ring_mat.set_shader_parameter("intensity", 0.9 if mode == "hover" else 2.2)
	_rim_mat.set_shader_parameter("rim_color", c)
	_rim_mat.set_shader_parameter("strength", 0.9 if mode == "hover" else 2.4)
	_target_ring.scale = Vector3.ONE * (1.0 if mode != "hover" else 0.8)
	_marker.get_child(0).material_override.albedo_color = c if mode != "hover" else Color("#ff2a2a")
	_refresh_overlay()


func _refresh_overlay() -> void:
	var o: Material = null
	if _flash_t > 0.0:
		o = _flash_mat
	elif _target_mode != "" and live_params:
		o = _rim_mat
	for p in _parts:
		p.material_overlay = o


## Where a spell leaves the caster: in front of the chest, on the casting side.
func hand_position() -> Vector3:
	var rot: float = _body.rotation.y
	return position + Vector3(sin(rot) * 0.55 + cos(rot) * 0.28, 1.25 * VS, cos(rot) * 0.55 - sin(rot) * 0.28) * Vector3(VS, 1.0, VS)


func head_position() -> Vector3:
	return global_position + Vector3(0, 2.55 * VS, 0)


func is_alive() -> bool:
	return not snap.is_empty() and snap.alive


# ---------------------------------------------------------------- per frame

func update(dt: float, now_s: float) -> void:
	if _companion != null:
		var face: float = facing_override if not is_nan(facing_override) else _target_rot
		_companion.track(dt, now_s, position, face, _vel, shown and not snap.is_empty(), snap.is_empty() or bool(snap.alive), maxf(_fade, 0.0))
	if not shown or snap.is_empty():
		return
	var s := snap
	var cc: Dictionary = s.cc
	var b: Dictionary = s.buffs
	if not predicted:
		_vel = Vector2(position.x - _last_pos.x, position.z - _last_pos.y) / maxf(dt, 1e-4)
		_speed = _vel.length()
	_last_pos = Vector2(position.x, position.z)
	var rot: float = facing_override if not is_nan(facing_override) else _target_rot
	_body.rotation.y = lerp_angle(_body.rotation.y, rot, 1.0 - exp(-18.0 * dt))
	_sheep.rotation.y = _body.rotation.y + sin(now_s * 3.0) * 0.3
	if b.has("storm") and s.alive:
		_body.rotation.y += dt * 16.0  # Bladestorm spin
	var sheep: bool = cc.has("incap") and cc.get("incapKind", "") == "poly" and s.alive
	_sheep.visible = sheep
	_body.visible = not sheep
	_ice.visible = cc.has("incap") and cc.get("incapKind", "") == "freeze" and s.alive
	_stars.visible = (cc.has("stun") or cc.has("fear")) and s.alive
	_stars.rotation.y = now_s * (-7.0 if cc.has("fear") else 5.0)
	for st in _stars.get_children():
		var sm := (st as MeshInstance3D).material_override as StandardMaterial3D
		sm.emission = Color("#a64dff") if cc.has("fear") else Color("#ffb000")
		sm.albedo_color = Color("#c77dff") if cc.has("fear") else Color("#ffd23a")
	_cloud.visible = cc.has("incap") and cc.get("incapKind", "") == "blind" and s.alive
	_cloud.rotation.y = now_s * 1.5
	_cyclone.visible = cc.has("incap") and cc.get("incapKind", "") == "cyclone" and s.alive
	_cyclone.rotation.y = now_s * 9.0
	_spikes.visible = cc.has("root") and s.alive
	_ring.visible = s.alive
	if _marker.visible:
		_marker.position.y = 3.35 * VS + sin(now_s * 5.0) * 0.12
		_marker.rotation.y = now_s * 2.0

	# Jump arc (650 ms, ~1 m high): the local player starts it instantly.
	var jt: float = (now_s - _local_jump_at) * 1000.0 if _local_jump_at >= 0.0 else float(s.jump)
	var k := jt / JUMP_MS if jt >= 0.0 and jt < JUMP_MS else -1.0
	if _local_jump_at >= 0.0 and k < 0.0:
		_local_jump_at = -1.0
	position.y = _world.h(position.x, position.z) + (4.0 * k * (1.0 - k) if k >= 0.0 else 0.0)
	var jumping := k >= 0.0
	if jumping and not _was_jumping and _rig != null:
		_rig.jump(now_s)
	if _was_jumping and not jumping and s.alive:
		landed.emit(Vector3(position.x, _world.h(position.x, position.z), position.z))
	_was_jumping = jumping

	var shield_color = null
	if b.has("shield"):
		shield_color = Color(0.5, 0.86, 1.0)
	elif b.has("absorb"):
		shield_color = Color(1.0, 0.82, 0.5)
	elif b.has("darkpact"):
		shield_color = Color(0.7, 0.45, 0.95)
	_bubble.visible = shield_color != null and s.alive and live_params
	if shield_color != null and live_params:
		_bubble_mat.set_shader_parameter("color", Color(0.35, 0.8, 1.0) if b.has("shield") else Color(0.65, 0.4, 0.95) if (b.has("darkpact") and not b.has("absorb")) else Color(1.0, 0.8, 0.35))
	_bubble.scale = Vector3.ONE * (1.0 + sin(now_s * 6.0) * 0.03)
	var aura_color = null
	if cc.has("marked"): aura_color = Color("#ff2a2a")
	elif b.has("storm"): aura_color = Color("#ffd166")
	elif b.has("crit"): aura_color = Color("#ff9a00")
	elif b.has("wall"): aura_color = Color("#c9ced6")
	elif b.has("haste"): aura_color = Color("#5cff8a")
	elif b.has("hot"): aura_color = Color("#7dff9a")
	_aura.visible = aura_color != null and s.alive and live_params
	if aura_color != null:
		if live_params:
			_aura_mat.set_shader_parameter("color", aura_color)
			_aura_mat.set_shader_parameter("core", aura_color.lightened(0.5))
		var pulse := 1.25 * (1.0 + sin(now_s * 8.0) * 0.06)
		_aura.scale = Vector3(pulse, 1, pulse)
	_slow_ring.visible = cc.has("slow") and s.alive and live_params
	# Glow at the hand while casting, tinted by the spell's school and growing as the cast completes.
	var casting_now: bool = s.cast != null and s.alive
	_cast_orb.visible = casting_now and live_params
	if casting_now:
		var abil: Array = GameData.abilities(entry.cls, str(entry.get("spec", "")))
		var slot := int(s.cast.slot)
		var school := SpellSchools.school_of(str(abil[slot].id)) if slot >= 0 and slot < abil.size() else "arcane"
		if school != _cast_school:
			_cast_school = school
			var pal := SpellSchools.palette(school)
			if live_params:
				_cast_mat.set_shader_parameter("core", pal.core)
				_cast_mat.set_shader_parameter("mid", pal.mid)
				_cast_mat.set_shader_parameter("edge", pal.edge)
		var prog: float = 1.0 - float(s.cast.left) / maxf(1.0, float(s.cast.total))
		var sz := 0.6 + prog * 1.1 + sin(now_s * 18.0) * 0.08
		_cast_orb.scale = Vector3.ONE * sz
		_cast_orb.position = Vector3(0.28, 1.35, 0.5)

	# See-through when stealthed, or when the camera is right on top of the unit.
	var want := 0.82 if near_camera else (0.75 if b.has("stealth") else 0.0)
	if want != _fade:
		_fade = want
		for p in _parts:
			p.transparency = want

	if _rig != null:
		var spd: float = GameData.classes[entry.cls].speed
		var moving_r := _speed > 0.5 and not cc.has("stun") and not cc.has("incap")
		_rig.move_xy = LocoBlend.blend_xy(_vel, _body.rotation.y, spd)
		_rig.drive(now_s, s.alive, cc.has("stun") or cc.has("incap") or cc.has("fear"), s.cast != null, float(s.cast.total) if s.cast != null else 0.0, moving_r, _speed / spd)
		_ring.visible = s.alive
		if _flash_t > 0.0:
			_flash_t -= dt
			if _flash_t <= 0.0:
				_refresh_overlay()
		return
	if not s.alive:
		# Death: topple and sink (sideways so the corpse reads from the high camera).
		_death_t = minf(1.0, _death_t + dt * 1.5)
		_body.rotation.z = _death_t * 1.45
		_body.position.y = _death_t * 0.25
		return
	_body.rotation.z = 0.0

	var moving := _speed > 0.5 and not cc.has("stun") and not cc.has("incap")
	_walk += dt * (9.0 if moving else 0.0)
	var sw := sin(_walk) if moving else 0.0
	_body.position.y = absf(cos(_walk)) * 0.06 if moving else 0.0
	var legs: Array = _model.legs
	for i in legs.size():
		legs[i].rotation.x = (-sw if i else sw) * 0.6
	_model.root.rotation.z = sw * 0.05 if entry.cls == "mage" else 0.0

	var casting := 1.0 if s.cast != null else 0.0
	_cast_pose += (casting - _cast_pose) * (1.0 - exp(-10.0 * dt))
	var weapon: Node3D = _model.weapon
	if entry.cls in ["mage", "priest", "warlock", "druid"]:
		weapon.rotation.x = -_cast_pose * 0.9
		weapon.position.y = _cast_pose * 0.3
	elif entry.cls == "hunter":
		weapon.rotation.y = _cast_pose * 0.6
	# Melee swing: wind up, then slash forward.
	if _swing_t > 0.0:
		_swing_t = maxf(0.0, _swing_t - dt)
		var total := 0.42 if _swing_heavy else 0.25
		var k2 := 1.0 - _swing_t / total
		weapon.rotation.x = -(k2 / 0.35) * 1.4 if k2 < 0.35 else -1.4 + ((k2 - 0.35) / 0.65) * 2.6
	elif entry.cls == "warrior" or entry.cls == "rogue":
		weapon.rotation.x *= 0.8
	var glow: StandardMaterial3D = _model.glow
	if glow != null:
		glow.emission_energy_multiplier = 1.6 + _cast_pose * (2.0 + sin(now_s * 20.0))

	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			_refresh_overlay()
