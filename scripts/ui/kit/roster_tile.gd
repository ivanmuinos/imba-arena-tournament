class_name RosterTile
extends Button
## Portrait tile of a champion in the roster row: portrait, name, class-colour bar; lifts when hot/selected.

var cls := ""
var hot := 0.0
var selected := false:
	set(v):
		selected = v
		_refresh()

var _style: StyleBoxFlat
var _tw: Tween
var _name: Label
var _art: TextureRect
var _tint: Color


func _init(cls_ := "") -> void:
	cls = cls_
	_tint = UiKit.class_color(cls)
	focus_mode = Control.FOCUS_ALL
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(100, 112)
	for s in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	var panel := UiKit.glass(UiKit.LINE, 10, 0, 3.0, 0.5)
	panel.show_behind_parent = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.clip_contents = true
	_style = panel.get_theme_stylebox("panel") as StyleBoxFlat
	add_child(panel)
	_art = TextureRect.new()
	_art.texture = Portraits.bust(cls)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	_art.offset_bottom = -26
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	var title := str(GameData.classes[cls].name).to_upper()
	_name = UiKit.heading(title, 13 if title.length() <= 10 else 10, UiKit.INK, 700, 1, HORIZONTAL_ALIGNMENT_CENTER)  # long names fit narrow tiles
	_name.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_name.offset_top = -26
	_name.offset_bottom = -4
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	var bar := ColorRect.new()
	bar.color = _tint
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -4
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)


func _ready() -> void:
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	focus_entered.connect(_hover.bind(true))
	focus_exited.connect(_hover.bind(false))
	_refresh()


func _hover(on: bool) -> void:
	if on and hot < 0.5:
		UiSound.play("uiHover")
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "hot", 1.0 if on else 0.0, 0.14)
	_tw.tween_property(self, "scale", Vector2.ONE * (1.07 if on else 1.0), 0.14)
	_tw.tween_method(func(_v): _refresh(), 0.0, 1.0, 0.16)


func _refresh() -> void:
	if _style == null:
		return
	var k := maxf(hot, 1.0 if selected else 0.0)
	_style.border_color = UiKit.LINE.lerp(_tint.lightened(0.2), k)
	_style.set_border_width_all(int(roundf(lerpf(1.0, 3.0, k))))
	_art.modulate = Color(1, 1, 1, 0.62 + 0.38 * k)
	_name.add_theme_color_override("font_color", UiKit.INK if k > 0.4 else UiKit.MUTED)
	queue_redraw()


func _draw() -> void:
	if has_focus():
		var f := UiKit.box(Color(0, 0, 0, 0), Color(1, 0.93, 0.75, 0.95), 12, 2, 0)
		f.draw_center = false
		draw_style_box(f, Rect2(Vector2.ZERO, size).grow(4))
	if selected:
		draw_style_box(UiKit.box(Color(_tint.r, _tint.g, _tint.b, 0.12), Color(0, 0, 0, 0), 14, 0, 0), Rect2(Vector2.ZERO, size).grow(5))
