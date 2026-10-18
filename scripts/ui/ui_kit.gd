class_name UiKit
extends RefCounted
## Design tokens + shared builders for menus and HUD: dark glass, one molten accent, team red/blue.
## Fonts: Rajdhani (display) and Inter (body), both OFL, bundled in assets/fonts.

const INK := Color("#f6eee6")
const MUTED := Color("#a99c90")
const DIM := Color("#6f655d")
const GOLD := Color("#ffc15a")
const LAVA := Color("#ff7a1a")
const EMBER := Color("#ff4d12")
const RED := Color("#ff5a52")
const BLUE := Color("#4aa8ff")
const GREEN := Color("#6dde8a")
const PANEL := Color(0.055, 0.035, 0.03, 0.82)
const LINE := Color(1.0, 0.62, 0.3, 0.30)
const LINE_STRONG := Color(1.0, 0.72, 0.38, 0.85)
const CLASS_COLORS := {"warlock": Color("#c45be0"), "mage": Color("#9a74ff"), "hunter": Color("#74cf62"), "warrior": Color("#c4ccd8"), "priest": Color("#ffe48c"), "rogue": Color("#5fd4ff")}

static var _theme: Theme = null
static var _fonts := {}
static var _glass_shader: Shader = null
static var _knob: ImageTexture = null


static func clear_cache() -> void:
	_theme = null
	_fonts.clear()
	_glass_shader = null
	_knob = null


# ---------------------------------------------------------------- fonts

## Display face (Rajdhani), weight 500/600/700. `spacing` adds letter spacing in px.
static func display(weight := 700, spacing := 0) -> Font:
	var key := "d%d_%d" % [weight, spacing]
	if not _fonts.has(key):
		var name: String = {500: "Medium", 600: "SemiBold", 700: "Bold"}.get(weight, "Bold")
		var f := load("res://assets/fonts/Rajdhani-%s.ttf" % name) as Font
		if spacing != 0:
			var v := FontVariation.new()
			v.base_font = f
			v.spacing_glyph = spacing
			f = v
		_fonts[key] = f
	return _fonts[key]


## Body face (Inter variable) at a given weight (400-800).
static func body(weight := 500) -> Font:
	var key := "b%d" % weight
	if not _fonts.has(key):
		var v := FontVariation.new()
		v.base_font = load("res://assets/fonts/Inter-Variable.ttf") as Font
		var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
		v.variation_opentype = {tag: weight}
		_fonts[key] = v
	return _fonts[key]


static func title_font() -> Font:
	return display(700, 2)


# ---------------------------------------------------------------- theme

static func box(bg: Color, border: Color = LINE, radius := 10, border_w := 2, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body(500)
	t.default_font_size = 16
	t.set_color("font_color", "Label", INK)
	t.set_font("font", "Button", display(600, 1))
	t.set_font_size("font_size", "Button", 18)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK if c == "font_color" else Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var bg := Color(0.14, 0.09, 0.07, 0.9)
		var border := LINE
		if state == "hover":
			bg = Color(0.24, 0.13, 0.08, 0.95)
			border = LINE_STRONG
		elif state in ["pressed", "hover_pressed"]:
			bg = Color(0.42, 0.2, 0.08, 1.0)
			border = GOLD
		elif state == "disabled":
			bg = Color(0.1, 0.07, 0.06, 0.7)
			border = Color(1, 1, 1, 0.1)
		t.set_stylebox(state, "Button", box(bg, border, 6, 1, 10))
	var focus := box(Color(0, 0, 0, 0), Color(1, 0.9, 0.7, 0.95), 7, 2, 10)
	focus.draw_center = false
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	t.set_stylebox("focus", "Button", focus)
	var le := box(Color(0.02, 0.012, 0.01, 0.7), LINE, 6, 1, 10)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(Color(0.03, 0.018, 0.012, 0.8), GOLD, 6, 2, 10))
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", DIM)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(1, 0.5, 0.15, 0.4))
	t.set_stylebox("panel", "PanelContainer", box(PANEL))
	t.set_stylebox("panel", "Panel", box(PANEL))
	# Slider: thin track, molten fill, round knob
	var track := box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 3, 0, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(LAVA, Color(0, 0, 0, 0), 3, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, Color(0, 0, 0, 0), 3, 0, 0))
	t.set_icon("grabber", "HSlider", knob(false))
	t.set_icon("grabber_highlight", "HSlider", knob(true))
	t.set_icon("grabber_disabled", "HSlider", knob(false))
	t.set_constant("center_grabber", "HSlider", 0)
	t.set_constant("grabber_offset", "HSlider", 0)
	# Scrollbars: slim
	t.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 0.6, 0.3, 0.4), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 0.7, 0.4, 0.7), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(GOLD, Color(0, 0, 0, 0), 4, 0, 0))
	_theme = t
	return t


static func knob(hot: bool) -> ImageTexture:
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	var c := Vector2(19.5, 19.5)
	for y in 40:
		for x in 40:
			var d := Vector2(x, y).distance_to(c)
			var col := Color(0, 0, 0, 0)
			if d < 14.0:
				col = Color("#fff3e0") if hot else Color("#ffd9a8")
				if d > 11.5:
					col = Color("#ff7a1a")
			elif d < 18.5:
				col = Color(1, 0.55, 0.15, clampf((18.5 - d) / 4.5, 0.0, 1.0) * (0.45 if hot else 0.2))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- glass

## Under the headless dummy renderer shader materials are skipped (visuals do not exist there and its material storage
## logs errors when they are freed at exit).
static func shaders_ok() -> bool:
	return DisplayServer.get_name() != "headless"


static func glass_material(blur := 3.2, tint_amount := 0.62, tint: Color = Color(0.035, 0.022, 0.02)) -> ShaderMaterial:
	if not shaders_ok():
		return null
	if _glass_shader == null:
		_glass_shader = load("res://assets/shaders/glass.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _glass_shader
	m.set_shader_parameter("blur_lod", blur)
	m.set_shader_parameter("tint_amount", tint_amount)
	m.set_shader_parameter("tint", tint)
	return m


## StyleBox for glass panels: black fill (the shader replaces it) and a thin luminous border.
static func glass_box(border: Color = LINE, radius := 12, pad := 18, border_w := 1) -> StyleBoxFlat:
	return box(Color(0, 0, 0, 1), border, radius, border_w, pad)


## A PanelContainer with blurred-glass background.
static func glass(border: Color = LINE, radius := 12, pad := 18, blur := 3.2, tint_amount := 0.62) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", glass_box(border, radius, pad))
	p.material = glass_material(blur, tint_amount)
	return p


# ---------------------------------------------------------------- small builders

static func label(text: String, size := 16, color: Color = INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


## Display-face label (Rajdhani): headings, numbers, buttons.
static func heading(text: String, size := 28, color: Color = INK, weight := 700, spacing := 1, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, align)
	l.add_theme_font_override("font", display(weight, spacing))
	return l


## Small spaced-out caps caption.
static func caption(text: String, color: Color = MUTED, size := 12) -> Label:
	return heading(text.to_upper(), size, color, 600, 2)


static func outlined(l: Label, outline := 6, color: Color = Color(0, 0, 0, 0.85)) -> Label:
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", color)
	return l


static func button(text: String, big := false, accent: Color = Color.TRANSPARENT) -> MButton:
	var variant := "secondary"
	if accent.a > 0.0:
		variant = "primary" if accent == LAVA else ("steam" if accent == Color("#66c0f4") else "accent")
	var b := MButton.new(text, variant)
	if big:
		b.custom_minimum_size = Vector2(0, 48)
	return b


static func spacer(h := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func panel() -> PanelContainer:
	return PanelContainer.new()


## Dark vignette over the 3D background so UI stays legible (the scene still shows through).
static func backdrop(strength := 1.0) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.06, 0.025, 0.015, 0.0), Color(0.04, 0.02, 0.015, 0.45 * strength), Color(0.02, 0.01, 0.008, 0.9 * strength)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.95)
	gt.width = 256
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Dark band from the left edge (keeps text over the 3D scene readable).
static func side_shade(alpha := 0.7) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.01, 0.008, alpha), Color(0.02, 0.01, 0.008, alpha * 0.35), Color(0.02, 0.01, 0.008, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	gt.width = 256
	gt.height = 8
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func class_color(cls: String) -> Color:
	return CLASS_COLORS.get(cls, GOLD)
