class_name FxManager
extends Node3D
## Projectiles, area markers, traps, power-ups and one-shot effects (port of src/fx.ts).
## Everything is driven by the snapshot lists and the fx events the server sends.

signal shake(amount: float, x: float, z: float)

const POOL := 64

const COL_FIRE := Color("#ff6a10")
const COL_HOT := Color("#ffd27a")
const COL_ICE := Color("#7fdbff")
const COL_ARCANE := Color("#c77dff")
const COL_ARROW := Color("#ffb060")
const COL_CONC := Color("#4da3ff")
const COL_SILENCE := Color("#b05cff")
const COL_SMOKE := Color("#553322")

const ORB := preload("res://assets/shaders/spell_orb.gdshader")
const TRAIL := preload("res://assets/shaders/spell_trail.gdshader")
const GROUND := preload("res://assets/shaders/spell_ground.gdshader")
const SCORCH := preload("res://assets/shaders/scorch.gdshader")
const SLASH := preload("res://assets/shaders/slash.gdshader")
const LIGHTS := 6
const SCORCHES := 14

## kind -> {color, size, arrow, trail}
const PROJ_STYLE := {
	"shadowbolt": {"color": Color("#a368df"), "size": 0.35, "arrow": false, "trail": 22},
	"fireball": {"color": COL_FIRE, "size": 0.35, "arrow": false, "trail": 18},
	"pyro": {"color": COL_FIRE, "size": 0.6, "arrow": false, "trail": 30},
	"shot": {"color": COL_ARROW, "size": 0.2, "arrow": true, "trail": 10},
	"aimed": {"color": COL_HOT, "size": 0.26, "arrow": true, "trail": 16},
	"conc": {"color": COL_CONC, "size": 0.22, "arrow": true, "trail": 12},
	"silence": {"color": COL_SILENCE, "size": 0.22, "arrow": true, "trail": 12},
	"volley": {"color": COL_FIRE, "size": 0.22, "arrow": true, "trail": 8},
	"smite": {"color": Color("#ffe08a"), "size": 0.3, "arrow": false, "trail": 14},
	"frostbolt": {"color": COL_ICE, "size": 0.38, "arrow": false, "trail": 22},
	"icelance": {"color": Color("#d8f6ff"), "size": 0.22, "arrow": true, "trail": 14},
	"wrath": {"color": Color("#8fe86a"), "size": 0.3, "arrow": false, "trail": 14},
	"rifle": {"color": Color("#ffe9a0"), "size": 0.1, "arrow": true, "trail": 22},
	"tornado": {"color": Color("#c8f4ff"), "size": 0.8, "arrow": false, "trail": 26},
	"headshot": {"color": Color("#fff2c0"), "size": 0.13, "arrow": true, "trail": 30},
	"awp": {"color": Color("#ffffff"), "size": 0.16, "arrow": true, "trail": 44},
}

var world: ArenaWorld

var _projs := {}
var _aoes := {}
var _zones := {}   # persistent area effects (blizzard): id -> {ring, snow}
var _traps := {}
var _powers := {}
var _flashes: Array = []
var _beams := {}
var _pool: Array = []  # {node, free_at}
var _pool_idx := 0
var _particle_mesh: QuadMesh
## Set by apply_quality(): particle multiplier, short impact lights, scorch decals.
var q := {"particles": 1.0, "fx_lights": true, "decals": true}
var _lights: Array = []   # {light, t, dur, energy}
var _scorches: Array = []  # {mesh, mat, t}
var _scorch_i := 0
var _mats := {}
## Set by the match each snapshot: world positions of casters' hands, so projectiles visibly leave the hand/staff tip.
var hands: Array = []
## false under the headless dummy renderer, whose material storage rejects shader materials on long-lived meshes (smoke runs).
var _fancy := DisplayServer.get_name() != "headless"


func setup(p_world: ArenaWorld) -> void:
	world = p_world
	_particle_mesh = QuadMesh.new()
	_particle_mesh.size = Vector2(0.4, 0.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = Textures.glow_dot()
	mat.albedo_color = Color(1.35, 1.35, 1.35, 1.0)
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	_particle_mesh.material = mat
	for i in POOL:
		var p := _make_particles()
		add_child(p)
		_pool.append({"node": p, "free_at": 0.0})
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 7.0
		l.shadow_enabled = false
		add_child(l)
		_lights.append({"light": l, "t": 1.0, "dur": 0.3, "energy": 0.0})
	for i in (SCORCHES if _fancy else 0):
		var m := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2, 2)
		m.mesh = pm
		var smat := ShaderMaterial.new()
		smat.shader = SCORCH
		smat.set_shader_parameter("noise_tex", Textures.spell_noise())
		m.material_override = smat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_scorches.append({"mesh": m, "mat": smat, "t": 99.0})


func apply_quality(d: Dictionary) -> void:
	q = {"particles": float(d.get("particles", 1.0)), "fx_lights": bool(d.get("fx_lights", true)), "decals": bool(d.get("decals", true))}


## Shader material for a school's orb / trail / ground effect (cached per school+kind).
func _school_mat(kind: String, school: String, energy := 2.4) -> ShaderMaterial:
	var pal := SpellSchools.palette(school)
	var m := ShaderMaterial.new()
	match kind:
		"orb":
			m.shader = ORB
			m.set_shader_parameter("core", pal.core)
			m.set_shader_parameter("mid", pal.mid)
			m.set_shader_parameter("edge", pal.edge)
			m.set_shader_parameter("noise_tex", Textures.spell_noise())
		"trail":
			m.shader = TRAIL
			m.set_shader_parameter("core", pal.core)
			m.set_shader_parameter("mid", pal.mid)
			m.set_shader_parameter("noise_tex", Textures.spell_noise())
		"ground":
			m.shader = GROUND
			m.set_shader_parameter("color", pal.mid)
			m.set_shader_parameter("core", pal.core)
	m.set_shader_parameter("energy", energy)
	return m  # a fresh material each time: effects animate their own parameters


func _light_flash(pos: Vector3, color: Color, energy: float, dur: float) -> void:
	if not q.fx_lights:
		return
	var best: Dictionary = _lights[0]
	for l in _lights:
		if l.t >= l.dur:
			best = l
			break
		if l.t > best.t:
			best = l
	best.t = 0.0
	best.dur = dur
	best.energy = energy
	best.light.position = pos
	best.light.light_color = color


func _scorch(pos: Vector3, r: float) -> void:
	if not q.decals or not _fancy:
		return
	var s: Dictionary = _scorches[_scorch_i]
	_scorch_i = (_scorch_i + 1) % SCORCHES
	var m: MeshInstance3D = s.mesh
	m.position = Vector3(pos.x, _y(pos.x, pos.z) + 0.05, pos.z)
	m.rotation.y = randf() * TAU
	m.scale = Vector3(r, 1, r)
	m.visible = true
	s.t = 0.0


func _make_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _particle_mesh
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.direction = Vector3.UP
	p.spread = 180.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = ramp
	return p


## One-shot burst of glowing particles.
func burst(pos: Vector3, n: int, speed: float, color: Color, life: float, size: float, gravity := 0.0) -> void:
	var slot: Dictionary = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL
	var p: CPUParticles3D = slot.node
	p.emitting = false
	p.position = pos
	p.amount = maxi(1, int(round(n * q.particles)))
	p.lifetime = life
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.3
	p.color = color
	p.restart()
	p.emitting = true


func _y(x: float, z: float) -> float:
	return world.h(x, z)


# ---------------------------------------------------------------- snapshot sync

func sync_projectiles(list: Array, now_s: float) -> void:
	var seen := {}
	for p in list:
		seen[p.id] = true
		var v: Dictionary = _projs.get(p.id, {})
		if v.is_empty():
			var node := _make_proj(p.kind)
			add_child(node)
			_start_trails(node)
			v = {"node": node, "kind": p.kind, "offset": Vector3.ZERO, "born": now_s}
			var spawn := Vector3(p.x, _y(p.x, p.z) + 1.1 * UnitView.VS, p.z)
			var best := 3.0
			for h in hands:
				var d := (h as Vector3).distance_to(spawn)
				if d < best:
					best = d
					v.offset = (h as Vector3) - spawn
			_projs[p.id] = v
		v.x = p.x
		v.z = p.z
		v.vx = p.vx
		v.vz = p.vz
		v.at = now_s
	for id in _projs.keys():
		if not seen.has(id):
			_projs[id].node.queue_free()
			_projs.erase(id)


func _emissive(color: Color, energy := 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * energy
	return m


func _make_proj(kind: String) -> Node3D:
	if not _fancy:
		return Node3D.new()
	var st: Dictionary = PROJ_STYLE.get(kind, PROJ_STYLE.fireball)
	var school := SpellSchools.school_of(kind)
	var pal := SpellSchools.palette(school)
	var g := Node3D.new()
	var r: float = st.size
	if not st.arrow:
		var a := MeshInstance3D.new()
		a.mesh = MeshBuilder.sphere(r * 1.5, 14, 8)
		a.material_override = _school_mat("orb", school, 1.0 if school == "frost" else 1.7) if _fancy else _emissive(pal.mid)
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(a)
		var b := MeshInstance3D.new()
		b.mesh = MeshBuilder.sphere(r * 0.55, 8, 4)
		b.material_override = _emissive(pal.core, 3.0)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(b)
	else:
		var shaft := MeshInstance3D.new()
		shaft.mesh = MeshBuilder.cylinder(0.03, 0.03, 1.1, 5)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color("#5a3a1e")
		shaft.material_override = sm
		shaft.rotation.x = PI / 2
		var tip := MeshInstance3D.new()
		tip.mesh = MeshBuilder.cylinder(0.0, 0.08, 0.25, 6)
		tip.material_override = _emissive(pal.mid, 3.0)
		tip.rotation.x = PI / 2
		tip.position.z = 0.6
		g.add_child(shaft)
		g.add_child(tip)
		var head := MeshInstance3D.new()
		head.mesh = MeshBuilder.sphere(r * 0.9, 8, 4)
		head.material_override = _school_mat("orb", school, 1.5) if _fancy else _emissive(pal.mid)
		head.position.z = 0.62
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(head)
	# Comet tail: a cone behind the projectile with a falling-off, noisy alpha.
	var length := r * (16.0 if not st.arrow else 12.0)
	var tail := MeshInstance3D.new()
	tail.mesh = MeshBuilder.cylinder(r * (1.1 if not st.arrow else 0.55), 0.0, length, 10)
	var tm := _school_mat("trail", school, 0.9 if school == "frost" else 1.5)
	tm.set_shader_parameter("length_m", length)
	tail.material_override = tm
	tail.rotation.x = PI / 2  # axis along the flight direction, head at the origin, tail behind
	tail.position.z = -length / 2.0
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(tail)
	if q.fx_lights:
		var l := OmniLight3D.new()
		l.light_color = pal.mid
		l.light_energy = 1.4
		l.omni_range = 6.0
		l.shadow_enabled = false
		g.add_child(l)
	# Tracer: embers left behind in world space as the projectile flies.
	var trail := _make_particles()
	trail.one_shot = false
	trail.explosiveness = 0.0
	trail.amount = maxi(2, int(st.trail * q.particles))
	trail.lifetime = 0.35
	trail.emission_sphere_radius = 0.06
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.5
	trail.scale_amount_min = r * 1.0
	trail.scale_amount_max = r * 1.7
	trail.color = pal.mid
	g.add_child(trail)  # starts emitting once in the tree (see _start_trails)
	return g


func _start_trails(n: Node) -> void:
	for c in n.get_children():
		if c is CPUParticles3D and not c.one_shot:
			c.emitting = true


func sync_aoes(list: Array, now_s: float) -> void:
	var seen := {}
	var zseen := {}
	for a in list:
		if a.get("kind", "meteor") == "blizzard":
			zseen[a.id] = true
			_sync_zone(a)
			continue
		seen[a.id] = true
		var v: Dictionary = _aoes.get(a.id, {})
		if v.is_empty():
			var ring := MeshInstance3D.new()
			if not _fancy:
				add_child(ring)
				var plain := Node3D.new()
				add_child(plain)
				v = {"ring": ring, "rock": plain, "total": maxf(a.left, 1.0)}
				_aoes[a.id] = v
				v.left = a.left
				v.at = now_s
				continue
			var pm := PlaneMesh.new()
			pm.size = Vector2(2, 2)
			ring.mesh = pm
			ring.material_override = _school_mat("ground", "fire", 1.5)
			ring.scale = Vector3(a.r, 1, a.r)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var rock := Node3D.new()
			var core := MeshInstance3D.new()
			core.mesh = MeshBuilder.sphere(0.8, 12, 6)
			core.material_override = _school_mat("orb", "fire", 1.8)
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rock.add_child(core)
			var tail := MeshInstance3D.new()
			tail.mesh = MeshBuilder.cylinder(1.0, 0.0, 9.0, 10)
			var tmat := _school_mat("trail", "fire", 1.6)
			tmat.set_shader_parameter("length_m", 9.0)
			tail.material_override = tmat
			var back := Vector3(6.0, 18.0, -3.0).normalized()  # the meteor falls along -back: its tail points back up the path
			tail.basis = Basis(Quaternion(Vector3.DOWN, back))
			tail.position = back * 4.5
			tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rock.add_child(tail)
			var trail := _make_particles()
			trail.one_shot = false
			trail.explosiveness = 0.0
			trail.amount = maxi(4, int(26 * q.particles))
			trail.lifetime = 0.5
			trail.initial_velocity_min = 0.0
			trail.initial_velocity_max = 1.0
			trail.scale_amount_min = 0.9
			trail.scale_amount_max = 1.5
			trail.color = COL_FIRE
			rock.add_child(trail)
			add_child(ring)
			add_child(rock)
			_start_trails(rock)
			v = {"ring": ring, "rock": rock, "total": maxf(a.left, 1.0)}
			_aoes[a.id] = v
		v.left = a.left
		v.at = now_s
		v.ring.position = Vector3(a.x, _y(a.x, a.z) + 0.2, a.z)
	for id in _zones.keys():
		if not zseen.has(id):
			_zones[id].ring.queue_free()
			_zones[id].snow.queue_free()
			_zones.erase(id)
	for id in _aoes.keys():
		if not seen.has(id):
			_aoes[id].ring.queue_free()
			_aoes[id].rock.queue_free()
			_aoes.erase(id)


## Blizzard: a frosty ground decal plus snow falling over the whole area while it lasts.
func _sync_zone(a: Dictionary) -> void:
	var z: Dictionary = _zones.get(a.id, {})
	if z.is_empty():
		var ring := MeshInstance3D.new()
		var snow := CPUParticles3D.new()
		if _fancy:
			var pm := PlaneMesh.new()
			pm.size = Vector2(2, 2)
			ring.mesh = pm
			var mat := _school_mat("ground", "frost", 1.3)
			mat.set_shader_parameter("fill", 0.38)
			ring.material_override = mat
			ring.scale = Vector3(a.r, 1, a.r)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			snow.mesh = _particle_mesh
			snow.amount = maxi(10, int(70 * q.particles))
			snow.lifetime = 1.3
			snow.local_coords = false
			snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			snow.emission_sphere_radius = float(a.r)
			snow.direction = Vector3.DOWN
			snow.spread = 12.0
			snow.gravity = Vector3(1.5, -9.0, 0.5)
			snow.initial_velocity_min = 2.0
			snow.initial_velocity_max = 5.0
			snow.scale_amount_min = 0.2
			snow.scale_amount_max = 0.45
			snow.color = Color("#e8f8ff")
			snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		add_child(snow)
		snow.position = Vector3(a.x, _y(a.x, a.z) + 6.0, a.z)
		ring.position = Vector3(a.x, _y(a.x, a.z) + 0.2, a.z)
		snow.emitting = _fancy
		z = {"ring": ring, "snow": snow}
		_zones[a.id] = z
	z.left = a.left
	var m := (z.ring as MeshInstance3D).material_override as ShaderMaterial
	if m != null:
		m.set_shader_parameter("fade", clampf(float(a.left) / 600.0, 0.0, 1.0) * 0.85)


## Cone of flame in front of the caster (dragon's breath).
func breath(x: float, z: float, dx: float, dz: float, r: float) -> void:
	var y := _y(x, z) + 1.0 * UnitView.VS
	for i in 4:
		var d := r * (0.25 + 0.25 * i)
		var pos := Vector3(x + dx * d, y, z + dz * d)
		burst(pos, 34 + i * 8, 4.0 + i * 1.5, COL_FIRE, 0.55 + i * 0.1, 0.8 + i * 0.3, -1.0)
		burst(pos, 14, 2.5, COL_HOT, 0.4, 0.6 + i * 0.2)
		_flash_sphere(pos, "fire", 0.3 + i * 0.12, 0.35, 2.2)
	_light_flash(Vector3(x + dx * r * 0.5, y, z + dz * r * 0.5), COL_FIRE, 3.0, 0.4)
	shake.emit(0.1, x, z)


func sync_traps(list: Array) -> void:
	var seen := {}
	for t in list:
		seen[t.id] = true
		var g: Node3D = _traps.get(t.id)
		if g == null:
			g = Node3D.new()
			var cone_mat := UnitModels.std(Color("#bff4ff"), Color("#3ab0ff"), 0.6)
			for i in 6:
				var a := TAU * i / 6.0
				var c := MeshInstance3D.new()
				c.mesh = MeshBuilder.cylinder(0.0, 0.08, 0.3, 5)
				c.material_override = cone_mat
				c.position = Vector3(cos(a) * 0.45, 0.15, sin(a) * 0.45)
				g.add_child(c)
			var disc := MeshInstance3D.new()
			disc.mesh = MeshBuilder.ring(0.3, 0.55, 24)
			var dm := StandardMaterial3D.new()
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dm.albedo_color = Color(0.5, 0.86, 1.0, 0.6)
			dm.cull_mode = BaseMaterial3D.CULL_DISABLED
			disc.material_override = dm
			disc.position.y = 0.08
			g.add_child(disc)
			g.position = Vector3(t.x, _y(t.x, t.z), t.z)
			add_child(g)
			_traps[t.id] = g
		g.set_meta("armed", t.armed)
	for id in _traps.keys():
		if not seen.has(id):
			_traps[id].queue_free()
			_traps.erase(id)


func sync_powers(list: Array) -> void:
	var seen := {}
	for p in list:
		seen[p.id] = true
		if _powers.has(p.id):
			continue
		var spec: Dictionary = GameData.powers[p.kind]
		var col := Color.hex(int(spec.color) << 8 | 0xff)
		var g := Node3D.new()
		var gem := MeshInstance3D.new()
		gem.mesh = MeshBuilder.sphere(0.45, 4, 2)
		gem.material_override = UnitModels.std(col, col, 1.8)
		gem.position.y = 1.2
		gem.name = "gem"
		var base := MeshInstance3D.new()
		base.mesh = MeshBuilder.ring(0.6, 0.9, 32)
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.albedo_color = Color(col.r * 1.5, col.g * 1.5, col.b * 1.5, 0.7)
		base.material_override = bm
		base.position.y = 0.12
		var label := Label3D.new()
		label.text = spec.name
		label.font_size = 40
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = col.lightened(0.5)
		label.outline_size = 8
		label.position.y = 2.2
		g.add_child(gem)
		g.add_child(base)
		g.add_child(label)
		g.position = Vector3(p.x, _y(p.x, p.z), p.z)
		add_child(g)
		_powers[p.id] = g
	for id in _powers.keys():
		if not seen.has(id):
			_powers[id].queue_free()
			_powers.erase(id)


# ---------------------------------------------------------------- one-shot events

## School-shaped impact: flash orb, particle burst in the school's palette, light flash, and per-school extras.
func impact(school: String, pos: Vector3, scale := 1.0, ground_ring := true) -> void:
	var pal := SpellSchools.palette(school)
	var b := SpellSchools.burst(school, 1.0)
	_flash_sphere(pos, school, 0.45 * scale, 0.3, 2.6 * scale)
	burst(pos, int(b.n * scale), b.speed * scale, pal.mid, b.life, b.size * scale, b.gravity)
	burst(pos, int(b.n * 0.5 * scale), b.speed * 0.55 * scale, pal.core, b.life * 0.6, b.size * 0.6 * scale, 0.0)
	_light_flash(pos + Vector3(0, 0.6, 0), pal.mid, 3.0 * scale, 0.28)
	var floor_y := _y(pos.x, pos.z)
	match school:
		"fire":
			burst(pos, int(10 * scale), 2.0, COL_SMOKE, 1.1, 0.9 * scale, -1.2)
			if scale >= 0.8:
				_scorch(pos, 1.3 * scale)
		"frost":
			if ground_ring:
				_flash_ground(Vector3(pos.x, floor_y + 0.12, pos.z), school, 0.5, 1.4 * scale)
			burst(pos, int(14 * scale), 4.0, Color("#ffffff"), 0.5, 0.2 * scale, 9.0)  # falling shards
		"arcane":
			if ground_ring:
				_flash_ground(Vector3(pos.x, floor_y + 0.12, pos.z), school, 0.55, 1.6 * scale)
		"holy":
			_flash_column(Vector3(pos.x, floor_y, pos.z), school, 0.5, scale)
			if ground_ring:
				_flash_ground(Vector3(pos.x, floor_y + 0.12, pos.z), school, 0.6, 1.8 * scale)
		"shadow":
			burst(pos, int(14 * scale), 2.0, pal.edge, 1.0, 0.9 * scale, 0.0)
			if ground_ring:
				_flash_ground(Vector3(pos.x, floor_y + 0.12, pos.z), school, 0.6, 1.5 * scale)
		"nature":
			burst(pos, int(12 * scale), 3.0, Color("#9cff7a"), 0.9, 0.3 * scale, 3.0)  # leaves
		_:
			burst(pos, int(8 * scale), 3.0, Color("#8a7a68"), 0.5, 0.6 * scale, -0.5)  # dust


## Small school-coloured flash where a spell lands on a unit.
func hit_impact(x: float, z: float, ability: String, crit: bool) -> void:
	var school := SpellSchools.school_of(ability)
	impact(school, Vector3(x, _y(x, z) + 1.3 * UnitView.VS, z), 0.7 if crit else 0.42, false)


## Glow at the caster's hand while a spell goes off.
func cast_glow(x: float, z: float, rot: float, ability: String) -> void:
	var school := SpellSchools.school_of(ability)
	var pos := Vector3(x + sin(rot) * 0.55, _y(x, z) + 1.35 * UnitView.VS, z + cos(rot) * 0.55)
	_flash_sphere(pos, school, 0.22, 0.34, 1.6)
	var pal := SpellSchools.palette(school)
	burst(pos, 8, 1.5, pal.mid, 0.35, 0.28)
	_light_flash(pos, pal.mid, 1.6, 0.3)


func pickup(x: float, z: float, kind: String) -> void:
	var c := Color.hex(int(GameData.powers[kind].color) << 8 | 0xff)
	var y := _y(x, z)
	burst(Vector3(x, y + 1.2, z), 45, 6.0, c, 0.8, 0.6, -1.0)
	burst(Vector3(x, y + 0.3, z), 24, 3.0, c, 0.7, 0.5, -2.0)
	_flash_column(Vector3(x, y, z), "holy", 0.6, 1.0, c)


func heal(x: float, z: float) -> void:
	impact("nature", Vector3(x, _y(x, z) + 1.0, z), 0.55, false)
	burst(Vector3(x, _y(x, z) + 0.4, z), 16, 1.2, Color("#c8ffd0"), 1.1, 0.3, -1.5)


func boom(x: float, z: float, r: float, kind: String) -> void:
	var meteor := kind == "meteor"
	var y := _y(x, z)
	impact("fire", Vector3(x, y + 0.6, z), 2.2 if meteor else clampf(r * 0.45, 0.5, 1.3), false)
	_flash_ground(Vector3(x, y + 0.14, z), "fire", 0.45 if meteor else 0.3, r * (1.3 if meteor else 1.0))
	if meteor:
		burst(Vector3(x, y + 0.6, z), 70, 11.0, COL_FIRE, 0.7, 0.9, 9.0)
		burst(Vector3(x, y + 0.4, z), 20, 2.0, COL_SMOKE, 1.4, 1.6, -1.0)
	shake.emit(0.7 if meteor else 0.15, x, z)


## Steel Tempest: a quick streak of wind along the thrust.
func tempest(x: float, z: float, dx: float, dz: float, r: float) -> void:
	var y := _y(x, z)
	for i in 8:
		var k := (i + 0.5) / 8.0
		burst(Vector3(x + dx * r * k, y + 1.0, z + dz * r * k), 3, 1.5, Color("#d8f6ff"), 0.3, 0.18, 0.0)


## Wind wall: a pale, swirling curtain across the caster's front that fades after `ms`.
func windwall(x: float, z: float, dx: float, dz: float, hw: float, ms: float) -> void:
	var y := _y(x, z)
	var m := MeshInstance3D.new()
	m.mesh = MeshBuilder.box(Vector3(hw * 2.0, 3.0, 0.25))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.82, 0.96, 1.0, 0.32)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	m.position = Vector3(x, y + 1.5, z)
	m.rotation.y = atan2(dx, dz)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	for i in 6:
		burst(Vector3(x - dz * hw * (i / 2.5 - 1.0), y + 0.5, z + dx * hw * (i / 2.5 - 1.0)), 4, 2.0, Color("#e8faff"), 0.6, 0.25, -3.0)
	var tw := m.create_tween()
	tw.tween_interval(maxf(0.0, ms / 1000.0 - 0.4))
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(m.queue_free)


## Flashbang: a white blast on the ground and a spray of bright sparks.
func flash(x: float, z: float, r: float) -> void:
	var y := _y(x, z)
	_flash_ground(Vector3(x, y + 0.15, z), "holy", 0.6, r)
	impact("holy", Vector3(x, y + 0.6, z), 1.4, false)
	burst(Vector3(x, y + 0.6, z), 50, r * 2.4, Color("#ffffff"), 0.35, 0.35, 2.0)
	shake.emit(0.25, x, z)


func nova(x: float, z: float, r: float) -> void:
	var y := _y(x, z)
	_flash_ground(Vector3(x, y + 0.15, z), "frost", 0.55, r * 1.05)
	impact("frost", Vector3(x, y + 0.5, z), 1.1, false)
	burst(Vector3(x, y + 0.4, z), 40, r * 2.2, COL_ICE, 0.45, 0.45, 3.0)
	shake.emit(0.15, x, z)


func blink(x0: float, z0: float, x1: float, z1: float) -> void:
	impact("arcane", Vector3(x0, _y(x0, z0) + 1.0, z0), 0.9)
	impact("arcane", Vector3(x1, _y(x1, z1) + 1.0, z1), 0.9)


func trap(x: float, z: float) -> void:
	var y := _y(x, z)
	impact("frost", Vector3(x, y + 0.6, z), 1.1)
	burst(Vector3(x, y + 0.5, z), 40, 5.0, COL_ICE, 0.7, 0.5, 6.0)


## Per-curse tick on the victim: Corruption purple wisps rising, Agony sickly green sparks, Soul Rot dark red-violet smoke.
func curse_pulse(x: float, z: float, ability: String) -> void:
	var y := _y(x, z)
	var base := Vector3(x, y + 0.9 * UnitView.VS, z)
	match ability:
		"corruption":
			burst(base, 3, 1.0, Color("#6a2fc0"), 0.9, 0.22, -1.4)
		"agony":
			burst(base, 4, 2.2, Color("#3fbf20"), 0.5, 0.14, 1.0)
		_:
			burst(base, 5, 1.4, Color("#8a1f6a"), 1.0, 0.34, -0.8)
			burst(base, 2, 2.0, Color("#d03a7a"), 0.5, 0.15, 0.0)


## Fear: dark wisps and a skull-white spark spiralling off a fleeing unit.
func fear_wisps(x: float, z: float) -> void:
	var y := _y(x, z)
	burst(Vector3(x, y + 1.6 * UnitView.VS, z), 3, 1.6, Color("#5a2aa0"), 0.8, 0.3, -0.6)
	burst(Vector3(x, y + 1.6 * UnitView.VS, z), 1, 1.0, Color("#bfb8a0"), 0.6, 0.14, -0.3)


## Soul Rot: rotten-violet ground eruption with a column of fel smoke.
func soulrot_burst(x: float, z: float) -> void:
	var y := _y(x, z)
	_flash_ground(Vector3(x, y + 0.15, z), "shadow", 0.7, 3.2)
	_flash_column(Vector3(x, y, z), "shadow", 0.8, 1.6, Color("#7a1f5e"))
	impact("shadow", Vector3(x, y + 1.0, z), 1.5, false)
	burst(Vector3(x, y + 0.5, z), 24, 4.0, Color("#3fa82a"), 0.9, 0.35, 2.0)
	shake.emit(0.25, x, z)


## Dark Pact: violet runes burst around the caster.
func pact(x: float, z: float) -> void:
	var y := _y(x, z)
	_flash_ground(Vector3(x, y + 0.15, z), "shadow", 0.6, 1.8)
	burst(Vector3(x, y + 0.8, z), 18, 2.6, Color("#7a4ad0"), 0.8, 0.25, -1.0)


## Drain Life beams: list of {id, from: Vector3, to: Vector3}. Persistent pooled meshes, one per caster, removed when the channel ends.
func set_beams(list: Array, now_s: float) -> void:
	if not _fancy and not list.is_empty():
		return
	var seen := {}
	for b in list:
		seen[b.id] = true
		var node: MeshInstance3D = _beams.get(b.id)
		if node == null:
			node = MeshInstance3D.new()
			node.mesh = MeshBuilder.cylinder(1.0, 1.0, 1.0, 8)
			node.material_override = _emissive(Color("#7dff5a"), 3.0)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			_beams[b.id] = node
		var a: Vector3 = b.from
		var c: Vector3 = b.to
		var len := maxf(0.05, a.distance_to(c))
		node.global_position = (a + c) * 0.5
		var up := (c - a).normalized()
		var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var xa := up.cross(ref).normalized()
		var za := xa.cross(up).normalized()
		var w := 0.07 + 0.03 * sin(now_s * 30.0)
		node.global_transform.basis = Basis(xa * w, up * len, za * w)
		# souls flowing victim -> caster
		if int(now_s * 14.0) != int((now_s - 0.016) * 14.0):
			burst(c.lerp(a, fmod(now_s * 2.0, 1.0)), 2, 0.4, Color("#c7ffb0"), 0.4, 0.2, 0.0)
	for id in _beams.keys():
		if not seen.has(id):
			(_beams[id] as Node).queue_free()
			_beams.erase(id)


func scream(x: float, z: float, r: float) -> void:
	var y := _y(x, z)
	_flash_ground(Vector3(x, y + 0.15, z), "shadow", 0.6, r * 1.05)
	impact("shadow", Vector3(x, y + 1.2, z), 1.0, false)
	shake.emit(0.2, x, z)


func hymn(x: float, z: float, r: float) -> void:
	var y := _y(x, z)
	_flash_ground(Vector3(x, y + 0.15, z), "holy", 0.8, r * 1.05)
	_flash_column(Vector3(x, y, z), "holy", 0.9, 2.2)
	impact("holy", Vector3(x, y + 1.0, z), 1.3, false)
	burst(Vector3(x, y + 0.4, z), 70, r * 0.45, Color("#ffe08a"), 1.0, 0.5, -3.0)


func charge(x0: float, z0: float, x1: float, z1: float) -> void:
	for i in 8:
		var t := float(i) / 7.0
		var x := lerpf(x0, x1, t)
		var z := lerpf(z0, z1, t)
		burst(Vector3(x, _y(x, z) + 0.3, z), 4, 2.0, Color("#8a6a50"), 0.7, 0.9, -0.5)


## Weapon slash: spark burst plus a crescent trail across the attacker's front (alternating sides for light swings).
func slash(x: float, z: float, rot: float, heavy: bool, side := 1.0) -> void:
	var pos := Vector3(x + sin(rot) * 1.2, _y(x, z) + 1.15 * UnitView.VS, z + cos(rot) * 1.2)
	burst(pos, 18 if heavy else 10, 3.0, Color("#ffb060") if heavy else Color("#dfe6ff"), 0.25, 0.45 if heavy else 0.3)
	_flash_sphere(pos, "physical", 0.2, 0.18, 2.0 if heavy else 1.3)
	if not _fancy:
		return
	var m := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.4, 3.4) if heavy else Vector2(2.8, 2.8)
	m.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = SLASH
	mat.set_shader_parameter("color", Color("#ffb060") if heavy else Color("#cfe0ff"))
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = pos
	m.rotation = Vector3(0.0, rot, side * (1.05 if not heavy else 0.2))  # diagonal slashes lean left/right; heavy ones come from above
	add_child(m)
	_flashes.append({"mesh": m, "t": 0.0, "dur": 0.2 if not heavy else 0.26, "grow": 0.0, "mat": mat, "kind": "slash"})


func dash(x: float, z: float) -> void:
	burst(Vector3(x, _y(x, z) + 0.3, z), 14, 2.5, COL_SMOKE, 0.6, 0.8, -0.5)


func cast_spark(x: float, z: float, kind: String, rot := 0.0) -> void:
	cast_glow(x, z, rot, kind)


## Expanding glowing orb that dissolves.
func _flash_sphere(pos: Vector3, school: String, r: float, dur: float, grow: float) -> void:
	if not _fancy:
		return
	var m := MeshInstance3D.new()
	m.mesh = MeshBuilder.sphere(r, 12, 6)
	var mat := _school_mat("orb", school, 1.8)
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	_flashes.append({"mesh": m, "t": 0.0, "dur": dur, "grow": grow, "mat": mat, "kind": "orb"})


## Ground shockwave: the animated ground shader expanding to radius `grow`.
func _flash_ground(pos: Vector3, school: String, dur: float, grow: float) -> void:
	if not _fancy:
		return
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	m.mesh = pm
	var mat := _school_mat("ground", school, 1.5)
	mat.set_shader_parameter("fill", 0.3)
	m.material_override = mat
	m.position = pos
	m.scale = Vector3(0.2, 1, 0.2)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	_flashes.append({"mesh": m, "t": 0.0, "dur": dur, "grow": grow, "mat": mat, "kind": "ground"})


## Vertical light pillar (holy impacts, pickups).
func _flash_column(pos: Vector3, school: String, dur: float, scale: float, tint := Color.TRANSPARENT) -> void:
	if not _fancy:
		return
	var m := MeshInstance3D.new()
	m.mesh = MeshBuilder.cylinder(0.28 * scale, 0.28 * scale, 7.0, 14)
	var mat := _school_mat("orb", school, 0.9)
	if tint.a > 0.0:
		mat.set_shader_parameter("mid", tint)
		mat.set_shader_parameter("edge", tint.darkened(0.4))
	m.material_override = mat
	m.position = pos + Vector3(0, 3.5, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	_flashes.append({"mesh": m, "t": 0.0, "dur": dur, "grow": 0.0, "mat": mat, "kind": "column"})


# ---------------------------------------------------------------- per frame

func update(dt: float, now_s: float) -> void:
	for v in _projs.values():
		var age := minf(0.12, now_s - v.at)
		var x: float = v.x + v.vx * age
		var z: float = v.z + v.vz * age
		var n: Node3D = v.node
		var left := maxf(0.0, 1.0 - (now_s - v.born) / 0.14)  # the offset from the caster's hand melts away in the first 0.14 s
		n.position = Vector3(x, _y(x, z) + 1.1 * UnitView.VS, z) + (v.offset as Vector3) * left * left
		n.rotation.y = atan2(v.vx, v.vz)
		var st: Dictionary = PROJ_STYLE.get(v.kind, PROJ_STYLE.fireball)
		if not st.arrow:
			n.scale = Vector3(1, 1, 1.0 + Vector2(v.vx, v.vz).length() * 0.05)
	for a in _aoes.values():
		var left := maxf(0.0, a.left - (now_s - a.at) * 1000.0)
		var t := 1.0 - left / maxf(1.0, a.total)
		var m := a.ring.material_override as ShaderMaterial
		if m != null:
			m.set_shader_parameter("progress", t)
			m.set_shader_parameter("fade", 0.75 + 0.25 * absf(sin(now_s * 10.0 * (0.4 + t))))
		a.rock.position = a.ring.position + Vector3((1.0 - t) * 6.0, 0.4 + (1.0 - t) * 18.0, -(1.0 - t) * 3.0)
	for g in _powers.values():
		var gem: Node3D = g.get_node("gem")
		gem.rotation.y = now_s * 2.0
		gem.position.y = 1.2 + sin(now_s * 3.0) * 0.15
	for g in _traps.values():
		g.rotation.y += dt * (1.5 if g.get_meta("armed", false) else 0.3)
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Dictionary = _flashes[i]
		f.t += dt
		var k: float = minf(1.0, f.t / f.dur)
		var mat: ShaderMaterial = f.mat
		match f.kind:
			"ground":
				var r: float = lerpf(0.2, f.grow, 1.0 - pow(1.0 - k, 3.0))
				f.mesh.scale = Vector3(r, 1, r)
				mat.set_shader_parameter("fade", 1.0 - k * k)
				mat.set_shader_parameter("progress", k)
			"slash":
				mat.set_shader_parameter("progress", minf(1.0, k * 1.6))
				mat.set_shader_parameter("fade", 1.0 - smoothstep(0.55, 1.0, k))
			"column":
				f.mesh.scale = Vector3(1.0 - k * 0.5, 1.0 + k * 0.3, 1.0 - k * 0.5)
				mat.set_shader_parameter("fade", 1.0 - k)
			_:
				f.mesh.scale = Vector3.ONE * (1.0 + k * f.grow)
				mat.set_shader_parameter("dissolve", k * 0.85)
				mat.set_shader_parameter("fade", 1.0 - k * 0.6)
		if k >= 1.0:
			f.mesh.queue_free()
			_flashes.remove_at(i)
	for l in _lights:
		if l.t < l.dur:
			l.t += dt
			l.light.light_energy = l.energy * maxf(0.0, 1.0 - l.t / l.dur)
		elif l.light.light_energy != 0.0:
			l.light.light_energy = 0.0
	for sc in _scorches:
		if sc.t < 8.0:
			sc.t += dt
			var fade := 1.0 - smoothstep(4.0, 8.0, sc.t)
			sc.mat.set_shader_parameter("fade", fade)
			sc.mat.set_shader_parameter("heat", maxf(0.0, 1.0 - sc.t / 1.6))
			if sc.t >= 8.0:
				sc.mesh.visible = false


func clear() -> void:
	set_beams([], 0.0)
	sync_powers([])
	sync_projectiles([], 0.0)
	sync_aoes([], 0.0)
	sync_traps([])
	for f in _flashes:
		f.mesh.queue_free()
	_flashes.clear()
