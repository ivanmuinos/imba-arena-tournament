class_name TopBar
extends Control
## Client top bar (Riot-style): logo, the big JUGAR button, section tabs with an underline on the active one, Volver
## inside a play flow, and on the right the profile card (avatar, name, status) with settings and quit.
## Lives on the menu's design stage, full width, HEIGHT tall; MenuScreen wires the signals.

signal play_pressed
signal tab_pressed(id: String)
signal back_pressed
signal settings_pressed
signal quit_pressed

const HEIGHT := 64.0
## Width of the profile card, which is also the width of the friends column under it.
const SIDE := 280.0
const TABS := [["hub", "Inicio"], ["champions", "Campeones"], ["howto", "Cómo jugar"]]

var play: MButton
var back: MButton
var settings: Button
var quit: Button
var name_edit: LineEdit
var persona: Label
var status: Label
var avatar: TextureRect
var active := ""

var _tabs := {}  # id -> Button
var _dot: Panel


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.022, 0.018, 0.94)
	sb.border_color = UiKit.LINE
	sb.border_width_bottom = 1
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var logo := UiKit.heading("IMBA", 24, Color("#ffcf6a"), 700, 3)
	UiKit.outlined(logo, 5, Color("#3a1204"))
	logo.position = Vector2(20, 15)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	play = MButton.new("JUGAR", "primary", "ui_play")
	play.position = Vector2(100, 13)
	play.custom_minimum_size = Vector2(176, 38)
	play.size = Vector2(176, 38)
	play.add_theme_font_size_override("font_size", 22)
	play.pressed.connect(func(): play_pressed.emit())
	add_child(play)
	var row := HBoxContainer.new()
	row.position = Vector2(300, 0)
	row.size = Vector2(0, HEIGHT)
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for t in TABS:
		var b := _tab_button(str(t[1]))
		b.pressed.connect(func(): tab_pressed.emit(t[0]))
		row.add_child(b)
		_tabs[t[0]] = b
	back = MButton.new("Volver", "ghost", "ui_back")
	back.custom_minimum_size = Vector2(120, 38)
	back.add_theme_font_size_override("font_size", 16)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.position = Vector2(-SIDE - 16 - 120, 13)
	back.size = Vector2(120, 38)
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	_build_profile()


## MButton sizes itself for the big menu variant when built; in the bar it is shorter, set once it is in the tree.
func _ready() -> void:
	play.size = play.custom_minimum_size


func _tab_button(text: String) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, HEIGHT)
	b.add_theme_font_override("font", UiKit.display(700, 2))
	b.add_theme_font_size_override("font_size", 17)
	for k in ["font_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, UiKit.MUTED)
	b.add_theme_color_override("font_hover_color", UiKit.INK)
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 16
	pad.content_margin_right = 16
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(s, pad)
	var focus := UiKit.box(Color(1, 1, 1, 0.04), UiKit.GOLD, 6, 1, 0)
	focus.content_margin_left = 16
	focus.content_margin_right = 16
	b.add_theme_stylebox_override("focus", focus)
	b.mouse_entered.connect(func(): UiSound.play("uiHover"))
	b.pressed.connect(func(): UiSound.play("uiConfirm"))
	var bar := ColorRect.new()
	bar.name = "Underline"
	bar.color = UiKit.GOLD
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -3
	bar.offset_left = 14
	bar.offset_right = -14
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	b.add_child(bar)
	return b


func _build_profile() -> void:
	var side := Control.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -SIDE
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(side)
	var sep := ColorRect.new()
	sep.color = UiKit.LINE
	sep.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	sep.offset_right = 1
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(sep)
	var frame := Panel.new()
	frame.position = Vector2(16, 12)
	frame.size = Vector2(40, 40)
	frame.add_theme_stylebox_override("panel", UiKit.box(Color(0.1, 0.06, 0.04, 1), UiKit.GOLD, 20, 2, 0))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(frame)
	avatar = TextureRect.new()
	avatar.position = Vector2(20, 16)
	avatar.size = Vector2(32, 32)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.texture = Icons.tex("ui_user")
	avatar.modulate = UiKit.GOLD
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(avatar)
	_dot = Panel.new()
	_dot.position = Vector2(46, 42)
	_dot.size = Vector2(12, 12)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(_dot)
	persona = UiKit.heading("", 18, UiKit.INK, 700, 1)
	persona.position = Vector2(66, 10)
	persona.size = Vector2(130, 24)
	persona.clip_text = true
	persona.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	persona.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(persona)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Tu nombre"
	name_edit.max_length = 16
	name_edit.flat = true
	name_edit.position = Vector2(60, 6)
	name_edit.size = Vector2(136, 30)
	name_edit.add_theme_font_override("font", UiKit.display(700, 1))
	name_edit.add_theme_font_size_override("font_size", 18)
	name_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	name_edit.add_theme_stylebox_override("focus", UiKit.box(Color(1, 1, 1, 0.07), UiKit.GOLD, 6, 1, 4))
	name_edit.tooltip_text = "Tu nombre (se puede editar acá)"
	name_edit.text_submitted.connect(func(_t): name_edit.release_focus())
	side.add_child(name_edit)
	status = UiKit.label("", 12, UiKit.MUTED)
	status.position = Vector2(66, 34)
	status.size = Vector2(130, 18)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(status)
	settings = _icon_button("ui_gear", "Configuración")
	settings.position = Vector2(SIDE - 84, 14)
	settings.pressed.connect(func(): settings_pressed.emit())
	side.add_child(settings)
	quit = _icon_button("ui_door", "Salir del juego")
	quit.position = Vector2(SIDE - 46, 14)
	quit.pressed.connect(func(): quit_pressed.emit())
	side.add_child(quit)


func _icon_button(icon_id: String, tip: String) -> Button:
	var b := Button.new()
	b.icon = Icons.tex(icon_id)
	b.expand_icon = true
	b.flat = true
	b.size = Vector2(36, 36)
	b.custom_minimum_size = Vector2(36, 36)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_constant_override("icon_max_width", 20)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for k in ["icon_normal_color", "icon_focus_color"]:
		b.add_theme_color_override(k, UiKit.MUTED)
	for k in ["icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(k, UiKit.INK)
	b.add_theme_stylebox_override("hover", UiKit.box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 8, 0, 0))
	b.add_theme_stylebox_override("focus", UiKit.box(Color(1, 1, 1, 0.04), UiKit.GOLD, 8, 1, 0))
	b.mouse_entered.connect(func(): UiSound.play("uiHover"))
	return b


func tab(id: String) -> Button:
	return _tabs.get(id)


## id: a tab id, "play" (JUGAR and the play flow) or "" (nothing highlighted, e.g. settings).
func set_active(id: String) -> void:
	active = id
	for k in _tabs:
		var on: bool = k == id
		var b: Button = _tabs[k]
		b.get_node("Underline").visible = on
		for c in ["font_color", "font_focus_color", "font_pressed_color"]:
			b.add_theme_color_override(c, UiKit.INK if on else UiKit.MUTED)
	play.modulate = Color(1.15, 1.1, 1.0) if id == "play" else Color.WHITE


## Steam: its name (not editable) and "En línea"; without Steam the editable name and "Sin Steam".
func set_profile(steam_name: String, saved_name: String, online: bool) -> void:
	persona.visible = steam_name != ""
	name_edit.visible = steam_name == ""
	persona.text = steam_name
	if not name_edit.has_focus():
		name_edit.text = saved_name
	status.text = "En línea" if online else "Sin Steam"
	status.add_theme_color_override("font_color", UiKit.GREEN if online else UiKit.DIM)
	_dot.add_theme_stylebox_override("panel", UiKit.box(UiKit.GREEN if online else UiKit.DIM, Color(0.035, 0.022, 0.018), 6, 2, 0))


func set_avatar(tex: Texture2D) -> void:
	avatar.texture = tex
	avatar.modulate = Color.WHITE
