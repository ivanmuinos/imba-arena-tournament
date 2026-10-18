class_name ArenaWorld
extends Node3D
## The scenery of one arena (see core/game_map.gd): terrain from height_at, the modular Blender kit
## (assets/models/env/*.glb) placed on the collision shapes, animated gates and living pillars, lava, lights and
## atmosphere. Gameplay shapes are authoritative; everything here is visual (decor lives outside the walls).

const KIT := "res://assets/models/env/%s.glb"

const THEMES := {
	"bridge": {"sky_top": 0x2a1a2a, "sky_horizon": 0xe07a3a, "fog": 0x7a4a34, "fog_density": 0.0022, "ambient": 0xf8dcc0, "ambient_energy": 0.95, "sun": 0xffe0b8, "sun_energy": 2.0,
		"torch": 0xff9a40, "glow": 0xff6a2a, "ember": 0xffb060, "tint": 0xffffff},
	"pillars": {"sky_top": 0x2a2a3a, "sky_horizon": 0xc89070, "fog": 0x6a5248, "fog_density": 0.002, "ambient": 0xf0e0d0, "ambient_energy": 0.95, "sun": 0xfff0d8, "sun_energy": 2.0,
		"torch": 0xffb860, "glow": 0xff7a30, "ember": 0xffc880, "tint": 0xf0e8e0},
	"tomb": {"sky_top": 0x182848, "sky_horizon": 0x5a78b8, "fog": 0x34466a, "fog_density": 0.0024, "ambient": 0xc8d8ff, "ambient_energy": 1.0, "sun": 0xe0ecff, "sun_energy": 1.9,
		"torch": 0x7ae8ff, "glow": 0x6ad8ff, "ember": 0xaaf8ff, "tint": 0xdce6f4},
	"living": {"sky_top": 0x2a1428, "sky_horizon": 0xc05068, "fog": 0x5a2c34, "fog_density": 0.0022, "ambient": 0xf0d4d4, "ambient_energy": 0.95, "sun": 0xffd0c0, "sun_energy": 2.0,
		"torch": 0xff6a70, "glow": 0xff4a40, "ember": 0xff8a78, "tint": 0xf4dcdc},
}

var map: GameMap
var sun: DirectionalLight3D
var env: Environment
var embers: CPUParticles3D

var _theme: Dictionary
var _rand: Rng
var _kits := {}
var _surface_cache := {}
var _gate_t := 0.0
var _gate_goal := 0.0
var _gates: Array = []  # {left, right}
var _pillars: Array = []  # {node, ring, base_y, last_state}
var _lights: Array = []  # {light, base, phase}
var _fx_lights: Array = []
var _dust: Array = []
var _local_ft := 0.0
var _ft_at := 0.0
var _gates_open := false
var _terrain: MeshInstance3D
var _terrain_mat: ShaderMaterial


func setup(p_map: GameMap) -> void:
	map = p_map
	_theme = THEMES.get(map.id, THEMES.bridge)
	_rand = Rng.new(77 + map.id.length())
	_build_environment()
	_build_terrain()
	_build_walls_and_gates()
	_build_statics()
	_build_dynamic_pillars()
	if map.id == "bridge":
		_build_bridge()
	_build_room_decor()
	_build_outer_decor()
	_build_embers()
	sync_state(false, 0.0, 0.0)


func h(x: float, z: float) -> float:
	return map.height_at(x, z)


func _col(hex: int) -> Color:
	return Color.hex(hex << 8 | 0xff)


# ---------------------------------------------------------------- kit helpers

func _kit(kit_name: String) -> PackedScene:
	if not _kits.has(kit_name):
		_kits[kit_name] = load(KIT % kit_name) if ResourceLoader.exists(KIT % kit_name) else null
	return _kits[kit_name]


func _place_kit(kit_name: String, pos: Vector3, rot_y := 0.0, scl := Vector3.ONE, parent: Node = null) -> Node3D:
	var ps := _kit(kit_name)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	n.position = pos
	n.rotation.y = rot_y
	n.scale = scl
	(parent if parent != null else self).add_child(n)
	return n


func _shape_rot(o: Dictionary) -> float:
	return -atan2(float(o.s), float(o.c))


func _tint_materials(n: Node) -> void:
	var t := _col(_theme.tint)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i)
			var kind: String = KIT_SURFACES.get(src.resource_name, "") if src != null else ""
			if kind != "" and DisplayServer.get_name() != "headless" and not (src as StandardMaterial3D).emission_enabled:
				m.set_surface_override_material(i, _kit_surface(src as StandardMaterial3D, kind, t))
			elif src is StandardMaterial3D:
				var c := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				if c.emission_enabled:
					if map.id == "tomb":  # spectral blue-green fire instead of magma orange
						c.emission = _col(_theme.glow)
						c.albedo_color = _col(_theme.glow)
				else:
					c.albedo_color = c.albedo_color * t
				m.set_surface_override_material(i, c)


## Kit materials that get the weathered triplanar surface (see assets/shaders/kit_surface.gdshader).
const KIT_SURFACES := {"carved_stone": "stone", "carved_stone_dark": "stone", "pale_stone": "stone", "basalt": "stone", "basalt_light": "stone",
	"dead_wood": "wood", "dark_iron": "metal"}


func _kit_surface(src: StandardMaterial3D, kind: String, tint: Color) -> ShaderMaterial:
	var key := "%s_%s_%s" % [src.resource_name, kind, map.id]
	if _surface_cache.has(key):
		return _surface_cache[key]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/kit_surface.gdshader")
	var tex := Textures.kit(kind)
	sm.set_shader_parameter("albedo_tex", tex[0])
	sm.set_shader_parameter("normal_tex", tex[1])
	var base := src.albedo_color * tint
	if src.resource_name == "pale_stone":
		base = base.darkened(0.25)
	sm.set_shader_parameter("base_color", base)
	sm.set_shader_parameter("rough", src.roughness)
	sm.set_shader_parameter("metallic", 0.55 if kind == "metal" else 0.0)
	sm.set_shader_parameter("dust_amount", 0.0 if kind != "stone" else (0.45 if map.id == "tomb" else 0.3))
	sm.set_shader_parameter("dust_color", Color(0.46, 0.5, 0.58) if map.id == "tomb" else Color(0.5, 0.42, 0.36))
	sm.set_shader_parameter("tex_scale", 0.5 if kind == "wood" else 0.28)
	_surface_cache[key] = sm
	return sm


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = _col(_theme.sky_top).srgb_to_linear()
	sky_mat.sky_horizon_color = _col(_theme.sky_horizon).srgb_to_linear()
	sky_mat.ground_horizon_color = _col(_theme.sky_horizon).srgb_to_linear().darkened(0.3)
	sky_mat.ground_bottom_color = _col(_theme.fog).srgb_to_linear()
	sky_mat.sky_curve = 0.25
	sky_mat.sun_angle_max = 0.0
	sky_mat.sun_curve = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _col(_theme.ambient)
	env.ambient_light_energy = _theme.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.0
	env.ssr_enabled = true
	env.fog_enabled = true
	env.fog_light_color = _col(_theme.fog)
	env.fog_density = _theme.fog_density
	env.fog_sky_affect = 0.15
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.002
	env.volumetric_fog_albedo = _col(_theme.fog).lightened(0.25)
	env.volumetric_fog_emission = _col(_theme.glow) * 0.01
	env.volumetric_fog_length = 70.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.0
	env.adjustment_brightness = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = _col(_theme.sun)
	sun.light_energy = _theme.sun_energy
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-30), 0)
	add_child(sun)


## Scales the expensive features to a Quality level (see logic/quality.gd).
func apply_quality(q: Dictionary) -> void:
	if Quality.compatibility_renderer():  # OpenGL fallback: no SSAO/SSR/SDFGI/volumetric fog
		env.glow_enabled = q.glow
		sun.shadow_enabled = q.shadows
		if embers != null:
			embers.amount = maxi(int(q.embers), 1)
		return
	env.glow_enabled = q.glow
	env.ssao_enabled = q.ssao
	env.ssr_enabled = q.ssr
	env.volumetric_fog_enabled = q.volumetric_fog
	env.sdfgi_enabled = q.sdfgi
	sun.shadow_enabled = q.shadows
	RenderingServer.directional_shadow_atlas_set_size(int(q.shadow_size), true)
	if embers != null:
		embers.amount = maxi(int(q.embers), 1)
		embers.visible = q.embers > 0
	for l in _fx_lights:
		(l as Light3D).visible = q.fx_lights
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = q.scale
		match str(q.get("upscaler", "bilinear")):
			"metalfx": vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL
			"metalfx_t": vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
			"fsr2": vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			_: vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}.get(int(q.msaa), Viewport.MSAA_DISABLED)


## Only the 3D render scale (used by dynamic resolution): cheap, no environment changes.
func set_render_scale(scale: float, upscaler: String) -> void:
	var vp := get_viewport()
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = {"metalfx": Viewport.SCALING_3D_MODE_METALFX_SPATIAL, "fsr2": Viewport.SCALING_3D_MODE_FSR2}.get(upscaler, Viewport.SCALING_3D_MODE_BILINEAR)


func follow(x: float, z: float) -> void:
	sun.position = Vector3(x, 40, z)
	if embers != null:
		embers.position = Vector3(x, h(x, z) + 1.0, z)


# ---------------------------------------------------------------- terrain

## Floor height with raised cliffs outside the playable rectangle (and in the sealed pockets behind the end walls).
func _full_h(x: float, z: float) -> float:
	var base := h(x, z)
	var ax := absf(x)
	var az := absf(z)
	var out := 0.0
	if ax > GameMap.W:
		out = maxf(out, ax - GameMap.W)
	if az > GameMap.R:
		out = maxf(out, az - GameMap.R)
	if az > GameMap.A + 1.0 and ax > GameMap.ROOM_HW + 1.0:
		out = maxf(out, minf(ax - GameMap.ROOM_HW - 1.0, az - GameMap.A - 1.0) * 1.2 + 3.0)
	if out > 0.0:
		base += minf(out * out * 0.16, 14.0) + 2.0 * sin(x * 0.4) * cos(z * 0.33) * minf(out, 3.0) * 0.4
	return base


func _build_terrain() -> void:
	var ext_x := GameMap.W + 24.0
	var ext_z := GameMap.R + 24.0
	var step := 0.8
	var nx := int(2.0 * ext_x / step)
	var nz := int(2.0 * ext_z / step)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var heights := PackedFloat32Array()
	heights.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			heights[j * (nx + 1) + i] = _full_h(-ext_x + i * step, -ext_z + j * step)
	for j in nz + 1:
		for i in nx + 1:
			var x := -ext_x + i * step
			var z := -ext_z + j * step
			var y := heights[j * (nx + 1) + i]
			var hl := heights[j * (nx + 1) + maxi(i - 1, 0)]
			var hr := heights[j * (nx + 1) + mini(i + 1, nx)]
			var hd := heights[maxi(j - 1, 0) * (nx + 1) + i]
			var hu := heights[mini(j + 1, nz) * (nx + 1) + i]
			verts.append(Vector3(x, y, z))
			norms.append(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
			uvs.append(Vector2(x, z) / 6.0)
			var inside := absf(x) <= GameMap.W and absf(z) <= GameMap.R
			var lava_floor := map.is_low(x, z)
			var tint := 1.0 - clampf(y * 0.015, 0.0, 0.25)
			var glow := 0.1 if not inside else (0.9 if lava_floor else 0.55)
			if map.id == "tomb":
				glow = 0.25
			cols.append(Color(tint / 1.6, tint / 1.6, tint / 1.6, glow))
	var indices := PackedInt32Array()
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var c := a + (nx + 1)
			indices.append_array(PackedInt32Array([a, a + 1, c, a + 1, c + 1, c]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var tex := Textures.ground_calm() if map.id == "tomb" else Textures.ground(false)
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = load("res://assets/shaders/terrain.gdshader")
	_terrain_mat.set_shader_parameter("ash_tex", tex[0])
	_terrain_mat.set_shader_parameter("rock_tex", Textures.rock())
	_terrain_mat.set_shader_parameter("glow_tex", tex[1])
	_terrain_mat.set_shader_parameter("glow_color", _col(_theme.glow))
	_terrain_mat.set_shader_parameter("glow_strength", 1.2 if map.id != "tomb" else 0.9)
	_terrain = MeshInstance3D.new()
	_terrain.mesh = mesh
	_terrain.material_override = _terrain_mat
	add_child(_terrain)
	# Lava over the chasm (bridge map).
	for hz in map.hazards:
		if hz.dps <= 0:
			continue
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(hz.hx * 2.0 + 0.6, hz.hz * 2.0 + 0.6)
		q.mesh = pm
		var lm := ShaderMaterial.new()
		lm.shader = load("res://assets/shaders/lava.gdshader")
		lm.set_shader_parameter("energy", 1.7)
		q.material_override = lm
		q.position = Vector3(hz.x, -1.55, hz.z)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
	if not map.hazards.is_empty():
		_add_light(Vector3(0, 1.0, 0), _col(_theme.glow), 5.0, 34.0, true)


func _add_light(pos: Vector3, color: Color, energy: float, rng: float, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.position = pos
	add_child(l)
	_fx_lights.append(l)
	if flicker:
		_lights.append({"light": l, "base": energy, "phase": _rand.next() * 10.0})
	return l


# ---------------------------------------------------------------- walls, gates, statics

func _build_walls_and_gates() -> void:
	for o in map.statics:
		if not o.get("wall", false):
			continue
		var long_is_x: bool = o.hx >= o.hz
		var length: float = 2.0 * (o.hx if long_is_x else o.hz)
		var thick: float = 2.0 * (o.hz if long_is_x else o.hx)
		var n := maxi(1, ceili(length / 4.0))
		var seg := length / n
		var rot := _shape_rot(o) + (0.0 if long_is_x else PI / 2.0)
		var dir := Vector2(cos(-rot), -sin(-rot))  # local +x of the segment in (x, z)
		var dir_w := Vector2(cos(rot), -sin(rot))
		var y0 := h(o.x, o.z)
		for k in n:
			var off := (k + 0.5) * seg - length / 2.0
			var p := Vector2(o.x, o.z) + dir_w * off
			var node := _place_kit("wall", Vector3(p.x, h(p.x, p.y) - 0.2, p.y), rot, Vector3(seg / 4.0, 1.0, thick / 1.5 * 1.0))
			if node != null:
				_tint_materials(node)
		if y0 < -100.0:
			pass
	for sgn in [1.0, -1.0]:
		var g := Node3D.new()
		g.position = Vector3(0, h(0, sgn * GameMap.A), sgn * GameMap.A)
		g.rotation.y = 0.0 if sgn > 0 else PI
		add_child(g)
		var frame := _place_kit("gate_frame", Vector3.ZERO, 0.0, Vector3.ONE, g)
		if frame != null:
			_tint_materials(frame)
		var left := Node3D.new()
		left.position = Vector3(-GameMap.GATE_HW, 0, 0)
		g.add_child(left)
		_place_kit("gate_leaf", Vector3.ZERO, 0.0, Vector3.ONE, left)
		var right := Node3D.new()
		right.position = Vector3(GameMap.GATE_HW, 0, 0)
		g.add_child(right)
		_place_kit("gate_leaf", Vector3.ZERO, 0.0, Vector3(-1, 1, 1), right)
		_gates.append({"left": left, "right": right, "root": g})
		_add_light(Vector3(0, h(0, sgn * GameMap.A) + 6.5, sgn * (GameMap.A + 0.2)), _col(_theme.torch), 2.0, 14.0)


func _build_statics() -> void:
	for o in map.statics:
		if o.get("wall", false):
			continue
		var y := h(o.x, o.z)
		if o.k == "c":
			if o.get("statue", false):
				var n := _place_kit("statue", Vector3(o.x, y - 0.1, o.z), PI, Vector3(0.95, 0.95, 0.95))
				if n != null:
					_tint_materials(n)
				_add_light(Vector3(o.x, y + 9.0, o.z), _col(_theme.glow), 3.0, 26.0, true)
			elif map.id == "pillars":
				var n := _place_kit("pillar", Vector3(o.x, y - 0.1, o.z), _rand.next() * TAU, Vector3(o.r, 1.25, o.r))
				if n != null:
					_tint_materials(n)
			elif map.id == "tomb":
				var n := _place_kit("broken_column", Vector3(o.x, y, o.z), _rand.next() * TAU, Vector3(o.r, o.r, o.r))
				if n != null:
					_tint_materials(n)
			else:
				var n := _place_kit(["rock_a", "rock_b", "rock_c"][int(_rand.next() * 3)], Vector3(o.x, y - 0.3, o.z), _rand.next() * TAU, Vector3(o.r * 1.15, o.r * 1.5, o.r * 1.15))
				if n != null:
					_tint_materials(n)
		else:
			var n := _place_kit("gravestone", Vector3(o.x, y, o.z), _shape_rot(o) + PI, Vector3(o.hx / 0.7, 1.7, o.hz / 0.225))
			if n != null:
				_tint_materials(n)


func _build_dynamic_pillars() -> void:
	for p in map.dyn_pillars:
		var y := h(p.x, p.z)
		var node := Node3D.new()
		node.position = Vector3(p.x, y, p.z)
		add_child(node)
		var body := _place_kit("pillar", Vector3(0, -0.1, 0), _rand.next() * TAU, Vector3(p.r, 1.25, p.r), node)
		if body != null:
			_tint_materials(body)
		# Ground telegraph: glowing ring + rune disc that pulses before the pillar rises.
		var ring := MeshInstance3D.new()
		ring.mesh = MeshBuilder.ring(p.r * 0.7, p.r * 1.25, 48)
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rm.cull_mode = BaseMaterial3D.CULL_DISABLED
		rm.albedo_color = Color(0, 0, 0, 0)
		ring.material_override = rm
		ring.position = Vector3(p.x, y + 0.12, p.z)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		var dust := CPUParticles3D.new()
		dust.amount = 40
		dust.lifetime = 1.4
		dust.one_shot = true
		dust.explosiveness = 0.9
		dust.emitting = false
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		dust.emission_ring_radius = p.r
		dust.emission_ring_inner_radius = p.r * 0.6
		dust.emission_ring_height = 0.2
		dust.emission_ring_axis = Vector3.UP
		dust.direction = Vector3.UP
		dust.spread = 50.0
		dust.initial_velocity_min = 2.0
		dust.initial_velocity_max = 6.0
		dust.gravity = Vector3(0, -3, 0)
		dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var qm := QuadMesh.new()
		qm.size = Vector2(1.2, 1.2)
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		dm.albedo_texture = Textures.glow_dot()
		dm.albedo_color = Color(0.5, 0.35, 0.28, 0.6)
		qm.material = dm
		dust.mesh = qm
		dust.position = Vector3(p.x, y + 0.3, p.z)
		add_child(dust)
		var light := _add_light(Vector3(p.x, y + 2.0, p.z), _col(_theme.glow), 0.0, 12.0)
		_pillars.append({"node": node, "ring": ring, "dust": dust, "light": light, "base_y": y, "state": "down", "r": p.r})


func _build_bridge() -> void:
	var b := _place_kit("bridge", Vector3(0, 3.0, 0), PI / 2, Vector3.ONE)
	if b != null:
		_tint_materials(b)
		# kit bridge runs along its Y axis (Godot -Z); the rotation above lays it along game z.
		b.rotation.y = 0.0
		b.scale = Vector3(1.0, 1.0, 9.0 * 2.0 / 19.4)
		b.position = Vector3(0, 3.0, 0)


func _build_room_decor() -> void:
	for sgn in [1.0, -1.0]:
		var z0: float = sgn * GameMap.A
		for pos in [Vector2(-6.8, sgn * (GameMap.A + 3.0)), Vector2(6.8, sgn * (GameMap.A + 3.0)), Vector2(-6.8, sgn * (GameMap.R - 2.5)), Vector2(6.8, sgn * (GameMap.R - 2.5)),
				Vector2(-GameMap.GATE_HW - 1.2, sgn * (GameMap.A - 1.4)), Vector2(GameMap.GATE_HW + 1.2, sgn * (GameMap.A - 1.4))]:
			var y := h(pos.x, pos.y)
			_place_kit("torch", Vector3(pos.x, y, pos.y), 0.0)
			_add_light(Vector3(pos.x, y + 2.4, pos.y), _col(_theme.torch), 2.6, 12.0, true)
		# a rune-lit floor disc marking where each team spawns
		var disc := MeshInstance3D.new()
		disc.mesh = MeshBuilder.ring(3.2, 3.6, 48)
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.albedo_color = _col(_theme.glow) * 1.8
		disc.material_override = dm
		disc.position = Vector3(0, h(0, sgn * 27.5) + 0.08, sgn * 27.5)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(disc)
		if z0 == 0.0:
			pass


func _build_outer_decor() -> void:
	# Cliffs behind the walls and dead ember trees / rocks scattered outside the play area.
	for k in 36:
		var a := TAU * k / 36.0
		var px := cos(a) * (GameMap.W + 15.0) * 1.1
		var pz := sin(a) * (GameMap.R + 15.0) * 1.08
		var n := _place_kit("cliff", Vector3(px, _full_h(px, pz) - 1.0, pz), -a + PI / 2, Vector3(0.95, 0.8 + _rand.next() * 0.4, 0.95))
		if n != null:
			_tint_materials(n)
	for k in 70:
		var x := (_rand.next() * 2.0 - 1.0) * (GameMap.W + 16.0)
		var z := (_rand.next() * 2.0 - 1.0) * (GameMap.R + 16.0)
		if absf(x) < GameMap.W + 2.5 and absf(z) < GameMap.R + 2.5:
			continue
		var y := _full_h(x, z)
		var kitn: String = ["tree_a", "tree_b", "tree_c", "rock_a", "rock_b", "rock_c", "crystal"][int(_rand.next() * 7)]
		var sc := 0.8 + _rand.next() * 0.9
		var n := _place_kit(kitn, Vector3(x, y - 0.2, z), _rand.next() * TAU, Vector3(sc, sc, sc))
		if n != null:
			_tint_materials(n)


func _build_embers() -> void:
	embers = CPUParticles3D.new()
	embers.amount = 450
	embers.lifetime = 12.0
	embers.preprocess = 12.0
	embers.local_coords = false
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(32, 0.5, 32)
	embers.direction = Vector3.UP
	embers.spread = 20.0
	embers.gravity = Vector3.ZERO
	embers.initial_velocity_min = 0.3
	embers.initial_velocity_max = 1.0
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Small, faint motes: atmosphere, not something the eye has to track.
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 1.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = Textures.glow_dot()
	mat.albedo_color = _col(_theme.ember) * 1.1
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	qm.material = mat
	embers.mesh = qm
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.85, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	embers.color_ramp = ramp
	add_child(embers)


# ---------------------------------------------------------------- per-frame state

## No bushes in the new arenas; kept so callers need not care.
func reveal_around(_px: float, _pz: float, _bush: int, _cam: Vector3) -> void:
	pass


## Gate / pillar state from the latest snapshot (`ft` = ms since the fight began).
func sync_state(open: bool, ft: float, now_s: float) -> void:
	_gates_open = open
	_gate_goal = 1.0 if open else 0.0
	_local_ft = ft
	_ft_at = now_s


func update(dt: float, now_s: float) -> void:
	_gate_t = move_toward(_gate_t, _gate_goal, dt / 1.6)
	var e := _gate_t * _gate_t * (3.0 - 2.0 * _gate_t)
	for g in _gates:
		g.left.rotation.y = e * deg_to_rad(100.0)
		g.right.rotation.y = -e * deg_to_rad(100.0)
	var ft := _local_ft + (now_s - _ft_at) * 1000.0 if _gates_open else 0.0
	for i in _pillars.size():
		var pv: Dictionary = _pillars[i]
		var info := map.pillar_info(i, ft)
		var node: Node3D = pv.node
		var body_y: float = (info.h - 1.0) * 11.5
		var shake := 0.0
		if info.state == "warn":
			shake = 0.05 + 0.1 * info.warn
		elif info.state == "rise" or info.state == "sink":
			shake = 0.12
		node.position = Vector3(map.dyn_pillars[i].x + sin(now_s * 60.0 + i) * shake, pv.base_y + body_y, map.dyn_pillars[i].z + cos(now_s * 53.0 + i) * shake)
		node.visible = info.h > 0.001
		var ring: MeshInstance3D = pv.ring
		var rm := ring.material_override as StandardMaterial3D
		var glow := 0.0
		if info.state == "warn":
			glow = 0.3 + 0.7 * info.warn * (0.6 + 0.4 * sin(now_s * 14.0))
		elif info.state == "rise":
			glow = 1.0
		elif info.state == "up":
			glow = 0.12
		var c := _col(_theme.glow)
		rm.albedo_color = Color(c.r * glow * 2.0, c.g * glow * 2.0, c.b * glow * 2.0, clampf(glow, 0.0, 1.0))
		ring.scale = Vector3.ONE * (1.0 + (0.15 * sin(now_s * 10.0) if info.state == "warn" else 0.0))
		(pv.light as OmniLight3D).light_energy = glow * 4.0
		if pv.state != info.state:
			if info.state == "rise" or info.state == "sink":
				(pv.dust as CPUParticles3D).restart()
				(pv.dust as CPUParticles3D).emitting = true
			pv.state = info.state
	for l in _lights:
		var lt: OmniLight3D = l.light
		lt.light_energy = l.base * (0.85 + 0.15 * sin(now_s * 7.0 + l.phase) * sin(now_s * 3.1 + l.phase * 2.0))
