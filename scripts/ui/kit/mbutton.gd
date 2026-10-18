class_name MButton
extends Button
## The one button of the front end. Variants: primary (molten, angular), accent (gold), steam,
## secondary (glass outline), ghost (text only), seg (segmented option).
## Hover scales + glows, press squashes, focus draws an outline (keyboard / gamepad), all with sounds.

var variant := "secondary"
var icon_id := ""
var glow := 0.0        # 0..1 hover amount, animated
var shine := -1.0      # sweep position 0..1 (-1 = idle)
var silent := false

var _bg: Control
var _tw: Tween


func _init(label := "", variant_ := "secondary", icon_ := "") -> void:
	text = label
	variant = variant_
	icon_id = icon_
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover_pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var big := variant in ["primary", "accent", "steam"]
	add_theme_font_override("font", UiKit.display(700 if big else 600, 2 if big else 1))
	add_theme_font_size_override("font_size", 24 if variant == "primary" else (20 if big else (16 if variant == "seg" else 18)))
	add_theme_color_override("font_color", Color("#2a0e02") if variant in ["primary", "accent"] else UiKit.INK)
	add_theme_color_override("font_hover_color", Color("#1a0800") if variant in ["primary", "accent"] else Color.WHITE)
	add_theme_color_override("font_pressed_color", Color("#1a0800") if variant in ["primary", "accent"] else Color.WHITE)
	add_theme_color_override("font_hover_pressed_color", Color("#1a0800") if variant in ["primary", "accent"] else Color.WHITE)
	add_theme_color_override("font_focus_color", Color("#1a0800") if variant in ["primary", "accent"] else Color.WHITE)
	custom_minimum_size = Vector2(0, {"primary": 58, "accent": 46, "steam": 46, "seg": 36, "ghost": 36}.get(variant, 44))
	if variant == "seg":
		toggle_mode = true


func _ready() -> void:
	_bg = Control.new()
	_bg.show_behind_parent = true
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.draw.connect(_draw_bg)
	add_child(_bg)
	if icon_id != "":
		icon = Icons.tex(icon_id)
		expand_icon = true
		icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		alignment = HORIZONTAL_ALIGNMENT_CENTER
		var px := 30 if variant == "primary" else 22
		add_theme_constant_override("icon_max_width", px)
		add_theme_constant_override("h_separation", 12)
		var dark := variant in ["primary", "accent"]
		for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
			add_theme_color_override(k, Color("#2a0e02") if dark else UiKit.INK)
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0; _bg.queue_redraw())
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	focus_entered.connect(func(): _hover(true); _bg.queue_redraw())
	focus_exited.connect(func(): _hover(false); _bg.queue_redraw())
	button_down.connect(func(): _scale_to(0.97, 0.06))
	button_up.connect(func(): _scale_to(1.04 if (is_hovered() or has_focus()) else 1.0, 0.12))
	pressed.connect(func(): if not silent: UiSound.play("uiConfirm" if variant == "primary" else ("uiSelect" if variant == "seg" else "uiClick")))
	toggled.connect(func(_on): refresh())
	refresh()


## Re-applies state-dependent colours (segmented option on/off) and redraws.
func refresh() -> void:
	if variant == "seg":
		var c := Color("#1a0800") if button_pressed else UiKit.INK
		for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			add_theme_color_override(k, c if (button_pressed or k == "font_color") else Color.WHITE)
	if _bg != null:
		_bg.queue_redraw()


func _hover(on: bool) -> void:
	if disabled:
		return
	if on and glow < 0.5 and not silent:
		UiSound.play("uiHover")
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "glow", 1.0 if on else 0.0, 0.16)
	var target := 1.0
	if on and variant != "seg":
		target = 1.035
	_tw.tween_property(self, "scale", Vector2(target, target), 0.16)
	if on and variant in ["primary", "accent", "steam"]:
		shine = 0.0
		_tw.tween_property(self, "shine", 1.0, 0.55).set_ease(Tween.EASE_IN_OUT)
		_tw.chain().tween_callback(func(): shine = -1.0; _bg.queue_redraw())
	_tw.tween_method(func(_v): _bg.queue_redraw(), 0.0, 1.0, 0.6)


func _scale_to(s: float, t: float) -> void:
	create_tween().tween_property(self, "scale", Vector2(s, s), t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _shape(r: Rect2, cut: float) -> PackedVector2Array:
	# Angular "cut corner" outline (top-left and bottom-right clipped).
	return PackedVector2Array([
		r.position + Vector2(cut, 0), r.position + Vector2(r.size.x, 0), r.position + Vector2(r.size.x, r.size.y - cut),
		r.position + Vector2(r.size.x - cut, r.size.y), r.position + Vector2(0, r.size.y), r.position + Vector2(0, cut)])


func _draw_bg() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var dis := disabled
	match variant:
		"primary", "accent", "steam":
			var base: Color = {"primary": UiKit.LAVA, "accent": UiKit.GOLD, "steam": Color("#66c0f4")}[variant]
			if dis:
				base = Color(0.3, 0.25, 0.22)
			var cut := minf(14.0, r.size.y * 0.3)
			var poly := _shape(r, cut)
			if glow > 0.01:  # outer halo
				for i in 3:
					var g := _shape(r.grow(3.0 + i * 3.0), cut + i * 2.0)
					_bg.draw_colored_polygon(g, Color(base.r, base.g, base.b, 0.10 * glow / (i + 1)))
			var top := base.lightened(0.28 + 0.12 * glow)
			var bot := base.darkened(0.18)
			var cols := PackedColorArray([top, top, bot, bot, bot, top])
			_bg.draw_polygon(poly, cols)
			if shine >= 0.0:  # diagonal sweep clipped to the rect
				var cx := lerpf(-r.size.y, r.size.x + r.size.y, shine)
				var w := r.size.y * 0.9
				var pts := PackedVector2Array([Vector2(cx, 0), Vector2(cx + w, 0), Vector2(cx + w - r.size.y * 0.6, r.size.y), Vector2(cx - r.size.y * 0.6, r.size.y)])
				pts = Geometry2D.intersect_polygons(pts, poly)[0] if not Geometry2D.intersect_polygons(pts, poly).is_empty() else PackedVector2Array()
				if pts.size() >= 3:
					_bg.draw_colored_polygon(pts, Color(1, 1, 1, 0.38))
			var edge := Color(1, 0.95, 0.8, 0.9) if not dis else Color(1, 1, 1, 0.15)
			_bg.draw_polyline(poly + PackedVector2Array([poly[0]]), edge, 1.5, true)
		"ghost":
			if glow > 0.01:
				_bg.draw_rect(r, Color(1, 0.6, 0.3, 0.10 * glow))
			_bg.draw_rect(Rect2(Vector2(0, r.size.y - 2), Vector2(r.size.x * glow, 2)), UiKit.LAVA)
		"seg":
			var on := button_pressed
			var fill := Color(1, 0.48, 0.1, 0.92) if on else Color(1, 1, 1, 0.05 + 0.07 * glow)
			var sb := UiKit.box(fill, Color(1, 0.8, 0.5, 0.9) if on else Color(1, 1, 1, 0.12 + 0.2 * glow), 6, 1, 0)
			_bg.draw_style_box(sb, r)
		_:
			var fill := Color(1, 1, 1, 0.05 + 0.08 * glow)
			var border := Color(1.0, 0.62, 0.3, 0.30 + 0.55 * glow)
			if dis:
				fill = Color(1, 1, 1, 0.03)
				border = Color(1, 1, 1, 0.08)
			_bg.draw_style_box(UiKit.box(fill, border, 6, 1, 0), r)
	if has_focus():
		var f := UiKit.box(Color(0, 0, 0, 0), Color(1, 0.93, 0.75, 0.95), 8, 2, 0)
		f.draw_center = false
		_bg.draw_style_box(f, r.grow(4))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENTER_TREE:
		if _bg != null:
			_bg.queue_redraw()
	if what == NOTIFICATION_THEME_CHANGED and _bg != null:
		_bg.queue_redraw()
