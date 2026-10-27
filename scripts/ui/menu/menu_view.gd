class_name MenuView
extends Control
## Base of every front-end screen (splash, hub, play, setup, join, champions, settings).

var menu: MenuScreen


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Called every time the screen is about to be shown (refresh from settings here).
func menu_enter() -> void:
	pass


## The control that should get keyboard/gamepad focus first.
func first_focus() -> Control:
	return null


## Text for the key-hint bar at the bottom.
func hints() -> Array:
	return [["Enter", "Aceptar"], ["Esc", "Volver"]]


## Section of the client this screen belongs to, shown as a small gold line over the title ("" = none).
func section() -> String:
	return ""


## Standard header: section line, title and muted subtitle, top-left under the top bar.
func header(title: String, subtitle := "") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.position = Vector2(72, 86)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if section() != "":
		var crumb := HBoxContainer.new()
		crumb.add_theme_constant_override("separation", 8)
		crumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar := ColorRect.new()
		bar.color = UiKit.GOLD
		bar.custom_minimum_size = Vector2(18, 2)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crumb.add_child(bar)
		var c := UiKit.caption(section(), UiKit.GOLD, 12)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crumb.add_child(c)
		box.add_child(crumb)
	var t := UiKit.heading(title.to_upper(), 42, UiKit.INK, 700, 3)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(t)
	var s := UiKit.label(subtitle, 16, UiKit.MUTED)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(s)
	add_child(box)
	return box
