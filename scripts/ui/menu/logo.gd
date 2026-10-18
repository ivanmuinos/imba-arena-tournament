class_name MenuLogo
extends VBoxContainer
## IMBA ARENA TOURNAMENT wordmark: molten gradient text with a sweeping shine and a breathing glow.

var _imba: Label
var _glow_tw: Tween


func _init(scale_ := 1.0) -> void:
	add_theme_constant_override("separation", int(-10 * scale_))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_imba = UiKit.heading("IMBA", int(150 * scale_), Color.WHITE, 700, int(10 * scale_), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(_imba, int(16 * scale_), Color("#3a1204"))
	_imba.add_theme_color_override("font_shadow_color", Color(1.0, 0.4, 0.05, 0.5))
	_imba.add_theme_constant_override("shadow_offset_y", int(4 * scale_))
	_imba.add_theme_constant_override("shadow_outline_size", int(26 * scale_))
	if UiKit.shaders_ok():
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/logo.gdshader")
		m.set_shader_parameter("area", Vector2(420.0, 190.0) * scale_)
		_imba.material = m
	_imba.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_imba)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(16 * scale_))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(_bar(scale_))
	var sub := UiKit.heading("ARENA TOURNAMENT", int(38 * scale_), Color("#fff1dc"), 600, int(9 * scale_))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sub)
	row.add_child(_bar(scale_))


func _bar(scale_: float) -> Control:
	var c := ColorRect.new()
	c.color = Color(1.0, 0.5, 0.15, 0.85)
	c.custom_minimum_size = Vector2(70 * scale_, 2)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _ready() -> void:
	_glow_tw = create_tween().set_loops()
	_glow_tw.tween_method(_set_glow, 0.35, 0.8, 1.8).set_trans(Tween.TRANS_SINE)
	_glow_tw.tween_method(_set_glow, 0.8, 0.35, 1.8).set_trans(Tween.TRANS_SINE)


func _set_glow(a: float) -> void:
	_imba.add_theme_color_override("font_shadow_color", Color(1.0, 0.4, 0.05, a))
