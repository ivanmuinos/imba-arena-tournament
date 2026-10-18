class_name EndScreen
extends StagedScreen
## Victory/defeat screen: big result, score, and per-team tables with portraits and stat bars.

signal again_pressed
signal menu_pressed

var _title: Label
var _score: RichTextLabel
var _teams := {}
var _again: MButton
var _mvp := ""


func _ready() -> void:
	_title = UiKit.heading("VICTORIA", 120, Color.WHITE, 700, 8, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(_title, 14, Color("#3a1204"))
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 14
	_title.offset_bottom = 150
	if UiKit.shaders_ok():
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/logo.gdshader")
		m.set_shader_parameter("area", Vector2(700, 130))
		_title.material = m
	stage.add_child(_title)
	_score = RichTextLabel.new()
	_score.bbcode_enabled = true
	_score.fit_content = true
	_score.scroll_active = false
	_score.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_score.offset_top = 150
	_score.offset_bottom = 210
	_score.add_theme_font_override("normal_font", UiKit.display(700, 3))
	_score.add_theme_font_size_override("normal_font_size", 38)
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_score)
	for t in ["red", "blue"]:
		var tint: Color = UiKit.RED if t == "red" else UiKit.BLUE
		var p := UiKit.glass(Color(tint.r, tint.g, tint.b, 0.7), 14, 16)
		p.position = Vector2(72 if t == "red" else 668, 250)
		p.custom_minimum_size = Vector2(540, 0)
		stage.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		p.add_child(v)
		v.add_child(UiKit.heading("EQUIPO ROJO" if t == "red" else "EQUIPO AZUL", 20, tint, 700, 3))
		v.add_child(_header_row())
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 5)
		v.add_child(list)
		_teams[t] = list
	_again = MButton.new("VOLVER", "primary", "ui_play")
	_again.position = Vector2(72, 620)
	_again.size = Vector2(340, 66)
	_again.custom_minimum_size = Vector2(340, 66)
	_again.pressed.connect(func(): again_pressed.emit())
	stage.add_child(_again)
	var menu := MButton.new("Menú principal", "secondary", "ui_back")
	menu.position = Vector2(428, 628)
	menu.size = Vector2(230, 50)
	menu.custom_minimum_size = Vector2(230, 50)
	menu.pressed.connect(func(): menu_pressed.emit())
	stage.add_child(menu)


func _header_row() -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(64, 0)
	r.add_child(sp)
	var n := UiKit.caption("Campeón", UiKit.MUTED, 11)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(n)
	for pair in [["Daño", 100], ["Curación", 90], ["Bajas", 44], ["Muertes", 54]]:
		var l := UiKit.caption(pair[0], UiKit.MUTED, 11)
		l.custom_minimum_size = Vector2(pair[1], 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if pair[1] < 60 else HORIZONTAL_ALIGNMENT_LEFT
		r.add_child(l)
	return r


func _bar_cell(value: int, top: int, tint: Color, width: int) -> Control:
	var c := VBoxContainer.new()
	c.custom_minimum_size = Vector2(width, 0)
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_theme_constant_override("separation", 2)
	c.add_child(UiKit.heading(str(value), 20, UiKit.INK if value > 0 else UiKit.DIM, 700, 1))
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(width - 14, 4)
	bar.color = Color(1, 1, 1, 0.08)
	var fill := ColorRect.new()
	fill.color = tint
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.anchor_right = clampf(float(value) / maxf(1.0, float(top)), 0.0, 1.0)
	bar.add_child(fill)
	c.add_child(bar)
	return c


func _num_cell(value: int, width: int, color: Color) -> Control:
	var l := UiKit.heading(str(value), 22, color if value > 0 else UiKit.DIM, 700, 1, HORIZONTAL_ALIGNMENT_RIGHT)
	l.custom_minimum_size = Vector2(width, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## rows: [{name, team, cls, dmg, kills, deaths, heal}]
func show_result(win: bool, score: Dictionary, rows: Array, again_text: String) -> void:
	_title.text = "VICTORIA" if win else "DERROTA"
	var m := _title.material as ShaderMaterial
	if m != null:
		m.set_shader_parameter("top", Color(1.0, 0.93, 0.68) if win else Color(1.0, 0.7, 0.66))
		m.set_shader_parameter("bottom", Color(1.0, 0.45, 0.08) if win else Color(0.75, 0.12, 0.12))
	_score.text = "[center][color=#%s]ROJO %d[/color]   [color=#a99c90]-[/color]   [color=#%s]%d AZUL[/color][/center]" % [UiKit.RED.to_html(false), score.red, UiKit.BLUE.to_html(false), score.blue]
	_again.text = again_text
	var top_dmg := 1
	var top_heal := 1
	var best := -1.0
	for r in rows:
		top_dmg = maxi(top_dmg, int(r.dmg))
		top_heal = maxi(top_heal, int(r.heal))
		var sc: float = float(r.dmg) + float(r.heal) + 300.0 * float(r.kills) - 100.0 * float(r.get("deaths", 0))
		if sc > best:
			best = sc
			_mvp = str(r.name)
	for t in _teams:
		for c in (_teams[t] as Control).get_children():
			c.queue_free()
	rows.sort_custom(func(a, b): return a.dmg + a.heal > b.dmg + b.heal)
	for r in rows:
		var tint: Color = UiKit.RED if r.team == "red" else UiKit.BLUE
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.06), Color(tint.r, tint.g, tint.b, 0.25), 8, 1, 6))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		row.add_child(h)
		var art := TextureRect.new()
		art.texture = Portraits.bust(str(r.cls))
		art.custom_minimum_size = Vector2(64, 48)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		h.add_child(art)
		var tc := VBoxContainer.new()
		tc.alignment = BoxContainer.ALIGNMENT_CENTER
		tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 6)
		nr.add_child(UiKit.heading(str(r.name), 20, UiKit.INK, 700, 1))
		if str(r.name) == _mvp:
			var star := Icons.rect("ui_star", 16)
			star.modulate = UiKit.GOLD
			star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			nr.add_child(star)
			nr.add_child(UiKit.heading("MVP", 12, UiKit.GOLD, 700, 2))
		tc.add_child(nr)
		tc.add_child(UiKit.label(str(GameData.classes[r.cls].name), 12, UiKit.MUTED))
		h.add_child(tc)
		h.add_child(_bar_cell(int(r.dmg), top_dmg, UiKit.LAVA, 100))
		h.add_child(_bar_cell(int(r.heal), top_heal, UiKit.GREEN, 90))
		h.add_child(_num_cell(int(r.kills), 44, UiKit.GOLD))
		h.add_child(_num_cell(int(r.get("deaths", 0)), 54, UiKit.MUTED))
		(_teams[r.team] as Control).add_child(row)
