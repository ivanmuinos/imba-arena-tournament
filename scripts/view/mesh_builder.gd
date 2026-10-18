class_name MeshBuilder
extends RefCounted
## Bakes many primitive meshes into one flat-shaded, vertex-coloured ArrayMesh (a tree, a
## bush, a ruin...). Keeps the scenery to a few hundred draw calls.

static var _prims := {}

static func clear_cache() -> void:
	_prims.clear()


var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()


static func xf(pos := Vector3.ZERO, euler := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(euler) * Basis.from_scale(scale), pos)


# --- cached primitives (same key -> same mesh) ---

static func sphere(r: float, seg := 7, rings := 4) -> Mesh:
	var k := "s%f/%d/%d" % [r, seg, rings]
	if not _prims.has(k):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = seg
		m.rings = rings
		_prims[k] = m
	return _prims[k]


static func cylinder(r_top: float, r_bottom: float, h: float, seg := 8) -> Mesh:
	var k := "c%f/%f/%f/%d" % [r_top, r_bottom, h, seg]
	if not _prims.has(k):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bottom
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		_prims[k] = m
	return _prims[k]


static func box(size: Vector3) -> Mesh:
	var k := "b%s" % str(size)
	if not _prims.has(k):
		var m := BoxMesh.new()
		m.size = size
		_prims[k] = m
	return _prims[k]


static func capsule(r: float, length: float, seg := 8) -> Mesh:
	var k := "k%f/%f/%d" % [r, length, seg]
	if not _prims.has(k):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = length + r * 2.0
		m.radial_segments = seg
		m.rings = 3
		_prims[k] = m
	return _prims[k]


static func torus(radius: float, tube: float, seg := 16, ring_seg := 6) -> Mesh:
	var k := "t%f/%f/%d/%d" % [radius, tube, seg, ring_seg]
	if not _prims.has(k):
		var m := TorusMesh.new()
		m.inner_radius = radius - tube
		m.outer_radius = radius + tube
		m.rings = seg
		m.ring_segments = ring_seg
		_prims[k] = m
	return _prims[k]


## Flat ring on the XZ plane (faces up).
static func ring(inner: float, outer: float, seg := 40) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in seg:
		var a := TAU * i / seg
		v.append(Vector3(cos(a) * inner, 0, sin(a) * inner))
		v.append(Vector3(cos(a) * outer, 0, sin(a) * outer))
		n.append(Vector3.UP)
		n.append(Vector3.UP)
	for i in seg:
		var a := i * 2
		var b := ((i + 1) % seg) * 2
		idx.append_array(PackedInt32Array([a, a + 1, b, b, a + 1, b + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Filled disc on the XZ plane (faces up).
static func disc(r: float, seg := 40) -> ArrayMesh:
	var v := PackedVector3Array([Vector3.ZERO])
	var n := PackedVector3Array([Vector3.UP])
	var uv := PackedVector2Array([Vector2(0.5, 0.5)])
	var idx := PackedInt32Array()
	for i in seg:
		var a := TAU * i / seg
		v.append(Vector3(cos(a) * r, 0, sin(a) * r))
		n.append(Vector3.UP)
		uv.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
	for i in seg:
		idx.append_array(PackedInt32Array([0, 1 + i, 1 + (i + 1) % seg]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- baking ---

func add(mesh: Mesh, t: Transform3D, color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var nb := t.basis.inverse().transposed()
	color = color.srgb_to_linear()  # vertex colours are linear; callers think in web colours
	var count: int = idx.size() if idx != null else v.size()
	for i in range(0, count, 3):
		var i0: int = idx[i] if idx != null else i
		var i1: int = idx[i + 1] if idx != null else i + 1
		var i2: int = idx[i + 2] if idx != null else i + 2
		var fn := (nb * (n[i0] + n[i1] + n[i2])).normalized()
		_verts.append(t * v[i0])
		_verts.append(t * v[i1])
		_verts.append(t * v[i2])
		for k in 3:
			_norms.append(fn)
			_cols.append(color)


func is_empty() -> bool:
	return _verts.is_empty()


func build() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _verts
	arr[Mesh.ARRAY_NORMAL] = _norms
	arr[Mesh.ARRAY_COLOR] = _cols
	var m := ArrayMesh.new()
	if not _verts.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
