class_name Segmented
extends HBoxContainer
## A row of options where exactly one is selected (glass pills, accent fill on the active one).

signal changed(value: String)

var value := ""
var _buttons := {}


## options: [[value, label], ...]
func setup(options: Array, initial: String) -> Segmented:
	add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for o in options:
		var b := MButton.new(o[1], "seg")
		b.button_group = group
		b.add_theme_constant_override("h_separation", 6)
		b.custom_minimum_size = Vector2(maxf(64.0, 28.0 + str(o[1]).length() * 9.0), 38)
		var v: String = o[0]
		b.pressed.connect(func(): _pick(v))
		add_child(b)
		_buttons[v] = b
	select(initial, false)
	return self


func _pick(v: String) -> void:
	value = v
	changed.emit(v)


func select(v: String, emit := true) -> void:
	value = v
	for k in _buttons:
		_buttons[k].set_pressed_no_signal(k == v)
		_buttons[k].refresh()
	if emit:
		changed.emit(v)


func set_locked(locked: bool) -> void:
	for b in _buttons.values():
		b.disabled = locked
