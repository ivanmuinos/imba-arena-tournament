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


## Section tabs (settings, how to play): text tabs with a gold underline on the active one, like the client's top bar,
## over a hairline. Options keep the pill look.
var tabs := false


func as_tabs() -> Segmented:
	tabs = true
	add_theme_constant_override("separation", 4)
	for b in _buttons.values():
		var mb: MButton = b
		mb.variant = "tab"
		mb.text = mb.text.to_upper()
		mb.add_theme_font_override("font", UiKit.display(700, 2))
		mb.add_theme_font_size_override("font_size", 16)
		mb.custom_minimum_size = Vector2(36.0 + mb.text.length() * 11.0, 42)  # the tab variant draws no box: room for the text
		for k in ["font_color", "font_focus_color"]:
			mb.add_theme_color_override(k, UiKit.MUTED)
		for k in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			mb.add_theme_color_override(k, UiKit.INK)
	queue_redraw()
	return self


func _draw() -> void:
	if tabs:
		draw_line(Vector2(0, size.y - 0.5), Vector2(size.x, size.y - 0.5), UiKit.LINE, 1.0)


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
