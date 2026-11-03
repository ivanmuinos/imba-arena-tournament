class_name GameMenu
extends Control
## In-match options (Esc), two tabs: General (HUD sizes applied live, so they can be tuned in the 10 s of preparation
## or in the practice arena; volume and mouse sensitivity) and Teclas (rebind your abilities and the trinket: click a
## key, press the new one, Esc leaves it unbound). Resume / leave / quit below. It never pauses the match.

signal setting_changed(key: String)
signal binds_pressed
## A key was rebound from the Teclas tab (the HUD redraws its labels).
signal keys_changed
signal leave_pressed
signal quit_pressed

const WIDTH := 470.0

var _sliders := {}  # key -> [HSlider, value Label, format, multiplier]
var _leave: MButton
var _quit: MButton
var _resume: MButton
var _leave_text := "Abandonar partida"
var _tabs: Segmented
var _pages := {}  # tab id -> VBoxContainer
var _key_buttons := {}  # action -> MButton
var _key_names := {}  # action -> Label (the ability's name)
var _key_status: Label
## Action waiting for its new key ("" = none); while set, match_view hands key presses to capture_key().
var capturing := ""
## Class / spec whose ability names the Teclas tab shows (match_view sets them before open()).
var kit_cls := "mage"
var kit_spec := ""


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP  # clicks around the panel do not reach the world
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.28)  # light: the HUD being resized stays visible behind it
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudArt.panel_style(18))
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position.y = -60  # above the ability bar, which should stay in view while it is resized
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	col.add_child(UiKit.heading("OPCIONES", 26, UiKit.GOLD, 700, 3, HORIZONTAL_ALIGNMENT_CENTER))
	var note := UiKit.caption("La partida sigue mientras el menú está abierto.", UiKit.MUTED, 12)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(note)
	_tabs = Segmented.new().setup([["general", "General"], ["keys", "Teclas"]], "general").as_tabs()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.changed.connect(show_tab)
	col.add_child(_tabs)
	var general := _page(col, "general")
	_build_keys(_page(col, "keys"))
	col = general
	col.add_child(UiKit.caption("TAMAÑO DEL HUD", UiKit.GOLD, 13))
	_slider(col, "bar_scale", "Barra de habilidades", SettingsStore.BAR_MIN, SettingsStore.BAR_MAX, "%d%%", 100.0)
	_slider(col, "enemy_frame_scale", "Marcos de oponentes", SettingsStore.FRAME_MIN, SettingsStore.FRAME_MAX, "%d%%", 100.0)
	_slider(col, "ally_frame_scale", "Marcos de tu equipo", SettingsStore.FRAME_MIN, SettingsStore.FRAME_MAX, "%d%%", 100.0)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	var reset := MButton.new("Tamaños por defecto", "ghost")
	reset.add_theme_font_size_override("font_size", 15)
	reset.pressed.connect(_reset_hud)
	tools.add_child(reset)
	col.add_child(tools)
	col.add_child(UiKit.caption("SONIDO Y MOUSE", UiKit.GOLD, 13))
	_slider(col, "master", "Volumen general", 0.0, 1.0, "%d%%", 100.0)
	_slider(col, "sfx", "Efectos", 0.0, 1.0, "%d%%", 100.0)
	_slider(col, "sens", "Sensibilidad del mouse", SettingsStore.SENS_MIN, SettingsStore.SENS_MAX, "x%.2f")
	col = general.get_parent()
	col.add_child(UiKit.spacer(6))
	_resume = MButton.new("Continuar", "accent")
	_resume.custom_minimum_size.y = 40
	_resume.pressed.connect(close)
	col.add_child(_resume)
	var exits := HBoxContainer.new()
	exits.add_theme_constant_override("separation", 8)
	col.add_child(exits)
	_leave = MButton.new(_leave_text, "secondary")
	_leave.pressed.connect(func(): _confirm(_leave, _leave_text, leave_pressed))
	_quit = MButton.new("Salir del juego", "secondary")
	_quit.pressed.connect(func(): _confirm(_quit, "Salir del juego", quit_pressed))
	for b in [_leave, _quit]:
		b.custom_minimum_size.y = 38
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		exits.add_child(b)


## The leave button's wording: the host's leaving closes the match for everyone.
func set_leave_text(text: String) -> void:
	_leave_text = text
	_leave.text = text


func open() -> void:
	capturing = ""
	show_tab("general")
	_refresh_keys()
	var st := SettingsStore.shared()
	for key in _sliders:
		(_sliders[key][0] as HSlider).set_value_no_signal(float(st.get_value(key)))
		_show_value(key)
	_leave.text = _leave_text
	_quit.text = "Salir del juego"
	visible = true
	_resume.grab_focus()  # keyboard / gamepad can drive it from the start


func close() -> void:
	if not visible:
		return
	capturing = ""
	visible = false
	SettingsStore.shared().save()
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()


## Leaving and quitting ask for a second click instead of a dialog.
func _confirm(b: MButton, text: String, done: Signal) -> void:
	if b.text == text:
		b.text = "¿Seguro? Otro clic"
		return
	close()
	done.emit()


func _reset_hud() -> void:
	var st := SettingsStore.shared()
	for key in SettingsStore.HUD_SCALES:
		st.set_value(key, 1.0)
		(_sliders[key][0] as HSlider).set_value_no_signal(1.0)
		_show_value(key)
	setting_changed.emit("bar_scale")


func _slider(parent: Control, key: String, title: String, lo: float, hi: float, fmt: String, mult := 1.0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiKit.label(title, 15, UiKit.INK)
	l.custom_minimum_size.x = 180
	row.custom_minimum_size.y = 28
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05 if hi > 1.0 else 0.01
	s.custom_minimum_size = Vector2(170, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	row.add_child(s)
	var val := UiKit.label("", 15, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	val.custom_minimum_size.x = 56
	row.add_child(val)
	parent.add_child(row)
	_sliders[key] = [s, val, fmt, mult]
	s.value_changed.connect(func(v):
		SettingsStore.shared().set_value(key, v)
		_show_value(key)
		setting_changed.emit(key))


func _show_value(key: String) -> void:
	var d: Array = _sliders[key]
	(d[1] as Label).text = str(d[2]) % (float(SettingsStore.shared().get_value(key)) * float(d[3]))


func show_tab(id: String) -> void:
	capturing = ""
	_refresh_keys()
	if _tabs.value != id:
		_tabs.select(id, false)
	for k in _pages:
		(_pages[k] as Control).visible = k == id


func _page(parent: Control, id: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.visible = id == "general"
	parent.add_child(v)
	_pages[id] = v
	return v


## Teclas: one row per ability of your champion (its real name) and the trinket, each with its key as a button.
func _build_keys(page: VBoxContainer) -> void:
	page.add_child(UiKit.caption("TECLAS DE TUS PODERES", UiKit.GOLD, 13))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	page.add_child(grid)
	GameData.ensure_loaded()
	var actions: Array = []
	for i in int(GameData.C.SLOT_COUNT):
		actions.append("slot_%d" % i)
	actions.append("trinket")
	for a in actions:
		var l := UiKit.label("", 15, UiKit.INK)
		l.custom_minimum_size = Vector2(250, 30)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(l)
		_key_names[a] = l
		var b := MButton.new("", "secondary")
		b.custom_minimum_size = Vector2(150, 30)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func():
			_refresh_keys()
			capturing = a
			b.text = "Apretá una tecla…")
		grid.add_child(b)
		_key_buttons[a] = b
	_key_status = UiKit.caption("Clic en una tecla y apretá la nueva · Esc: dejarla sin tecla", UiKit.MUTED, 12)
	_key_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_key_status)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	var reset := MButton.new("Teclas por defecto", "ghost")
	reset.add_theme_font_size_override("font_size", 15)
	reset.pressed.connect(func():
		var d := Keybinds.defaults()
		for a in _key_buttons:
			Keybinds.shared().bind(a, d[a])
		Keybinds.shared().save()
		_refresh_keys()
		keys_changed.emit())
	var bar_mode := MButton.new("Asignar desde la barra", "ghost")
	bar_mode.add_theme_font_size_override("font_size", 15)
	bar_mode.pressed.connect(func():
		close()
		binds_pressed.emit())
	tools.add_child(reset)
	tools.add_child(bar_mode)
	page.add_child(tools)


func _refresh_keys() -> void:
	var kb := Keybinds.shared()
	var abilities := GameData.abilities(kit_cls, GameData.normalize_spec(kit_cls, kit_spec)) if GameData.playable(kit_cls) else []
	for a in _key_buttons:
		(_key_buttons[a] as MButton).text = kb.label(a)
		var name := Keybinds.action_label(a)
		if a.begins_with("slot_"):
			var i := int(a.substr(5))
			if i < abilities.size():
				name = ("Definitiva: " if abilities[i].get("ult", false) else "%d. " % (i + 1)) + str(abilities[i].name)
		(_key_names[a] as Label).text = name


## A key pressed while waiting for one (match_view forwards it): binds it, Esc unbinds. Returns true when used.
func capture_key(event: InputEvent) -> bool:
	if capturing == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var k := event as InputEventKey
	if k.keycode in [KEY_CTRL, KEY_ALT, KEY_META]:
		return true  # wait for the real key of a combination (Shift alone is a valid key)
	var action := capturing
	capturing = ""
	var key := "" if k.keycode == KEY_ESCAPE else Keybinds.event_name(k)
	var lost := Keybinds.shared().bind(action, key)
	Keybinds.shared().save()
	_refresh_keys()
	if lost != "":
		_key_status.text = "%s ahora es %s (se la sacó a %s)" % [(_key_names[action] as Label).text, key, Keybinds.action_label(lost)]
	else:
		_key_status.text = "%s: %s" % [(_key_names[action] as Label).text, kb_text(key)]
	keys_changed.emit()
	return true


static func kb_text(key: String) -> String:
	return "sin tecla" if key == "" else key.replace("Space", "Espacio")
