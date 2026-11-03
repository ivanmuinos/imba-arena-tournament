extends SceneTree
## Battle pass sample sheet (needs a real window, not --headless):
##   godot --path . --script res://tools/render_skin_samples.gd --resolution 1600x900 -- <out.png>
## Base model next to each sample skin, a pet skin, and a nameplate with a title and a lobby frame.

const SHEET := Vector2i(2000, 1120)
const CELL := Vector2i(300, 400)

const SKINS := [
	{"cls": "mage", "name": "Archimago de Escarcha", "rarity": "Épica", "skin": {"id": "frost_archmage", "recolor": {"hue": -0.17, "sat": -0.35, "val": 0.35}, "hide": ["Mage_Hat"], "cape": "#2b6fb8",
		"accessories": ["crown", "orbs"], "palette": {"trim": "#d6ecff", "glow": "#7fd8ff"}}},
	{"cls": "warrior", "name": "Caballero del Ocaso", "rarity": "Legendaria", "skin": {"id": "dusk_knight", "recolor": {"hue": 0.0, "sat": 0.0, "val": -0.62}, "cape": "#8a1414",
		"accessories": ["horned_helm", "pauldrons"], "palette": {"trim": "#e0aa3e", "glow": "#ff3a1a"}}},
	{"cls": "warlock", "name": "Señor del Abismo", "rarity": "Épica", "skin": {"id": "abyss_lord", "recolor": {"hue": 0.25, "sat": 0.2, "val": -0.3}, "cape": "#5a0c0c",
		"palette": {"shadow": "#3a1010", "deep": "#1a0606", "fel": "#d8341c", "fel_glow": "#ff4a1a"}}},
]
const PET := {"name": "Fénix de Escarcha", "rarity": "Rara", "over": {"tint": {"Wings": "#2a7fe2", "Head": "#7fd0ff", "Beak": "#e8f6ff", "Claws": "#103060"}, "glow": "#3ab8ff", "bond": "#8fe4ff"}}
const RARITY := {"Rara": "#4aa8ff", "Épica": "#c45be0", "Legendaria": "#ffc15a", "Base": "#a99c90"}

var _sheet: SubViewport


func _init() -> void:
	GameData.ensure_loaded()
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://skin_samples.png"
	_sheet = SubViewport.new()
	_sheet.size = SHEET
	_sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_sheet)
	var bg := ColorRect.new()
	bg.color = Color("#140d0b")
	bg.size = Vector2(SHEET)
	_sheet.add_child(bg)
	var title := UiKit.heading("PASE DE BATALLA  ·  TEMPORADA 1  ·  MUESTRA", 34, UiKit.GOLD)
	title.position = Vector2(40, 22)
	_sheet.add_child(title)
	var x := 40
	for s in SKINS:
		_cell(Vector2(x, 90), s.cls, {}, "Base", "Base")
		_cell(Vector2(x + CELL.x + 10, 90), s.cls, s.skin, s.name, s.rarity)
		x += CELL.x * 2 + 40
	_pet_cell(Vector2(40, 600), "warrior", {}, "Fénix (base)", "Base")  # cls only picks the team colour
	_pet_cell(Vector2(40 + CELL.x + 10, 600), "warrior", PET.over, PET.name, PET.rarity)
	_plates(Vector2(700, 610))
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := _sheet.get_texture().get_image()
	img.save_png(out)
	var zoom := img.get_region(Rect2i(Vector2i(40, 90), Vector2i(CELL.x * 4 + 50, CELL.y)))  # mage and warrior pairs, enlarged
	zoom.resize(zoom.get_width() * 2, zoom.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	zoom.save_png(out.get_basename() + "_zoom.png")
	print("muestra ", out)
	quit()


func _stage(pos: Vector2, tint: Color) -> SubViewport:
	var box := SubViewportContainer.new()
	box.position = pos
	box.size = Vector2(CELL)
	box.stretch = true
	_sheet.add_child(box)
	var frame := Panel.new()
	frame.position = pos
	frame.size = Vector2(CELL) + Vector2(0, 64)
	frame.add_theme_stylebox_override("panel", UiKit.box(Color(0.06, 0.04, 0.035), UiKit.LINE, 10, 1, 0))
	_sheet.add_child(frame)
	_sheet.move_child(frame, box.get_index())
	var vp := SubViewport.new()
	vp.size = CELL
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	box.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1d1411").lerp(tint, 0.08)
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
	return vp


func _caption(pos: Vector2, name: String, rarity: String) -> void:
	var n := UiKit.heading(name.to_upper(), 20, UiKit.INK, 700, 1, HORIZONTAL_ALIGNMENT_CENTER)
	n.position = pos + Vector2(0, CELL.y + 6)
	n.size = Vector2(CELL.x, 26)
	_sheet.add_child(n)
	var r := UiKit.caption(rarity, Color(RARITY[rarity]), 14)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.position = pos + Vector2(0, CELL.y + 34)
	r.size = Vector2(CELL.x, 20)
	_sheet.add_child(r)


func _cell(pos: Vector2, cls: String, skin: Dictionary, name: String, rarity: String) -> void:
	var vp := _stage(pos, UiKit.class_color(cls))
	var rig := CharacterRig.new()
	rig.setup(cls, Color("#ffb84d"), skin)
	rig.root.rotation.y = 0.45
	vp.add_child(rig.root)
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.1, 1.6, 7.6), Vector3(0, 1.05, 0))
	_caption(pos, name, rarity)


func _pet_cell(pos: Vector2, _cls: String, over: Dictionary, name: String, rarity: String) -> void:
	var vp := _stage(pos, Color(str(over.get("glow", "#ff5a08"))))
	var def := CompanionView.def_for("mage", "fire").duplicate(true)
	def.merge(over, true)
	var pet := CompanionView.new()
	pet.setup(def, Color("#ffb84d"), null)
	vp.add_child(pet)
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.4, 0.9, 3.2), Vector3(0, 0.45, 0))
	_caption(pos, name, rarity)


## A nameplate with a title under the name, and lobby rows with and without a season frame.
func _plates(pos: Vector2) -> void:
	var h := UiKit.heading("TÍTULOS Y MARCOS", 22, UiKit.GOLD)
	h.position = pos
	_sheet.add_child(h)
	var plate := Nameplate.new().setup("Emi", true, true, Color("#ff5a52"))
	plate.position = pos + Vector2(20, 60)
	plate.scale = Vector2(2.2, 2.2)
	_sheet.add_child(plate)
	var t := UiKit.label("« Azote de la Lava »", 13, Color("#ff9a3a"), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(t, 5)
	t.position = Vector2(0, 6)
	t.size = Vector2(Nameplate.W, 14)
	plate.add_child(t)
	var rows := [["Emi", "Brujo · Aflicción", "« Azote de la Lava »", "#ff9a3a", "lava"], ["Ivan", "Guerrero", "« Invicto »", "#ffc15a", "gold"], ["Bot", "Mago · Fuego", "", "", ""]]
	var y := 70.0
	for r in rows:
		var row := PanelContainer.new()
		row.position = pos + Vector2(360, y)
		row.custom_minimum_size = Vector2(620, 74)
		var border := Color("#3a2a22")
		var bw := 1
		if r[4] == "lava":
			border = Color("#ff7a1a")
			bw = 3
		elif r[4] == "gold":
			border = Color("#ffc94a")
			bw = 3
		var sb := UiKit.box(Color(0.07, 0.045, 0.04), border, 10, bw, 12)
		if r[4] != "":
			sb.shadow_color = Color(border, 0.45)
			sb.shadow_size = 10
		row.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		row.add_child(hb)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		hb.add_child(vb)
		vb.add_child(UiKit.heading(r[0], 22, UiKit.INK))
		vb.add_child(UiKit.caption(r[1], UiKit.MUTED, 13))
		if r[2] != "":
			var tl := UiKit.label(r[2], 16, Color(r[3]))
			tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(tl)
		_sheet.add_child(row)
		y += 92.0
	var note := UiKit.caption("Marco de temporada (lava / oro) en la sala · título bajo el nombre, en el nameplate y en la sala", UiKit.MUTED, 14)
	note.position = pos + Vector2(360, y + 4)
	_sheet.add_child(note)
