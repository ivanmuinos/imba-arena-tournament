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

## As wide as the action bar it sits on, and a little over half as tall as it used to be.
const SIZE := Vector2(308, 26)
const FILL_X := 27.0
const FILL_W := 278.0


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_back = Panel.new()
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.add_theme_stylebox_override("panel", HudArt.flat(HudArt.EDGE))
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	_fill = ColorRect.new()
	_fill.position = Vector2(FILL_X, 3)
	_fill.size = Vector2(0, 20)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	_icon = Icons.rect("fireball", 20)
	_icon.position = Vector2(3, 3)
	add_child(_icon)
	_name = UiKit.heading("", 13, Color.WHITE, 700, 1)
	UiKit.outlined(_name, 4)
	_name.position = Vector2(FILL_X + 5, 4)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	_time = UiKit.heading("", 13, Color.WHITE, 700, 1, HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.outlined(_time, 4)
	_time.position = Vector2(SIZE.x - 86, 4)
	_time.size = Vector2(80, 18)
	_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time)
	_msg = UiKit.heading("", 15, Color("#ff5a52"), 700, 2, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(_msg, 4)
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
	_fill.size.x = FILL_W * clampf(ratio, 0.0, 1.0)
	_time.text = "%.1f s" % (total_ms * (1.0 - ratio) / 1000.0)


func complete() -> void:
	_fill.size.x = FILL_W
	_fill.color = Color(1, 1, 1, 0.95)
	_time.text = ""
	_end(0.25)


func interrupted() -> void:
	_fill.size.x = FILL_W
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
