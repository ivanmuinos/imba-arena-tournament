extends SceneTree
## Close-up screenshots of one companion from 3 angles (side, front, back): godot --path . --script res://tools/companion_shot.gd -- <cls> <spec or -> <out prefix>
var _n := 0
var _cam: Camera3D
var _pet: CompanionView
var _out := ""
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[2]
	GameData.ensure_loaded()
	UnitView.live_params = true
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.22, 0.2)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	_pet = CompanionView.new()
	_pet.setup(CompanionView.def_for(a[0], a[1] if a[1] != "-" else ""), Color.RED, null)
	root.add_child(_pet)
	_cam = Camera3D.new()
	_cam.fov = 35
	root.add_child(_cam)
	get_root().size = Vector2i(900, 700)
func _process(dt: float) -> bool:
	_n += 1
	_pet.track(dt, _n * dt, Vector3(-1.0, 0, 0.35), 0.0, Vector2.ZERO, true, true, 0.0)
	var views := [Vector3(2.6, 1.4, 1.2), Vector3(-0.2, 1.3, 3.0), Vector3(0.0, 2.4, -2.6)]
	var v: int = clampi((_n - 1) / 40, 0, 2)
	_cam.look_at_from_position(_pet.position + views[v], _pet.position + Vector3(0, 0.45, 0))
	if _n % 40 == 39:
		get_root().get_texture().get_image().save_png("%s_%d.png" % [_out, v])
		if v == 2:
			return true
	return false
