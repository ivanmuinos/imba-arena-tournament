class_name MChampions
extends MenuView
## Champion select: lit 3D pedestal, role tags, stat bars, ability row with tooltips, portrait roster.

const CLASS_SOUND := {"warlock": "vanish", "mage": "fireball", "hunter": "shot", "warrior": "heavySwing", "priest": "heal", "rogue": "vanish", "druid": "renew", "ct": "shot", "ronin": "heavySwing", "crack": "golazo", "wizard": "guardian", "ki": "awaken"}
const STATS := [["hp", "Vida", "ui_stat_hp"], ["mobility", "Movilidad", "ui_stat_speed"], ["damage", "Daño", "ui_stat_dmg"], ["control", "Control", "ui_stat_cc"], ["difficulty", "Dificultad", "ui_stat_diff"]]

var _show: ClassShowcase
var _name: Label
var _tagline: Label
var _tags: HBoxContainer
var _bars := {}
var _abil_row: HBoxContainer
var _slots: Array = []
var _tiles := {}
var _tip: UiTip
## Band of the 1280 px menu canvas the roster row is centred in: right of the specialization cards, to the right margin.
const ROSTER_X0 := 284.0
const ROSTER_X1 := 1208.0

var _confirm: MButton
var _panel: Control
var _cls := ""
var _spec_box: VBoxContainer
var _spec_cards := {}


func _ready() -> void:
	_show = ClassShowcase.new()
	_show.position = Vector2(250, 60)
	_show.size = Vector2(560, 500)
	_show.custom_minimum_size = Vector2(560, 500)
	add_child(_show)
	_name = UiKit.heading("", 72, Color.WHITE, 700, 4)
	UiKit.outlined(_name, 12, Color(0.05, 0.02, 0.01, 0.9))
	_name.position = Vector2(72, 118)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	_tagline = UiKit.label("", 17, Color("#e6d9cc"))
	UiKit.outlined(_tagline, 5, Color(0, 0, 0, 0.8))
	_tagline.position = Vector2(76, 250)
	_tagline.custom_minimum_size = Vector2(200, 0)
	_tagline.size = Vector2(190, 90)
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tagline)
	_tags = HBoxContainer.new()
	_tags.position = Vector2(76, 196)
	_tags.add_theme_constant_override("separation", 8)
	_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tags)
	# right column: stats/abilities panel with the confirm button right under it (the roster below gets the full width)
	var right := VBoxContainer.new()
	right.position = Vector2(800, 84)
	right.add_theme_constant_override("separation", 14)
	add_child(right)
	var p := UiKit.glass(UiKit.LINE, 14, 22)
	p.custom_minimum_size = Vector2(408, 0)
	right.add_child(p)
	_panel = p
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	p.add_child(col)
	col.add_child(UiKit.caption("Estadísticas", UiKit.MUTED, 12))
	for s in STATS:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		var ic := Icons.rect(s[2], 18)
		ic.modulate = UiKit.MUTED
		r.add_child(ic)
		var l := UiKit.heading(str(s[1]).to_upper(), 14, UiKit.INK, 600, 2)
		l.custom_minimum_size = Vector2(104, 0)
		r.add_child(l)
		var b := StatBar.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(b)
		_bars[s[0]] = b
		col.add_child(r)
	col.add_child(UiKit.spacer(8))
	col.add_child(UiKit.caption("Habilidades (pasá el mouse o enfocá para ver)", UiKit.MUTED, 12))
	_abil_row = HBoxContainer.new()
	_abil_row.add_theme_constant_override("separation", 8)
	col.add_child(_abil_row)
	for i in 7:
		var slot := _make_slot(i)
		_abil_row.add_child(slot)
		_slots.append(slot)
	col.add_child(UiKit.spacer(6))
	var role := UiKit.label("", 14, UiKit.MUTED)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role.name = "RoleLine"
	col.add_child(role)
	# roster: one row centred in its band; tiles narrow down when there are many champions
	var n := GameData.playable_ids().size()
	var gap := 12.0
	var tile_w := minf(104.0, (ROSTER_X1 - ROSTER_X0 - gap * (n - 1)) / n)
	var rrow := HBoxContainer.new()
	rrow.position = Vector2(ROSTER_X0 + (ROSTER_X1 - ROSTER_X0 - (tile_w * n + gap * (n - 1))) / 2.0, 548)
	rrow.add_theme_constant_override("separation", int(gap))
	add_child(rrow)
	for id in GameData.playable_ids():
		var t := RosterTile.new(id)
		t.custom_minimum_size = Vector2(tile_w, 112)
		t.fit_name(tile_w)
		t.pressed.connect(select.bind(id, true))
		rrow.add_child(t)
		_tiles[id] = t
	_confirm = MButton.new("CONFIRMAR", "primary", "ui_check")
	_confirm.custom_minimum_size = Vector2(408, 66)
	_confirm.pressed.connect(_on_confirm)
	right.add_child(_confirm)
	_tip = UiTip.new()
	_tip.z_index = 20
	add_child(_tip)


func _make_slot(i: int) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(46, 56)
	for s in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	var ic := Icons.rect("fireball", 46)
	ic.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ic.offset_bottom = 46
	ic.material = HudArt.circle_mask()  # the painted icons are round: shown in a circle, ringed below
	b.add_child(ic)
	b.set_meta("icon", ic)
	var key := UiKit.heading("", 12, UiKit.MUTED, 700, 1, HORIZONTAL_ALIGNMENT_CENTER)
	key.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	key.offset_top = -12
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(key)
	b.set_meta("key", key)
	b.pivot_offset = Vector2(23, 23)
	b.mouse_entered.connect(_tip_for.bind(i, true))
	b.mouse_exited.connect(_tip_for.bind(i, false))
	b.focus_entered.connect(_tip_for.bind(i, true))
	b.focus_exited.connect(_tip_for.bind(i, false))
	b.draw.connect(func():
		var c := Vector2(23, 23)
		var a: Dictionary = b.get_meta("ability", {})
		b.draw_arc(c, 23.5, 0.0, TAU, 48, UiKit.GOLD if a.get("ult", false) else Color("#8a6a3a"), 2.5 if a.get("ult", false) else 2.0, true)
		if b.has_focus():
			b.draw_arc(c, 26.5, 0.0, TAU, 48, Color(1, 0.93, 0.75, 0.95), 2.0, true))
	return b


func _tip_for(i: int, on: bool) -> void:
	var slot: Button = _slots[i]
	if not on:
		if _tip != null and _tip_slot == i:
			_tip.hush()
			_tip_slot = -1
		create_tween().tween_property(slot, "scale", Vector2.ONE, 0.1)
		return
	_tip_slot = i
	var a: Dictionary = slot.get_meta("ability", {})
	if a.is_empty():
		return
	_tip.set_ability(a, Keybinds.shared().slot_label(i))
	_tip.modulate.a = 0.0
	_tip.show()
	create_tween().tween_property(slot, "scale", Vector2.ONE * 1.14, 0.1)
	UiSound.play("uiTick")
	await get_tree().process_frame
	await get_tree().process_frame
	if _tip_slot != i:
		return
	_tip.reset_size()
	var local := get_global_transform().affine_inverse() * slot.get_global_rect().position
	var sz := _tip.get_combined_minimum_size()
	var x := clampf(local.x + 23.0 - sz.x / 2.0, 20.0, size.x - sz.x - 20.0)
	_tip.pop(Vector2(x, local.y - sz.y - 14.0))


var _tip_slot := -1


## Debug/screenshots: open the tooltip of ability `i` as if hovered.
func debug_tip(i: int) -> void:
	_tip_for.call_deferred(i, true)


func select(id: String, from_user := false) -> void:
	if not GameData.playable(id):
		return
	var changed := id != _cls
	_cls = id
	menu.st.set_value("cls", id)
	for k in _tiles:
		_tiles[k].selected = k == id
	var sid := GameData.normalize_spec(id, str(menu.st.get_value("spec")))
	var spec: Dictionary = GameData.kit(id, sid)
	var tint: Color = Color(str(spec.spec_color)) if spec.has("spec_color") else UiKit.class_color(id)
	_build_spec_cards(id, sid)
	_name.text = str(spec.name).to_upper()
	_name.add_theme_font_size_override("font_size", 72 if _name.text.length() <= 9 else 40)  # long names stay clear of the pedestal
	_name.add_theme_color_override("font_color", tint.lightened(0.35))
	_tagline.text = str(spec.tagline)
	_tagline.position.y = 250 if sid == "" else 250
	for c in _tags.get_children():
		c.queue_free()
	for t in spec.tags:
		var chip := UiKit.heading(str(t).to_upper(), 13, Color("#1a0800"), 700, 2, HORIZONTAL_ALIGNMENT_CENTER)
		chip.add_theme_stylebox_override("normal", UiKit.box(tint.lightened(0.15), Color(0, 0, 0, 0), 4, 0, 6))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tags.add_child(chip)
	for s in STATS:
		(_bars[s[0]] as StatBar).animate_to(float(spec.stats[s[0]]), tint)
		(_bars[s[0]] as StatBar).tooltip_text = HowToContent.stat_tip(spec, s[0])
	for i in 7:
		var slot: Button = _slots[i]
		var a: Dictionary = spec.abilities[i]
		slot.set_meta("ability", a)
		(slot.get_meta("icon") as TextureRect).texture = Icons.tex(str(a.icon))
		var kl: Label = slot.get_meta("key")
		kl.text = Keybinds.shared().slot_label(i)
		kl.add_theme_color_override("font_color", UiKit.GOLD if a.get("ult", false) else UiKit.MUTED)
		slot.queue_redraw()
	(_panel.find_child("RoleLine", true, false) as Label).text = str(GameData.classes[id].specs[sid].role) if sid != "" else str(spec.role)
	_tip.hush()
	_show.show_class(id, Color("#ffb84d"), sid)
	if changed and from_user:
		UiSound.play(CLASS_SOUND.get(id, "uiSelect"))
		_show.play_select(Time.get_ticks_msec() / 1000.0)


## Two big toggle cards under the class (Fuego / Escarcha for the mage); hidden for classes without specializations.
func _build_spec_cards(cls: String, current: String) -> void:
	if _spec_box == null:
		_spec_box = VBoxContainer.new()
		_spec_box.position = Vector2(72, 392)
		_spec_box.add_theme_constant_override("separation", 10)
		add_child(_spec_box)
	for c in _spec_box.get_children():
		c.queue_free()
	_spec_cards.clear()
	var ids := GameData.spec_ids(cls)
	_spec_box.visible = not ids.is_empty()
	if ids.is_empty():
		return
	var cap := UiKit.caption("Especialización", UiKit.MUTED, 12)
	_spec_box.add_child(cap)
	for sid in ids:
		var sp: Dictionary = GameData.classes[cls].specs[sid]
		var col := Color(str(sp.color))
		var card := SpecCard.new(str(sp.icon), str(sp.name), str(sp.role), col)
		card.selected = sid == current
		card.pressed.connect(_pick_spec.bind(sid))
		_spec_box.add_child(card)
		_spec_cards[sid] = card


func _pick_spec(sid: String) -> void:
	if str(menu.st.get_value("cls")) != _cls:
		menu.st.set_value("cls", _cls)
	menu.st.set_value("spec", sid)
	select(_cls)
	UiSound.play("uiSelect")
	_show.play_select(Time.get_ticks_msec() / 1000.0)


func _on_confirm() -> void:
	menu.st.save()
	if menu.nav.mode == "":
		menu.back()
	else:
		menu.next_step()


func menu_enter() -> void:
	_cls = ""
	select(str(menu.st.get_value("cls")))
	var m := menu.nav.mode
	_confirm.text = {"": "GUARDAR CAMPEÓN", "steam_browse": "BUSCAR SALAS", "join": "ENTRAR", "host": "CREAR PARTIDA", "steam_host": "CREAR SALA", "practice": "JUGAR"}.get(m, "CONFIRMAR")


func first_focus() -> Control:
	return _tiles.get(_cls)


func hints() -> Array:
	return [["Flechas", "Navegar"], ["Arrastrar", "Girar"], ["Enter", "Elegir"], ["Esc", "Volver"]]
