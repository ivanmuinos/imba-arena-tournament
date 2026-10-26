class_name PracticePanel
extends PanelContainer
## Side panel of the practice arena: class/spec switch, DPS meter with the per-ability table and the practice controls.
## It only displays what the server's PracticeMeter sends (you.meter) and emits signals for the buttons.

signal reset_pressed
signal nocd_toggled(on: bool)
signal ult_pressed
signal class_changed(cls: String, spec: String)
signal menu_pressed

const ROWS := 8
const WIDTH := 330.0

var cls := "mage"
var spec := ""

var _cls_pick: OptionButton
var _spec_pick: OptionButton
var _total: Label
var _dps10: Label
var _dps: Label
var _heal: Label
var _grid: GridContainer
var _cells: Array = []
var _body: VBoxContainer
var _fold: MButton
var _nocd: CheckButton
var _quiet := false
var _nocd_local_ms := -10000


static func ability_name(id: String, p_cls: String, p_spec := "") -> String:
	for a in GameData.abilities(p_cls, p_spec):
		if a.id == id:
			return str(a.name)
	return {"burn": "Quemadura", "auto": "Ataque básico"}.get(id, id.capitalize())


## Table rows as display strings (pure, tested): [name, damage, "12%", casts, crits].
static func row_texts(rows: Array, p_cls: String, p_spec := "") -> Array:
	var out: Array = []
	for r in rows:
		out.append([ability_name(str(r.id), p_cls, p_spec), _n(int(r.dmg)), "%d%%" % roundi(float(r.pct)), str(int(r.casts)), str(int(r.crits))])
	return out


## 12345 -> "12 345" (thin grouping, no locale surprises).
static func _n(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += " "
		out += s[i]
	return ("-" if v < 0 else "") + out


func setup(p_cls: String, p_spec: String) -> PracticePanel:
	cls = p_cls
	spec = p_spec
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiKit.box(Color(0.045, 0.03, 0.026, 0.9), UiKit.LINE_STRONG, 12, 1, 12))
	custom_minimum_size = Vector2(WIDTH, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var t := UiKit.heading("ARENA DE PRÁCTICA", 18, UiKit.GOLD, 700, 2)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_fold = MButton.new("Ocultar", "ghost")
	_fold.custom_minimum_size = Vector2(76, 28)
	_fold.add_theme_font_size_override("font_size", 13)
	_fold.pressed.connect(func():
		_body.visible = not _body.visible
		_fold.text = "Ocultar" if _body.visible else "Mostrar"
		reset_size())
	head.add_child(_fold)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 7)
	col.add_child(_body)
	# class / spec switch
	_body.add_child(UiKit.caption("Campeón", UiKit.MUTED, 11))
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 6)
	_body.add_child(pick)
	_cls_pick = OptionButton.new()
	_cls_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cls_pick.focus_mode = Control.FOCUS_NONE
	_cls_pick.add_theme_font_size_override("font_size", 15)
	var ids: Array = GameData.playable_ids()
	for i in ids.size():
		_cls_pick.add_item(str(GameData.classes[ids[i]].name), i)
		_cls_pick.set_item_metadata(i, ids[i])
		if ids[i] == cls:
			_cls_pick.select(i)
	_cls_pick.item_selected.connect(func(i: int): _on_class(str(_cls_pick.get_item_metadata(i))))
	pick.add_child(_cls_pick)
	_spec_pick = OptionButton.new()
	_spec_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spec_pick.focus_mode = Control.FOCUS_NONE
	_spec_pick.add_theme_font_size_override("font_size", 15)
	_spec_pick.item_selected.connect(func(i: int): _emit_class(str(_spec_pick.get_item_metadata(i))))
	pick.add_child(_spec_pick)
	_fill_specs()
	# totals
	var sums := GridContainer.new()
	sums.columns = 2
	sums.add_theme_constant_override("h_separation", 12)
	sums.add_theme_constant_override("v_separation", 2)
	_body.add_child(sums)
	_total = _stat(sums, "Daño total")
	_dps10 = _stat(sums, "DPS (últimos 10 s)")
	_dps = _stat(sums, "DPS (desde el primer golpe)")
	_heal = _stat(sums, "Curación hecha")
	# per-ability table
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 1)
	_body.add_child(_grid)
	for i in 5:
		var h := UiKit.caption(["Habilidad", "Daño", "%", "Lanz.", "Crít."][i], UiKit.MUTED, 10)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		if i == 0:
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(h)
	for r in ROWS:
		var row: Array = []
		for i in 5:
			var l := UiKit.label("", 13, UiKit.INK if i < 2 else UiKit.MUTED)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			l.clip_text = i == 0
			l.custom_minimum_size.x = 112.0 if i == 0 else 0.0
			_grid.add_child(l)
			row.append(l)
		_cells.append(row)
	# controls
	var reset := MButton.new("Reiniciar", "secondary")
	reset.tooltip_text = "Pone en cero el medidor, cura a los muñecos y deja tus habilidades listas"
	reset.pressed.connect(func(): reset_pressed.emit())
	_body.add_child(reset)
	_nocd = CheckButton.new()
	_nocd.text = "Sin cooldowns"
	_nocd.add_theme_font_size_override("font_size", 14)
	_nocd.focus_mode = Control.FOCUS_NONE
	_nocd.toggled.connect(func(on: bool):
		if not _quiet:
			_nocd_local_ms = Time.get_ticks_msec()
			nocd_toggled.emit(on))
	_body.add_child(_nocd)
	var ult := MButton.new("Definitiva lista", "secondary")
	ult.pressed.connect(func(): ult_pressed.emit())
	_body.add_child(ult)
	var back := MButton.new("Volver al menú", "ghost")
	back.pressed.connect(func(): menu_pressed.emit())
	_body.add_child(back)
	for b in [reset, ult, back]:
		b.custom_minimum_size = Vector2(0, 38)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
	return self


func _stat(parent: Control, caption: String) -> Label:
	var c := UiKit.label(caption, 13, UiKit.MUTED)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	var v := UiKit.heading("0", 18, UiKit.INK, 700, 1, HORIZONTAL_ALIGNMENT_RIGHT)
	parent.add_child(v)
	return v


func _fill_specs() -> void:
	_spec_pick.clear()
	var specs: Array = GameData.spec_ids(cls)
	_spec_pick.visible = not specs.is_empty()
	for i in specs.size():
		_spec_pick.add_item(str(GameData.classes[cls].specs[specs[i]].name), i)
		_spec_pick.set_item_metadata(i, specs[i])
		if specs[i] == spec:
			_spec_pick.select(i)


func _on_class(new_cls: String) -> void:
	if new_cls == cls:
		return
	cls = new_cls
	spec = GameData.normalize_spec(cls, str(SettingsStore.shared().values.specs.get(cls, "")))
	_fill_specs()
	_emit_class(spec)


func _emit_class(new_spec: String) -> void:
	spec = new_spec
	class_changed.emit(cls, spec)


## Refreshes the numbers from the server's meter snapshot ({} = nothing yet).
func update_meter(you: Dictionary) -> void:
	var m: Dictionary = you.get("meter", {})
	_total.text = _n(int(m.get("total", 0)))
	_dps10.text = "%.1f" % float(m.get("dps10", 0.0))
	_dps.text = "%.1f" % float(m.get("dps", 0.0))
	_heal.text = _n(int(m.get("heal", 0)))
	var texts := row_texts(m.get("rows", []), cls, spec)
	for r in ROWS:
		for i in 5:
			(_cells[r][i] as Label).text = texts[r][i] if r < texts.size() else ""
	var want := bool(you.get("nocd", false))
	# a snapshot sent before the server saw the click must not undo it: trust the server only after the round trip
	if _nocd.button_pressed != want and Time.get_ticks_msec() - _nocd_local_ms > 800:
		_quiet = true
		_nocd.button_pressed = want
		_quiet = false
