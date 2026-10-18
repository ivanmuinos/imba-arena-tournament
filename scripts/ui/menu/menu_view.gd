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


## Standard header: big title + muted subtitle, top-left under the chrome.
func header(title: String, subtitle := "") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.position = Vector2(72, 92)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UiKit.heading(title.to_upper(), 46, UiKit.INK, 700, 3)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(t)
	var s := UiKit.label(subtitle, 16, UiKit.MUTED)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(s)
	add_child(box)
	return box
