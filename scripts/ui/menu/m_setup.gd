class_name MSetup
extends MenuView
## Match setup: 2v2/3v3, bot difficulty, team, (port / Steam privacy) and the map picker with thumbnails.

var _mode: Segmented
var _diff: Segmented
var _pref: Segmented
var _port_box: Control
var _port: LineEdit
var _priv_box: Control
var _priv: Segmented
var _maps := {}
var _title_box: Control
var _next: MButton
var _subtitle: Label


func _ready() -> void:
	_title_box = header("Configurar partida", "")
	_subtitle = _title_box.get_child(1)
	# left: options
	var panel := UiKit.glass(UiKit.LINE, 14, 22)
	panel.position = Vector2(72, 196)
	panel.custom_minimum_size = Vector2(330, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	panel.add_child(col)
	_mode = _field(col, "Modo", Segmented.new().setup([["2", "2v2"], ["3", "3v3"]], "2"))
	_diff = _field(col, "Bots", Segmented.new().setup([["easy", "Fácil"], ["normal", "Normal"], ["hard", "Difícil"]], "normal"))
	_pref = _field(col, "Tu equipo", Segmented.new().setup([["any", "Al azar"], ["red", "Rojo"], ["blue", "Azul"]], "any"))
	_priv = Segmented.new().setup([["friends", "Sólo amigos"], ["public", "Pública"]], "friends")
	_priv_box = _field_box(col, "Sala de Steam", _priv)
	_port = LineEdit.new()
	_port.custom_minimum_size = Vector2(140, 42)
	_port.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_port_box = _field_box(col, "Puerto UDP", _port)
	_mode.changed.connect(func(v): menu.st.set_value("mode", int(v)))
	_diff.changed.connect(func(v): menu.st.set_value("diff", v))
	_pref.changed.connect(func(v): menu.st.set_value("pref", v))
	_priv.changed.connect(func(v): menu.st.set_value("steam_friends", v == "friends"))
	_port.text_changed.connect(func(t): if SettingsStore.parse_port(t) > 0: menu.st.set_value("port", SettingsStore.parse_port(t)))
	# right: map cards
	var title := UiKit.caption("Arena", UiKit.MUTED, 13)
	title.position = Vector2(430, 196)
	add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(430, 222)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	add_child(grid)
	GameData.ensure_loaded()
	var ids: Array = GameMap.IDS.duplicate()
	ids.append("random")
	for id in ids:
		var spec: Dictionary = GameData.maps.get(id, {"name": "Aleatoria", "desc": "Una arena distinta cada vez"})
		var c := Card.new("", str(spec.name), str(spec.desc), UiKit.LAVA, _thumb(id))
		c.custom_minimum_size = Vector2(250, 214)
		var sub: Label = c.get_child(1).get_child(c.get_child(1).get_child_count() - 2)
		sub.add_theme_font_size_override("font_size", 12)
		var t: Label = c.get_child(1).get_child(c.get_child(1).get_child_count() - 3)
		t.add_theme_font_size_override("font_size", 24)
		c.pressed.connect(_pick_map.bind(id))
		grid.add_child(c)
		_maps[id] = c
	_next = MButton.new("CONTINUAR", "primary")
	_next.position = Vector2(72, 470)
	_next.size = Vector2(330, 66)
	_next.custom_minimum_size = Vector2(330, 66)
	_next.pressed.connect(func(): menu.next_step())
	add_child(_next)


func _thumb(id: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 84)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if id == "random":
		var bg := ColorRect.new()
		bg.color = Color(0.16, 0.08, 0.05)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(bg)
		var ic := Icons.rect("ui_map_random", 72)
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ic.position -= Vector2(36, 36)
		ic.modulate = UiKit.GOLD
		holder.add_child(ic)
	else:
		var tr := TextureRect.new()
		tr.texture = Portraits.map_tex(id)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	return holder


func _field(parent: Control, title: String, seg: Segmented) -> Segmented:
	_field_box(parent, title, seg)
	return seg


func _field_box(parent: Control, title: String, ctl: Control) -> Control:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 5)
	b.add_child(UiKit.caption(title))
	b.add_child(ctl)
	parent.add_child(b)
	return b


func _pick_map(id: String) -> void:
	menu.st.set_value("map", id)
	_mark_maps()
	menu.map_changed.emit(id)


func _mark_maps() -> void:
	var cur := str(menu.st.get_value("map"))
	for id in _maps:
		_maps[id].selected = id == cur


func menu_enter() -> void:
	var st := menu.st
	_mode.select(str(st.get_value("mode")), false)
	_diff.select(str(st.get_value("diff")), false)
	_pref.select(str(st.get_value("pref")), false)
	_priv.select("friends" if st.get_value("steam_friends") else "public", false)
	_port.text = str(st.get_value("port"))
	var m := menu.nav.mode
	_priv_box.visible = m == "steam_host"
	_port_box.visible = m == "host"
	_subtitle.text = {"practice": "Práctica contra bots. Los lugares libres se llenan con bots.", "host": "Vas a ser el anfitrión: los lugares libres se llenan con bots.",
		"steam_host": "Sala de Steam: tus amigos entran desde Steam."}.get(m, "")
	_mark_maps()


func first_focus() -> Control:
	return _maps.get(str(menu.st.get_value("map")))


func hints() -> Array:
	return [["Flechas", "Navegar"], ["Enter", "Elegir"], ["Esc", "Volver"]]
