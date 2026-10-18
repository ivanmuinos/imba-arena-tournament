class_name ClassShowcase
extends SubViewportContainer
## Champion on a lit pedestal with the class colour in the lights, embers and a glowing ring.
## Drag to rotate (with inertia); idles with the class idle animation and plays a cast/attack on select.

var _vp := SubViewport.new()
var _pivot := Node3D.new()
var _rig: CharacterRig = null
var _pet: CompanionView = null
var _pet_key := ""
var _cls := ""
var _t := 0.0
var _next_move := 6.0
var _spin_v := 0.0
var _drag := false
var _rim: DirectionalLight3D
var _fill: OmniLight3D
var _ring_mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D
var _embers: CPUParticles3D
var _cam: Camera3D


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.46, 0.5)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.3
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32, 32, 0)
	key.light_energy = 1.55
	key.shadow_enabled = true
	_vp.add_child(key)
	_rim = DirectionalLight3D.new()
	_rim.rotation_degrees = Vector3(-14, 205, 0)
	_rim.light_energy = 2.2
	_vp.add_child(_rim)
	_fill = OmniLight3D.new()
	_fill.position = Vector3(-2.2, 0.6, 2.2)
	_fill.light_energy = 1.6
	_fill.omni_range = 8.0
	_vp.add_child(_fill)
	# pedestal: dark metal disc + glowing ring in the class colour
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.25
	cm.bottom_radius = 1.4
	cm.height = 0.16
	disc.mesh = cm
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.albedo_color = Color(0.1, 0.08, 0.075)
	_disc_mat.metallic = 0.7
	_disc_mat.roughness = 0.32
	disc.material_override = _disc_mat
	disc.position.y = -0.08
	_vp.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.12
	tm.outer_radius = 1.2
	tm.rings = 48
	tm.ring_segments = 8
	ring.mesh = tm
	ring.scale = Vector3(1, 0.5, 1)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.emission_enabled = true
	ring.material_override = _ring_mat
	ring.position.y = 0.02
	_vp.add_child(ring)
	_embers = CPUParticles3D.new()
	_embers.amount = 36
	_embers.lifetime = 3.4
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 1.2
	_embers.direction = Vector3.UP
	_embers.spread = 14.0
	_embers.gravity = Vector3(0, 0.25, 0)
	_embers.initial_velocity_min = 0.25
	_embers.initial_velocity_max = 0.8
	_embers.scale_amount_min = 0.025
	_embers.scale_amount_max = 0.055
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.vertex_color_use_as_albedo = true
	em.albedo_color = Color(1, 1, 1)
	sm.material = em
	_embers.mesh = sm
	_embers.position.y = 0.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.2, 1))
	curve.add_point(Vector2(1, 0))
	_embers.scale_amount_curve = curve
	_vp.add_child(_embers)
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 34
	_vp.add_child(_cam)
	_cam.look_at_from_position(Vector3(0, 1.4, 6.0), Vector3(0, 0.95, 0))
	gui_input.connect(_on_input)


func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
		if e.pressed:
			_spin_v = 0.0
	elif e is InputEventMouseMotion and _drag:
		_pivot.rotation.y += e.relative.x * 0.012
		_spin_v = e.relative.x * 0.012 * 60.0


func _tint(c: Color) -> void:
	_rim.light_color = c.lerp(Color(1, 0.6, 0.35), 0.25)
	_fill.light_color = c.lightened(0.2)
	_ring_mat.albedo_color = c
	_ring_mat.emission = c
	_ring_mat.emission_energy_multiplier = 2.2
	_disc_mat.emission_enabled = true
	_disc_mat.emission = c
	_disc_mat.emission_energy_multiplier = 0.12
	_embers.color = c.lightened(0.35)


func show_class(cls: String, team := Color("#ffb84d"), spec := "") -> void:
	_show_pet(cls, spec, team)
	if cls == _cls:
		return
	_cls = cls
	_tint(UiKit.class_color(cls))
	if _rig != null and _rig.root != null:
		_rig.root.queue_free()
	_rig = null
	if not CharacterRig.available(cls):
		return
	_rig = CharacterRig.new()
	_rig.setup(cls, team)
	_pivot.add_child(_rig.root)
	_pivot.rotation.y = 0.5
	_spin_v = 0.0
	_t = 0.0
	_next_move = 5.0
	play_select(Time.get_ticks_msec() / 1000.0)


## The class companion beside the champion on the pedestal (changes with the specialization: phoenix / frost elemental).
func _show_pet(cls: String, spec: String, team: Color) -> void:
	var def := CompanionView.def_for(cls, spec) if CompanionView.enabled() else {}
	var key := str(def)
	if key == _pet_key:
		return
	_pet_key = key
	if _pet != null:
		_pet.queue_free()
		_pet = null
	if def.is_empty():
		return
	_pet = CompanionView.new()
	_pet.setup(def, team, null)
	_pivot.add_child(_pet)


## Short cast/attack on selection (the model "answers" the click).
func play_select(now: float) -> void:
	if _rig == null:
		return
	var anim := "attack" if _cls in ["warrior", "rogue"] else "cast"
	_rig.once(anim, now, 1.0)


func _process(dt: float) -> void:
	if _rig == null or not is_visible_in_tree():
		return
	_t += dt
	if not _drag:
		_pivot.rotation.y += (_spin_v + 0.0) * dt
		_spin_v = lerpf(_spin_v, 0.0, minf(1.0, dt * 2.5))
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, 0.5, minf(1.0, dt * 0.35)) if absf(_spin_v) < 0.05 else _pivot.rotation.y
	_cam.position.y = 1.4 + sin(_t * 0.6) * 0.03
	var now := Time.get_ticks_msec() / 1000.0
	if _t >= _next_move:
		_next_move = _t + 6.0
		_rig.once("attack" if _cls in ["warrior", "rogue"] and randf() < 0.5 else "cast", now, 1.0)
	_rig.drive(now, true, false, false, 0.0, false, 1.0)
	if _pet != null:
		_pet.track(dt, _t, Vector3.ZERO, 0.0, Vector2.ZERO, true, true, 0.0)
		_pet.position = Vector3(0.95, _pet.position.y * 0.85, 0.35)  # on the pedestal, a little in front of the champion
		_pet.rotation.y = deg_to_rad(float(_pet.def.get("yaw", 0.0))) + 0.35
