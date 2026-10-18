class_name MSplash
extends MenuView
## Title screen over the cinematic 3D flythrough: logo with shine, "press any key".

var _prompt: Label


func _ready() -> void:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.02, 0.008, 0.005, 0.78), Color(0.02, 0.008, 0.005, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var glow := TextureRect.new()
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	glow.position = Vector2(-560, -330)
	glow.size = Vector2(1120, 560)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	var logo := MenuLogo.new(1.0)
	logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	logo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	logo.grow_vertical = Control.GROW_DIRECTION_BOTH
	logo.position.y -= 70
	add_child(logo)
	_prompt = UiKit.heading("PRESIONÁ CUALQUIER TECLA", 22, UiKit.INK, 600, 7, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -190
	_prompt.offset_bottom = -150
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)
	var tw := create_tween().set_loops()
	tw.tween_property(_prompt, "modulate:a", 0.25, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_prompt, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	var ver := UiKit.label("v%s" % str(ProjectSettings.get_setting("application/config/version", "0")), 13, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ver.offset_top = -50
	ver.offset_bottom = -30
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver)


func hints() -> Array:
	return []
