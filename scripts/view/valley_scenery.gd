class_name ValleyScenery
extends RefCounted
## Draws the Academia's valley on an ArenaWorld: the ground and the mountains around it, the lava in its channel, the pond,
## everything GameMap placed (trees, rocks, pillars, braziers), grass and flowers, and Tizón by the fire of his camp.
## Only looks: where things are and what stops a walker is GameMap's.

const RIM := 36.0  # how far past the edge the ground is drawn
const STEP := 1.0
const TUFTS := 30000
const FLOWERS := 1600
const FLOWER_COLORS := [Color("#d8c888"), Color("#e0a820"), Color("#e0608c"), Color("#9a78e0"), Color("#d8d8d0")]


static func build(w: ArenaWorld) -> void:
	_terrain(w)
	_lava(w)
	_pond(w)
	_statics(w)
	_grass(w)
	_outside(w)
	_camp(w)
	_zone_lights(w)


## Height with the mountains that close the valley: past the edge the ground climbs, rough and steep.
static func full_h(map: GameMap, x: float, z: float) -> float:
	var base := map.height_at(clampf(x, -map.half_x, map.half_x), clampf(z, -map.half_z, map.half_z))
	var out := maxf(absf(x) - map.half_x, absf(z) - map.half_z)
	if out <= 0.0:
		return base
	var ridge := 0.6 + 0.4 * sin(x * 0.13 + 1.0) * cos(z * 0.11) + 0.25 * sin((x - z) * 0.31)
	return base + minf(out * out * 0.07, 26.0) * ridge + minf(out, 4.0) * 0.5


static func _terrain(w: ArenaWorld) -> void:
	var map := w.map
	var ext := map.half_x + RIM
	var n := int(2.0 * ext / STEP)
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			heights[j * (n + 1) + i] = full_h(map, -ext + i * STEP, -ext + j * STEP)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for j in n + 1:
		for i in n + 1:
			var x := -ext + i * STEP
			var z := -ext + j * STEP
			var y := heights[j * (n + 1) + i]
			var hl := heights[j * (n + 1) + maxi(i - 1, 0)]
			var hr := heights[j * (n + 1) + mini(i + 1, n)]
			var hd := heights[maxi(j - 1, 0) * (n + 1) + i]
			var hu := heights[mini(j + 1, n) * (n + 1) + i]
			verts.append(Vector3(x, y, z))
			norms.append(Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized())
			cols.append(ground_color(map, x, z))
	var indices := PackedInt32Array()
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var c := a + (n + 1)
			indices.append_array(PackedInt32Array([a, a + 1, c, a + 1, c + 1, c]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/valley_terrain.gdshader")
	mat.set_shader_parameter("noise_tex", Textures.spell_noise())
	mat.set_shader_parameter("rock_tex", Textures.rock())
	mat.set_shader_parameter("glow_color", w._col(w._theme.glow))
	w._terrain_mat = mat
	w._terrain = MeshInstance3D.new()
	w._terrain.mesh = mesh
	w._terrain.material_override = mat
	w.add_child(w._terrain)


## What the terrain shader paints at a point: r = path, g = paved floor, b = scorched by the lava, a = shade.
static func ground_color(map: GameMap, x: float, z: float) -> Color:
	var inside := absf(x) <= map.half_x and absf(z) <= map.half_z
	var path := map.path_weight(x, z) if inside else 0.0
	var paved := 0.0
	for zn in map.zones:
		if str(zn.id) in ["camp", "arena", "yard"]:
			paved = maxf(paved, clampf((float(zn.r) - 2.0 - Vector2(x - float(zn.x), z - float(zn.z)).length()) / 2.5, 0.0, 1.0))
	var burnt := clampf((GameMap.RIVER_HZ + 4.5 - absf(z - GameMap.RIVER_Z)) / 4.5, 0.0, 1.0)
	for f in GameMap.FORDS:
		if absf(x - float(f)) < GameMap.FORD_HW:
			burnt *= 0.55  # the fords are trodden earth, not ash
			path = maxf(path, 1.0 - absf(x - float(f)) / GameMap.FORD_HW) if absf(z - GameMap.RIVER_Z) < 8.0 else path
	return Color(path, paved, burnt, 1.0 if inside else 0.82)


static func _lava(w: ArenaWorld) -> void:
	var shader: Shader = load("res://assets/shaders/lava.gdshader")
	for hz in w.map.hazards:
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(hz.hx * 2.0 + 1.2, hz.hz * 2.0 + 1.6)
		q.mesh = pm
		var lm := ShaderMaterial.new()
		lm.shader = shader
		lm.set_shader_parameter("energy", 1.7)
		q.material_override = lm
		q.position = Vector3(hz.x, -0.42, hz.z)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(q)
	for x in [-56.0, -40.0, -12.0, 12.0, 40.0, 56.0]:
		w._add_light(Vector3(x, 1.4, GameMap.RIVER_Z), w._col(w._theme.glow), 3.2, 17.0, true)


static func _pond(w: ArenaWorld) -> void:
	var q := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GameMap.POND.z * 2.0, GameMap.POND.z * 2.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	q.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/valley_water.gdshader")
	mat.set_shader_parameter("noise_tex", Textures.spell_noise())
	mat.set_shader_parameter("radius", GameMap.POND.z)
	q.material_override = mat
	q.position = Vector3(GameMap.POND.x, -0.28, GameMap.POND.y)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(q)


## Everything GameMap put in the valley that is not a wall, with the model its `art` names.
static func _statics(w: ArenaWorld) -> void:
	for o in w.map.statics:
		if o.get("wall", false) or o.k != "c":
			continue
		var art := str(o.get("art", "rock_a"))
		var y := w.h(o.x, o.z)
		var at := Vector3(o.x, y, o.z)
		var sc := float(o.get("sc", 1.0))
		var rot := float(o.get("rot", 0.0))
		var n: Node3D = null
		match art:
			"torch":
				w._place_torch(at)
				w._add_light(at + Vector3(0, 2.4, 0), w._col(w._theme.torch), 2.2, 11.0, true)
			"pillar":
				n = w._place_kit("pillar", at - Vector3(0, 0.1, 0), o.x * 1.7, Vector3(o.r, 1.15, o.r))
			"statue":
				n = w._place_kit("statue", at - Vector3(0, 0.1, 0), PI, Vector3(0.7, 0.7, 0.7))
			"broken_column":
				n = w._place_kit("broken_column", at, o.z * 2.3, Vector3(o.r, o.r, o.r))
			"crystal":
				n = w._place_kit("crystal", at - Vector3(0, 0.2, 0), o.x * 0.9, Vector3(o.r, o.r * 1.3, o.r) * 1.3)
				w._add_light(at + Vector3(0, 1.6, 0), Color("#7fe8ff"), 1.6, 9.0)
			_:
				if art.begins_with("tree"):
					n = w._place_kit(art, at - Vector3(0, 0.15, 0), rot, Vector3(sc, sc * 1.05, sc) * 0.9)
				else:
					n = w._place_kit(art, at - Vector3(0, 0.3, 0), rot, Vector3(o.r, o.r * 1.2, o.r) * 0.9)
		if n != null:
			w._tint_materials(n)


## Tufts of grass on the meadows and flowers here and there, as two MultiMeshes (one draw call each).
static func _grass(w: ArenaWorld) -> void:
	var map := w.map
	var r := Rng.new(4411)
	var blades: Array = []
	var blooms: Array = []
	var tries := 0
	while blades.size() < TUFTS and tries < TUFTS * 6:
		tries += 1
		var x := (r.next() * 2.0 - 1.0) * (map.half_x + 6.0)
		var z := (r.next() * 2.0 - 1.0) * (map.half_z + 6.0)
		var patch := 0.5 + 0.5 * sin(x * 0.21 + 2.0) * cos(z * 0.17 + 0.5)  # grass grows in drifts, not evenly
		if r.next() > 0.35 + patch * 0.65 or not _grows(map, x, z):
			continue
		var s := 0.7 + r.next() * 0.6
		var xf := Transform3D(Basis(Vector3.UP, r.next() * TAU).scaled(Vector3(s, s * (0.8 + patch * 0.6), s)), Vector3(x, full_h(map, x, z) - 0.03, z))
		var tint := Color(0.11, 0.25, 0.05).lerp(Color(0.2, 0.33, 0.07), r.next()).lerp(Color(0.34, 0.33, 0.1), maxf(0.0, r.next() - 0.75))
		blades.append([xf, tint])
		if blooms.size() < FLOWERS and patch > 0.6 and r.next() < 0.3:
			var fs := 0.5 + r.next() * 0.5
			var at := Vector3(x + r.next() * 0.6 - 0.3, xf.origin.y, z + r.next() * 0.6 - 0.3)
			blooms.append([Transform3D(Basis(Vector3.UP, r.next() * TAU).scaled(Vector3(fs, fs, fs)), at), FLOWER_COLORS[int(r.next() * FLOWER_COLORS.size()) % FLOWER_COLORS.size()]])
	w._grass = _multimesh(w, _tuft_mesh(0.035, 0.3, 7), blades, Color(0.08, 0.2, 0.045), 0.1)
	_multimesh(w, _tuft_mesh(0.05, 0.34, 4), blooms, Color(0.1, 0.24, 0.06), 0.08)


static func _grows(map: GameMap, x: float, z: float) -> bool:
	if absf(x) > map.half_x or absf(z) > map.half_z:
		return true  # the foot of the mountains is green too
	if map.ground_kind(x, z) != "grass" or map.path_weight(x, z) > 0.05:
		return false
	return absf(z - GameMap.RIVER_Z) > GameMap.RIVER_HZ + 3.5 and Vector2(x - GameMap.POND.x, z - GameMap.POND.y).length() > GameMap.POND.z


## A tuft: `blades` thin leaves fanned out from one root, each leaning its own way. Root at y = 0 (UV.y = 1), tip at
## about `height` (UV.y = 0). The same tuft every time: the variety comes from each instance's turn, size and tint.
static func _tuft_mesh(half_w: float, height: float, blades: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var r := Rng.new(31 + blades)
	for c in blades:
		var a := TAU * float(c) / float(blades) + r.next() * 0.8
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-out.z, 0.0, out.x) * half_w
		var foot := out * (0.03 + r.next() * 0.1)
		var tall := height * (0.65 + r.next() * 0.5)
		var lean := out * tall * (0.2 + r.next() * 0.35)
		var b := verts.size()
		verts.append_array(PackedVector3Array([foot - side, foot + side, foot + lean * 0.45 + side * 0.6 + Vector3(0, tall * 0.55, 0), foot + lean * 0.45 - side * 0.6 + Vector3(0, tall * 0.55, 0), foot + lean + Vector3(0, tall, 0)]))
		uvs.append_array(PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(0.8, 0.45), Vector2(0.2, 0.45), Vector2(0.5, 0)]))
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3, b + 3, b + 2, b + 4]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func _multimesh(w: ArenaWorld, mesh: Mesh, items: Array, root: Color, wind: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/valley_grass.gdshader")
	mat.set_shader_parameter("root_color", root)
	mat.set_shader_parameter("wind", wind)
	mat.set_shader_parameter("noise_tex", Textures.spell_noise())
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(node)
	return node


## The mountains' clothes: a thick line of trees and boulders past the edge, and cliffs behind them.
static func _outside(w: ArenaWorld) -> void:
	var map := w.map
	var r := Rng.new(9173)
	for k in 230:
		var x := (r.next() * 2.0 - 1.0) * (map.half_x + 26.0)
		var z := (r.next() * 2.0 - 1.0) * (map.half_z + 26.0)
		var out := maxf(absf(x) - map.half_x, absf(z) - map.half_z)
		if out < 1.5:
			continue
		var kit: String = ["tree_a", "tree_b", "tree_c", "tree_a", "tree_b", "rock_a", "rock_b", "rock_c"][int(r.next() * 8.0) % 8]
		var sc := 1.2 + r.next() * 1.3 + out * 0.03
		var n := w._place_kit(kit, Vector3(x, full_h(map, x, z) - 0.3, z), r.next() * TAU, Vector3(sc, sc, sc))
		if n != null:
			w._tint_materials(n)
	for k in 40:
		var a := TAU * float(k) / 40.0
		var px := cos(a) * (map.half_x + 30.0) * 1.12
		var pz := sin(a) * (map.half_z + 30.0) * 1.12
		var n := w._place_kit("cliff", Vector3(px, full_h(map, px, pz) - 6.0, pz), -a + PI / 2.0, Vector3(1.5, 1.3 + r.next() * 0.8, 1.5))
		if n != null:
			w._tint_materials(n)


## Tizón waits by his fire.
static func _camp(w: ArenaWorld) -> void:
	var scene := load("res://assets/models/tizon.glb") as PackedScene
	if scene == null:
		return
	var tizon := scene.instantiate() as Node3D
	tizon.name = "Tizon"
	tizon.position = Vector3(GameMap.TIZON_AT.x, w.h(GameMap.TIZON_AT.x, GameMap.TIZON_AT.y), GameMap.TIZON_AT.y)
	tizon.rotation.y = deg_to_rad(-25.0)
	tizon.scale = Vector3.ONE * 1.5
	w.add_child(tizon)
	w.tizon = tizon
	for p in tizon.find_children("*", "AnimationPlayer", true, false):
		var player := p as AnimationPlayer
		if player.has_animation("idle"):
			player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			player.play("idle")


## A soft light over each built zone, so they read from far away at dusk.
static func _zone_lights(w: ArenaWorld) -> void:
	w._add_light(Vector3(0, 7.0, -50.0), w._col(w._theme.torch), 2.6, 26.0)
	w._add_light(Vector3(38.0, 6.0, 14.0), Color("#bfd8ff"), 1.8, 22.0)
	w._add_light(Vector3(GameMap.POND.x, 2.0, GameMap.POND.y), Color("#7fe0d0"), 1.4, 14.0)
