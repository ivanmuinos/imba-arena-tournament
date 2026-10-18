class_name CastBar
extends Control
## Player cast bar (WoW style): spell icon, name, remaining time and a fill in the school colour. Flashes on completion and
## shows a red "Interrumpido" when the cast is cut short.

var _icon: TextureRect
var _name: Label
var _time: Label
var _fill: ColorRect
var _back: Panel
var _frame: Panel
var _msg: Label
var _tw: Tween
var _color := Color("#ffd166")


func _init() -> void:
	custom_minimum_size = Vector2(440, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_back = Panel.new()
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.add_theme_stylebox_override("panel", UiKit.box(Color(0.04, 0.025, 0.02, 0.88), UiKit.LINE_STRONG, 8, 2, 0))
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	_fill = ColorRect.new()
	_fill.position = Vector2(48, 5)
	_fill.size = Vector2(0, 34)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	_icon = Icons.rect("fireball", 38)
	_icon.position = Vector2(5, 3)
	add_child(_icon)
	_name = UiKit.heading("", 20, Color.WHITE, 700, 1)
	UiKit.outlined(_name, 5)
	_name.position = Vector2(58, 7)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	_time = UiKit.heading("", 20, Color.WHITE, 700, 1, HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.outlined(_time, 5)
	_time.position = Vector2(300, 7)
	_time.size = Vector2(130, 28)
	_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time)
	_msg = UiKit.heading("", 24, Color("#ff5a52"), 700, 3, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(_msg, 6)
	_msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.visible = false
	add_child(_msg)


func begin(spec: Dictionary, color: Color) -> void:
	if _tw != null:
		_tw.kill()
	_color = color
	_icon.texture = Icons.tex(str(spec.icon))
	_name.text = str(spec.name)
	_fill.color = Color(color.r, color.g, color.b, 0.85)
	_msg.visible = false
	_name.visible = true
	_time.visible = true
	modulate = Color.WHITE
	visible = true
	set_progress(0.0, float(spec.get("cast", 0)))


func set_progress(ratio: float, total_ms: float) -> void:
	_fill.size.x = 384.0 * clampf(ratio, 0.0, 1.0)
	_time.text = "%.1f s" % (total_ms * (1.0 - ratio) / 1000.0)


func complete() -> void:
	_fill.size.x = 384.0
	_fill.color = Color(1, 1, 1, 0.95)
	_time.text = ""
	_end(0.25)


func interrupted() -> void:
	_fill.size.x = 384.0
	_fill.color = Color(0.9, 0.18, 0.15, 0.85)
	_name.visible = false
	_time.visible = false
	_msg.text = "INTERRUMPIDO"
	_msg.visible = true
	_end(0.7)


func _end(hold: float) -> void:
	if _tw != null:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_interval(hold)
	_tw.tween_property(self, "modulate:a", 0.0, 0.25)
	_tw.tween_callback(func(): visible = false)
