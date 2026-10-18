class_name SpecCard
extends Button
## Compact toggle card for a specialization: icon, name and role line; glowing accent border when selected.

var accent := UiKit.LAVA
var selected := false:
	set(v):
		selected = v
		_apply()

var _style: StyleBoxFlat
var _name: Label


func _init(icon_id := "", title := "", role := "", accent_: Color = UiKit.LAVA) -> void:
	accent = accent_
	focus_mode = Control.FOCUS_ALL
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	custom_minimum_size = Vector2(190, 66)
	var panel := UiKit.glass(UiKit.LINE, 10, 0, 3.0, 0.6)
	panel.show_behind_parent = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style = panel.get_theme_stylebox("panel") as StyleBoxFlat
	add_child(panel)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var ic := Icons.rect(icon_id, 46)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_name = UiKit.heading(title.to_upper(), 24, UiKit.INK, 700, 2)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_name)
	var r := UiKit.label(role, 12, UiKit.MUTED)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(r)


func _ready() -> void:
	mouse_entered.connect(_apply)
	mouse_exited.connect(_apply)
	focus_entered.connect(_apply)
	focus_exited.connect(_apply)
	pressed.connect(func(): UiSound.play("uiSelect"))
	_apply()


func _apply() -> void:
	if _style == null:
		return
	var hot := selected or is_hovered() or has_focus()
	_style.border_color = Color(accent.r, accent.g, accent.b, 1.0) if selected else (UiKit.LINE_STRONG if hot else UiKit.LINE)
	_style.set_border_width_all(3 if selected else 1)
	_style.bg_color = Color(0, 0, 0, 1)
	_name.add_theme_color_override("font_color", accent.lightened(0.45) if selected else UiKit.INK)
	queue_redraw()


func _draw() -> void:
	if selected:
		draw_style_box(UiKit.box(Color(accent.r, accent.g, accent.b, 0.14), Color(0, 0, 0, 0), 14, 0, 0), Rect2(Vector2.ZERO, size).grow(3))
	if has_focus():
		var f := UiKit.box(Color(0, 0, 0, 0), Color(1, 0.93, 0.75, 0.95), 12, 2, 0)
		f.draw_center = false
		draw_style_box(f, Rect2(Vector2.ZERO, size).grow(4))
