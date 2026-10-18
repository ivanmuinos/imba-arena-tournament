class_name UnitModels
extends RefCounted
## Placeholder character models built from primitives (port of the builders in src/units.ts).
## Models face +Z, are ~1.8 m tall and use the team colour on belts/tabards.
## build(cls, team_color) -> {root, weapon, glow: StandardMaterial3D|null, legs: [Node3D]}


static func std(color: Color, emissive: Color = Color.BLACK, energy := 0.0, metal := 0.0, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emissive
		m.emission_energy_multiplier = energy
	return m


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _cone(r: float, h: float, seg := 10) -> Mesh:
	return MeshBuilder.cylinder(0.0, r, h, seg)


static func _dome(r: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r  # hemisphere: height == radius
	m.is_hemisphere = true
	m.radial_segments = 12
	m.rings = 5
	return m


static func _legs(g: Node3D, mat: Material, width := 0.14, radius := 0.12) -> Array:
	var out := []
	for s in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(s * width, 0.78, 0)
		_add(hip, MeshBuilder.capsule(radius, 0.5), mat, Vector3(0, -0.38, 0))
		g.add_child(hip)
		out.append(hip)
	return out


static func build(cls: String, team: Color) -> Dictionary:
	match cls:
		"hunter": return _hunter(team)
		"warrior": return _warrior(team)
		"priest": return _priest(team)
		"rogue": return _rogue(team)
		_: return _mage(team)


static func team_belt(team: Color) -> StandardMaterial3D:
	return std(team, team, 0.5)


static func _mage(team: Color) -> Dictionary:
	var g := Node3D.new()
	var robe := std(Color("#3d1f73"))
	var dark := std(Color("#24123f"))
	var skin := std(Color("#f0c9a0"))
	_add(g, _cone(0.52, 1.35, 12), robe, Vector3(0, 0.68, 0))
	_add(g, MeshBuilder.torus(0.29, 0.05), team_belt(team), Vector3(0, 1.02, 0))
	_add(g, MeshBuilder.sphere(0.3, 10, 6), robe, Vector3(0, 1.28, 0), Vector3.ZERO, Vector3(1.2, 0.8, 0.9))
	_add(g, MeshBuilder.sphere(0.19, 12, 8), skin, Vector3(0, 1.6, 0))
	_add(g, _cone(0.16, 0.42, 8), std(Color("#dddddd")), Vector3(0, 1.38, 0.12), Vector3(PI, 0, 0))
	_add(g, MeshBuilder.cylinder(0.45, 0.45, 0.04, 18), dark, Vector3(0, 1.74, 0))
	_add(g, _cone(0.3, 0.85, 12), dark, Vector3(0, 2.15, -0.04), Vector3(-0.18, 0, 0))
	var staff := Node3D.new()
	staff.position = Vector3(0.48, 0, 0.12)
	_add(staff, MeshBuilder.cylinder(0.035, 0.045, 1.8, 6), std(Color("#5a3a1e")), Vector3(0, 0.95, 0))
	var glow := std(Color("#ff7a1a"), Color("#ff6a00"), 2.4)
	_add(staff, MeshBuilder.sphere(0.14, 8, 5), glow, Vector3(0, 1.92, 0))
	g.add_child(staff)
	return {"root": g, "weapon": staff, "glow": glow, "legs": []}


static func _hunter(team: Color) -> Dictionary:
	var g := Node3D.new()
	var leather := std(Color("#5a4428"))
	var cloth := std(Color("#2f4a22"))
	var skin := std(Color("#d9a77c"))
	var legs := []
	for s in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(s * 0.14, 0.78, 0)
		_add(hip, MeshBuilder.capsule(0.11, 0.5), std(Color("#3a2a18")), Vector3(0, -0.38, 0))
		g.add_child(hip)
		legs.append(hip)
	_add(g, MeshBuilder.capsule(0.27, 0.42, 10), leather, Vector3(0, 1.15, 0))
	_add(g, MeshBuilder.torus(0.22, 0.06), team_belt(team), Vector3(0, 1.47, 0))
	_add(g, MeshBuilder.sphere(0.18, 12, 8), skin, Vector3(0, 1.66, 0))
	_add(g, _dome(0.23), cloth, Vector3(0, 1.64, -0.03), Vector3(-0.3, 0, 0))
	_add(g, _cone(0.12, 0.3, 6), cloth, Vector3(0, 1.9, -0.14), Vector3(-0.9, 0, 0))
	var capem := std(Color("#23361a"))
	capem.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.62, 1.1)
	_add(g, quad, capem, Vector3(0, 0.98, -0.3), Vector3(-0.12, PI, 0))
	var quiver := Node3D.new()
	quiver.position = Vector3(0.18, 1.2, -0.28)
	quiver.rotation.z = -0.35
	_add(quiver, MeshBuilder.cylinder(0.08, 0.07, 0.6, 8), std(Color("#6b3f1e")))
	var tip := std(Color("#ff7a1a"), Color("#ff5a00"), 1.8)
	for ox in [-0.03, 0.03]:
		_add(quiver, _cone(0.03, 0.1, 5), tip, Vector3(ox, 0.38, 0))
	g.add_child(quiver)
	var bow := Node3D.new()
	bow.position = Vector3(-0.32, 1.15, 0.35)
	var wood := std(Color("#7a4a22"))
	for i in 7:  # half-circle limb built from short capsules
		var a := PI * (float(i) / 6.0 - 0.5)
		_add(bow, MeshBuilder.capsule(0.03, 0.12, 5), wood, Vector3(0, sin(a) * 0.55, cos(a) * 0.3 - 0.1), Vector3(a, 0, 0))
	_add(bow, MeshBuilder.cylinder(0.006, 0.006, 1.1, 4), std(Color("#eeeeee")), Vector3(0, 0, -0.1))
	for s in [-1, 1]:
		_add(g, MeshBuilder.capsule(0.075, 0.42, 6), leather, Vector3(s * 0.34, 1.12, 0.12), Vector3(-1.1, 0, 0))
	g.add_child(bow)
	return {"root": g, "weapon": bow, "glow": tip, "legs": legs}


static func _warrior(team: Color) -> Dictionary:
	var g := Node3D.new()
	var plate := std(Color("#8a8f99"), Color.BLACK, 0.0, 0.7, 0.35)
	var dark := std(Color("#3a3f48"), Color.BLACK, 0.0, 0.6, 0.4)
	var skin := std(Color("#d9a77c"))
	var tabard := team_belt(team)
	var legs := _legs(g, dark, 0.15)
	_add(g, MeshBuilder.capsule(0.32, 0.4, 10), plate, Vector3(0, 1.15, 0), Vector3.ZERO, Vector3(1.15, 1, 0.9))
	_add(g, MeshBuilder.box(Vector3(0.62, 0.3, 0.42)), tabard, Vector3(0, 0.88, 0))
	for s in [-1, 1]:
		_add(g, MeshBuilder.sphere(0.2, 8, 5), plate, Vector3(s * 0.42, 1.45, 0), Vector3.ZERO, Vector3(1.2, 0.8, 1.1))
	_add(g, MeshBuilder.sphere(0.19, 12, 8), skin, Vector3(0, 1.68, 0))
	_add(g, _dome(0.22), plate, Vector3(0, 1.66, 0), Vector3.ZERO, Vector3(1, 1.05, 1.05))
	for s in [-1, 1]:
		_add(g, _cone(0.05, 0.28, 6), std(Color("#eee8d8")), Vector3(s * 0.2, 1.9, 0), Vector3(0, 0, -s * 0.9))
	_add(g, MeshBuilder.cylinder(0.34, 0.34, 0.06, 18), tabard, Vector3(-0.42, 1.1, 0.25), Vector3(PI / 2, 0, 0))
	_add(g, MeshBuilder.torus(0.34, 0.035), plate, Vector3(-0.42, 1.1, 0.28), Vector3(PI / 2, 0, 0))
	var sword := Node3D.new()
	sword.position = Vector3(0.45, 1.05, 0.25)
	_add(sword, MeshBuilder.box(Vector3(0.06, 1.1, 0.02)), std(Color("#dfe6ee"), Color.BLACK, 0.0, 0.9, 0.2), Vector3(0, 0.55, 0))
	_add(sword, MeshBuilder.box(Vector3(0.3, 0.05, 0.06)), dark)
	_add(sword, MeshBuilder.cylinder(0.03, 0.03, 0.25, 6), std(Color("#5a3a1e")), Vector3(0, -0.14, 0))
	g.add_child(sword)
	return {"root": g, "weapon": sword, "glow": null, "legs": legs}


static func _priest(team: Color) -> Dictionary:
	var g := Node3D.new()
	var robe := std(Color("#f2eee4"))
	var gold := std(Color("#ffd27a"), Color("#6a4a00"), 0.5, 0.6, 0.3)
	var skin := std(Color("#f0c9a0"))
	_add(g, _cone(0.5, 1.35, 14), robe, Vector3(0, 0.68, 0))
	_add(g, MeshBuilder.torus(0.27, 0.045), team_belt(team), Vector3(0, 1.0, 0))
	_add(g, MeshBuilder.sphere(0.29, 10, 6), robe, Vector3(0, 1.27, 0), Vector3.ZERO, Vector3(1.15, 0.8, 0.9))
	_add(g, MeshBuilder.box(Vector3(0.16, 0.9, 0.02)), gold, Vector3(0, 0.75, 0.33))
	_add(g, MeshBuilder.sphere(0.19, 12, 8), skin, Vector3(0, 1.6, 0))
	_add(g, _dome(0.21), robe, Vector3(0, 1.6, -0.02))
	_add(g, MeshBuilder.torus(0.2, 0.025, 24, 6), std(Color("#fff3c0"), Color("#ffd27a"), 2.4), Vector3(0, 1.98, 0))
	var staff := Node3D.new()
	staff.position = Vector3(0.46, 0, 0.12)
	_add(staff, MeshBuilder.cylinder(0.03, 0.04, 1.75, 6), gold, Vector3(0, 0.9, 0))
	var glow := std(Color("#fff3c0"), Color("#ffe08a"), 2.6)
	_add(staff, MeshBuilder.sphere(0.13, 4, 2), glow, Vector3(0, 1.86, 0))
	g.add_child(staff)
	return {"root": g, "weapon": staff, "glow": glow, "legs": []}


static func _rogue(team: Color) -> Dictionary:
	var g := Node3D.new()
	var leather := std(Color("#2a2430"))
	var cloth := std(Color("#1b1820"))
	var skin := std(Color("#d9a77c"))
	var legs := _legs(g, leather, 0.13)
	_add(g, MeshBuilder.capsule(0.24, 0.42, 10), leather, Vector3(0, 1.15, 0))
	_add(g, MeshBuilder.torus(0.2, 0.05), team_belt(team), Vector3(0, 1.47, 0))
	_add(g, MeshBuilder.sphere(0.17, 12, 8), skin, Vector3(0, 1.64, 0))
	_add(g, _dome(0.22), cloth, Vector3(0, 1.64, -0.03), Vector3(-0.25, 0, 0))
	_add(g, MeshBuilder.box(Vector3(0.3, 0.1, 0.06)), cloth, Vector3(0, 1.58, 0.15))
	var glow := std(Color("#9be7ff"), Color("#6ab8ff"), 1.8)
	var blades := Node3D.new()
	for s in [-1, 1]:
		var dag := Node3D.new()
		dag.position = Vector3(s * 0.36, 1.0, 0.25)
		_add(dag, _cone(0.04, 0.45, 4), glow, Vector3(0, 0.25, 0))
		_add(dag, MeshBuilder.cylinder(0.025, 0.025, 0.14, 6), std(Color("#5a3a1e")), Vector3(0, -0.04, 0))
		dag.rotation.x = 0.6
		blades.add_child(dag)
	g.add_child(blades)
	var capem := std(Color("#15121a"))
	capem.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.95)
	_add(g, quad, capem, Vector3(0, 0.98, -0.28), Vector3(-0.1, PI, 0))
	return {"root": g, "weapon": blades, "glow": glow, "legs": legs}


static func sheep() -> Node3D:
	var g := Node3D.new()
	var wool := std(Color.WHITE, Color.BLACK, 0.0, 0.0, 1.0)
	for p in [[0, 0.55, 0, 0.42], [0.25, 0.6, 0.15, 0.3], [-0.25, 0.6, 0.15, 0.3], [0, 0.65, -0.3, 0.32], [0, 0.8, 0.05, 0.3]]:
		_add(g, MeshBuilder.sphere(p[3], 10, 6), wool, Vector3(p[0], p[1], p[2]))
	var dark := std(Color("#222222"))
	_add(g, MeshBuilder.sphere(0.2, 8, 5), dark, Vector3(0, 0.68, 0.45))
	for s in [-1, 1]:
		for z in [-0.2, 0.2]:
			_add(g, MeshBuilder.cylinder(0.05, 0.05, 0.35, 5), dark, Vector3(s * 0.18, 0.17, z))
	return g
