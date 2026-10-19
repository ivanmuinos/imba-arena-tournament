class_name MSettings
extends MenuView
## Settings tabs: Gráficos / Controles / Audio / Juego / Macros. Everything persists through SettingsStore (macros:
## MacroStore).

const TABS := [["graficos", "Gráficos"], ["controles", "Controles"], ["audio", "Audio"], ["juego", "Juego"], ["macros", "Macros"]]
## Fixed (not rebindable); everything else is in Keybinds.
const KEYS := [
	["Moverse", "W A S D  /  flechas"], ["Seleccionar", "Click izquierdo"], ["Auto-ataque", "Click derecho en un enemigo"],
	["Girar / orbitar", "Mantener click derecho / izquierdo"], ["Zoom", "Rueda del mouse"], ["Cancelar / soltar objetivo", "Esc"],
]

var _tabs: Segmented
var _pages := {}
var _slider_labels := {}
var _gfx: Segmented
var _full: Segmented
var _invert: Segmented
var _pets: Segmented
var _name: LineEdit
var _sliders := {}
var _gfx_info: Label
var _holder: Control
var _panel: PanelContainer
var _macros := MacroStore.new()
var _macro_sel := 0
var _macro_list: Array[MButton] = []
var _macro_key: MButton
var _macro_text: TextEdit
var _macro_err: Label
var _capturing := ""  # action waiting for its new key ("" = none)
var _bind_buttons := {}  # action -> MButton


func _ready() -> void:
	header("Configuración", "")
	_tabs = Segmented.new().setup(TABS, "graficos")
	_tabs.position = Vector2(72, 164)
	_tabs.add_theme_constant_override("separation", 8)
	add_child(_tabs)
	_tabs.changed.connect(select_tab)
	var panel := UiKit.glass(UiKit.LINE, 14, 26)
	panel.position = Vector2(72, 220)
	panel.custom_minimum_size = Vector2(860, 0)
	add_child(panel)
	_panel = panel
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(808, 330)
	panel.add_child(holder)
	_holder = holder
	# Gráficos
	var g := _page(holder, "graficos")
	_gfx = Segmented.new().setup([["auto", "Auto"], ["alta", "Alta"], ["media", "Media"], ["baja", "Baja"]], "auto")
	_row(g, "Calidad gráfica", "Auto elige según tu equipo. Baja ayuda en PCs modestas.", _gfx)
	_full = Segmented.new().setup([["off", "Ventana"], ["on", "Pantalla completa"]], "off")
	_row(g, "Pantalla", "", _full)
	_gfx_info = UiKit.label("", 13, UiKit.MUTED)
	_gfx_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gfx_info.custom_minimum_size = Vector2(780, 0)
	g.add_child(UiKit.spacer(10))
	g.add_child(UiKit.caption("Tu equipo", UiKit.MUTED, 12))
	g.add_child(_gfx_info)
	_gfx.changed.connect(func(v): menu.st.set_value("gfx", v); menu.settings_changed("gfx"); _update_gfx_info())
	_full.changed.connect(func(v): menu.st.set_value("fullscreen", v == "on"); menu.settings_changed("fullscreen"))
	# Controles
	var c := _page(holder, "controles")
	_slider(c, "sens", "Sensibilidad del mouse", SettingsStore.SENS_MIN, SettingsStore.SENS_MAX, 0.05, "x%.2f")
	_invert = Segmented.new().setup([["off", "Normal"], ["on", "Invertido"]], "off")
	_row(c, "Eje vertical de la cámara", "", _invert)
	_invert.changed.connect(func(v): menu.st.set_value("invert", v == "on"); menu.settings_changed("invert"))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	c.add_child(UiKit.caption("Fijas", UiKit.MUTED, 12))
	c.add_child(grid)
	_build_bindings(c)
	for k in KEYS:
		var a := UiKit.label(k[0], 12, UiKit.MUTED)
		a.custom_minimum_size = Vector2(120, 0)
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(a)
		var kk := UiKit.heading(k[1], 13, UiKit.INK, 600, 1)
		kk.custom_minimum_size = Vector2(140, 0)
		kk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(kk)
	# Audio
	var a := _page(holder, "audio")
	_slider(a, "master", "Volumen general", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_slider(a, "music", "Música del menú", 0.0, 1.0, 0.01, "%d%%", 100.0)
	_slider(a, "sfx", "Efectos", 0.0, 1.0, 0.01, "%d%%", 100.0)
	# Juego
	var j := _page(holder, "juego")
	_name = LineEdit.new()
	_name.max_length = 16
	_name.placeholder_text = "Nombre del campeón"
	_name.custom_minimum_size = Vector2(300, 46)
	_name.add_theme_font_size_override("font_size", 19)
	_name.text_changed.connect(func(t): menu.st.set_value("name", t); menu.settings_changed("name"))
	_row(j, "Nombre", "Es el que ven los demás jugadores (hasta 16 caracteres).", _name)
	_pets = Segmented.new().setup([["on", "Mostrar"], ["off", "Ocultar"]], "on")
	_row(j, "Compañeros", "La mascota de cada clase (lobo, toro, hada...). Es sólo visual; se aplica en la próxima partida.", _pets)
	_pets.changed.connect(func(v): menu.st.set_value("companions", v == "on"); menu.settings_changed("companions"))
	var reset := MButton.new("Restablecer valores", "secondary")
	reset.custom_minimum_size = Vector2(260, 44)
	reset.pressed.connect(_reset)
	j.add_child(UiKit.spacer(14))
	j.add_child(reset)
	_build_macros(_page(holder, "macros"))


## Macros: six slots on the left, the selected one's key and text on the right, the syntax under it.
func _build_macros(page: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	page.add_child(row)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size = Vector2(230, 0)
	row.add_child(list)
	for i in MacroStore.COUNT:
		var b := MButton.new("", "secondary")
		b.custom_minimum_size = Vector2(230, 44)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_select_macro.bind(i))
		list.add_child(b)
		_macro_list.append(b)
	var ed := VBoxContainer.new()
	ed.add_theme_constant_override("separation", 8)
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ed)
	_macro_key = MButton.new("", "accent")
	_macro_key.custom_minimum_size = Vector2(260, 40)
	_macro_key.pressed.connect(func():
		_capturing = "macro_%d" % (_macro_sel + 1)
		_macro_key.text = "Apretá la tecla (Esc: sin tecla)…")
	ed.add_child(_macro_key)
	_macro_text = TextEdit.new()
	_macro_text.custom_minimum_size = Vector2(540, 170)
	_macro_text.add_theme_font_size_override("font_size", 15)
	_macro_text.placeholder_text = "#Nombre
/cast [@focus] Polimorfia"
	_macro_text.text_changed.connect(_macro_edited)
	ed.add_child(_macro_text)
	_macro_err = UiKit.label("", 12, Color("#ff9b7a"))
	ed.add_child(_macro_err)
	var help := UiKit.label(Macro.HELP, 12, UiKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(540, 0)
	ed.add_child(help)
	_select_macro(0)


func _macro_title(i: int) -> String:
	var name := "(vacía)" if _macros.is_empty(i) else _macros.title(i)
	return "%s  ·  %s" % [Keybinds.shared().label("macro_%d" % (i + 1)), name]


func _select_macro(i: int) -> void:
	_macro_sel = i
	_capturing = ""
	for j in _macro_list.size():
		_macro_list[j].text = ("▶ " if j == i else "") + _macro_title(j)
	var m: Dictionary = _macros.macros[i]
	_macro_key.text = "Tecla: %s (cambiar)" % Keybinds.shared().label("macro_%d" % (i + 1))
	_macro_text.text = str(m.text)
	_check_macro()


func _macro_edited() -> void:
	_macros.set_text(_macro_sel, _macro_text.text)
	_macros.save()
	_macro_list[_macro_sel].text = "▶ " + _macro_title(_macro_sel)
	_check_macro()


func _check_macro() -> void:
	var parsed := Macro.parse(_macro_text.text, str(menu.st.get_value("cls")), str(menu.st.get_value("spec")))
	_macro_err.text = "" if parsed.errors.is_empty() else ("Con tu campeón actual: " + " · ".join(parsed.errors))


## Every rebindable action (Keybinds.ACTIONS) with a button: click it, then press the new key (Esc: no key).
func _build_bindings(parent: Control) -> void:
	parent.add_child(UiKit.caption("Teclas (clic y apretá la nueva · Esc: sin tecla · en partida también con el modo teclas)", UiKit.MUTED, 12))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	for a in Keybinds.ACTIONS:
		var l := UiKit.label(str(a[1]).replace(" (reasignar en partida)", "").replace(" (básica)", ""), 12, UiKit.MUTED)
		l.custom_minimum_size = Vector2(140, 0)
		grid.add_child(l)
		var b := MButton.new("", "secondary")
		b.custom_minimum_size = Vector2(110, 28)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			_capturing = a[0]
			b.text = "Apretá…")
		grid.add_child(b)
		_bind_buttons[a[0]] = b
	var reset := MButton.new("Teclas por defecto", "ghost")
	reset.pressed.connect(func():
		Keybinds.shared().reset()
		Keybinds.shared().save()
		_refresh_bindings())
	parent.add_child(reset)
	_refresh_bindings()


func _refresh_bindings() -> void:
	for a in _bind_buttons:
		(_bind_buttons[a] as MButton).text = Keybinds.shared().label(a)
	if _macro_list.size() > 0:
		_select_macro(_macro_sel)


func _input(event: InputEvent) -> void:
	if _capturing == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode in [KEY_CTRL, KEY_ALT, KEY_META]:
		return  # wait for the real key of a combination (Shift alone is a valid key)
	get_viewport().set_input_as_handled()
	var action := _capturing
	_capturing = ""
	var key := "" if k.keycode == KEY_ESCAPE else Keybinds.event_name(k)
	var lost := Keybinds.shared().bind(action, key)
	Keybinds.shared().save()
	_refresh_bindings()
	if lost != "":
		menu.set_status("%s ahora es %s (se la sacó a %s)" % [Keybinds.action_label(action), key, Keybinds.action_label(lost)])


func _page(parent: Control, id: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.visible = false
	parent.add_child(v)
	_pages[id] = v
	return v


func _row(parent: Control, title: String, hint: String, ctl: Control) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 20)
	var l := VBoxContainer.new()
	l.custom_minimum_size = Vector2(300, 0)
	l.add_child(UiKit.heading(title, 22, UiKit.INK, 600, 1))
	if hint != "":
		var h := UiKit.label(hint, 12, UiKit.MUTED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_child(h)
	r.add_child(l)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ctl)
	parent.add_child(r)


func _slider(parent: Control, key: String, title: String, lo: float, hi: float, step: float, fmt: String, mult := 1.0) -> void:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(320, 26)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.add_child(s)
	var val := UiKit.heading("", 20, UiKit.GOLD, 700, 1, HORIZONTAL_ALIGNMENT_RIGHT)
	val.custom_minimum_size = Vector2(70, 0)
	box.add_child(val)
	_sliders[key] = s
	_slider_labels[key] = [val, fmt, mult]
	s.value_changed.connect(func(v):
		menu.st.set_value(key, v)
		_update_label(key)
		menu.settings_changed(key))
	s.drag_ended.connect(func(_c):
		if key == "master":
			UiSound.play("uiConfirm")
		elif key == "sfx":
			UiSound.play("hit"))
	_row(parent, title, "", box)


func _update_label(key: String) -> void:
	var d: Array = _slider_labels[key]
	d[0].text = d[1] % (float(menu.st.get_value(key)) * d[2])


func _update_gfx_info() -> void:
	var level := Quality.resolve(str(menu.st.get_value("gfx")), Quality.initial_level(RenderingServer.get_video_adapter_type(), Quality.compatibility_renderer()))
	var q: Dictionary = Quality.settings(level)
	_gfx_info.text = "%s  ·  %s\nNivel %s: sombras %s, niebla volumétrica %s, oclusión ambiental %s, partículas %d%%. En \"Auto\" baja solo si los cuadros por segundo caen." % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(), level.to_upper(),
		"sí" if q.shadows else "no", "sí" if q.volumetric_fog else "no", "sí" if q.ssao else "no", int(q.particles * 100.0)]


func select_tab(id: String) -> void:
	for k in _pages:
		_pages[k].visible = k == id
	if _holder != null:
		_holder.custom_minimum_size.y = {"graficos": 250.0, "controles": 560.0, "audio": 200.0, "juego": 300.0, "macros": 420.0}.get(id, 300.0)
		_panel.reset_size()
	_tabs.select(id, false)


func menu_enter() -> void:
	var st := menu.st
	_gfx.select(str(st.get_value("gfx")), false)
	_full.select("on" if st.get_value("fullscreen") else "off", false)
	_update_gfx_info()
	_invert.select("on" if st.get_value("invert") else "off", false)
	_pets.select("on" if st.get_value("companions") else "off", false)
	_name.text = str(st.get_value("name"))
	for k in _sliders:
		(_sliders[k] as HSlider).set_value_no_signal(float(st.get_value(k)))
		_update_label(k)
	select_tab(_tabs.value)


func _reset() -> void:
	var fresh := SettingsStore.new()
	for k in ["gfx", "fullscreen", "master", "music", "sfx", "sens", "invert", "companions"]:
		menu.st.set_value(k, fresh.get_value(k))
	menu.settings_changed("gfx")
	menu_enter()
	menu.set_status("Configuración restablecida.")


func first_focus() -> Control:
	return _tabs.get_child(0)


func hints() -> Array:
	return [["Flechas", "Navegar"], ["Esc", "Volver"]]
