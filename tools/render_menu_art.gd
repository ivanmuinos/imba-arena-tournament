extends SceneTree
## Renders the menu art from the real game assets (needs a real window, not --headless):
##   godot --path . --script res://tools/render_menu_art.gd --resolution 1280x720
## Writes assets/ui/portraits/<class>.png (transparent bust, lit with the class colour)
## and assets/ui/maps/<map>.png (aerial view of each arena).

const PORTRAIT := Vector2i(512, 640)
const THUMB := Vector2i(640, 400)


func _init() -> void:
	GameData.ensure_loaded()
	await process_frame
	var only := OS.get_cmdline_user_args()
	for id in GameData.classes:
		if not only.is_empty() and not only.has(id): continue
		await _portrait(id)
	for id in GameMap.IDS:
		if not only.is_empty() and not only.has(id): continue
		await _thumb(id)
	quit()


func _viewport(size: Vector2i, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = transparent
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	return vp


func _portrait(cls: String) -> void:
	var tint: Color = UiKit.class_color(cls)
	var vp := _viewport(PORTRAIT, true)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.48, 0.52).lerp(tint, 0.15)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 2.2
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 205, 0)
	rim.light_energy = 2.6
	rim.light_color = tint.lerp(Color(1, 0.6, 0.3), 0.35)
	vp.add_child(rim)
	var rig := CharacterRig.new()
	rig.setup(cls, Color("#ffb84d"))
	rig.root.rotation.y = 0.45
	vp.add_child(rig.root)
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	if cls == "warlock" or cls == "priest":  # horns and the staff skull are taller than the other heads: pull back
		cam.look_at_from_position(Vector3(0.15, 1.55, 5.4), Vector3(0, 1.2, 0))
	else:
		cam.look_at_from_position(Vector3(0.15, 1.45, 4.2), Vector3(0, 1.1, 0))
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("res://assets/ui/portraits/%s.png" % cls)
	print("retrato ", cls)
	vp.queue_free()


func _thumb(map_id: String) -> void:
	var vp := _viewport(THUMB, false)
	var w := ArenaWorld.new()
	vp.add_child(w)
	w.setup(GameMap.create(map_id))
	var cam := Camera3D.new()
	cam.fov = 52
	cam.far = 600
	vp.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0, 55, 49), Vector3(0, 0, 3))
	w.follow(0.0, 0.0)
	for i in 70:
		await process_frame
		w.update(0.05, Time.get_ticks_msec() / 1000.0)
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("res://assets/ui/maps/%s.png" % map_id)
	print("mapa ", map_id)
	vp.queue_free()
