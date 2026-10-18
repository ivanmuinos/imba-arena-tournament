class_name SteamBrowser
extends Control
## Overlay with the Steam lobbies of this game (same version): pick one to join.

signal join_entry(entry: Dictionary)
signal refresh_pressed
signal closed

var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiKit.label("Salas de Steam", 28, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_status = UiKit.label("Buscando…", 14, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_status)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	col.add_child(_list)
	var row := HBoxContainer.new()
	var refresh := UiKit.button("Actualizar")
	refresh.pressed.connect(func(): refresh_pressed.emit())
	var close := UiKit.button("Cerrar")
	close.pressed.connect(func(): closed.emit())
	row.add_child(refresh)
	row.add_child(close)
	col.add_child(row)


func show_entries(entries: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	_status.text = "No hay salas de tus amigos o públicas ahora mismo." if entries.is_empty() else "%d sala%s" % [entries.size(), "" if entries.size() == 1 else "s"]
	for e in entries:
		var row := HBoxContainer.new()
		var info := UiKit.label("%s — %dv%d · %s · %d/%d" % [e.name if e.name != "" else "Sala", int(e.mode), int(e.mode), str(e.map), e.members, e.max], 15)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var b := UiKit.button("Unirme", false, UiKit.GOLD)
		b.pressed.connect(func(): join_entry.emit(e))
		row.add_child(b)
		_list.add_child(row)


func set_status(text: String) -> void:
	_status.text = text
