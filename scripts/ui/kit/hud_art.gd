class_name HudArt
extends RefCounted
## The match HUD skin, drawn in code: flat dark-steel panels with a thin bronze edge, compact and docked to the screen
## edges (it replaced the painted gargoyle kit, which was large and had wide transparent margins, so it seemed to float).
## Every number is in HUD px (the 1280x720 design); `s` scales a frame.

const STEEL := Color(0.05, 0.055, 0.07, 0.9)
const TRACK := Color(0.0, 0.0, 0.0, 0.78)
const EDGE := Color("#a8854a")
const EDGE_DIM := Color("#5c4a2c")
const EDGE_ENEMY := Color("#a8483c")

## Unit frames: size, the square portrait and the bar tracks (health, then cast).
const ALLY := {"size": Vector2(188, 46), "portrait": Rect2(4, 4, 38, 38), "bars": [Rect2(46, 20, 138, 14), Rect2(46, 36, 138, 6)], "edge": EDGE}
const ENEMY := {"size": Vector2(188, 46), "portrait": Rect2(4, 4, 38, 38), "bars": [Rect2(46, 20, 138, 14), Rect2(46, 36, 138, 6)], "edge": EDGE_ENEMY}
const FOCUS := {"size": Vector2(170, 18), "bars": [Rect2(3, 3, 164, 12)], "edge": EDGE_DIM}

static var _mask: ShaderMaterial = null


## A flat panel: steel fill, 1 px edge, slightly rounded. `flush` names a screen side the panel touches ("top",
## "bottom" or ""): no edge and square corners there, so it reads as part of the screen border.
static func flat(edge := EDGE, pad := 0, flush := "", bg := STEEL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	if flush == "top":
		s.border_width_top = 0
		s.corner_radius_top_left = 0
		s.corner_radius_top_right = 0
	elif flush == "bottom":
		s.border_width_bottom = 0
		s.corner_radius_bottom_left = 0
		s.corner_radius_bottom_right = 0
	else:
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = 3
	return s


## The style of every HUD panel (score, tooltips, alerts, the Esc menu).
static func panel_style(pad := 10) -> StyleBox:
	return flat(EDGE, pad)


## A unit frame built on `spec` at scale `s`: {root, art (the panel), icon (portrait or null), bars (Bar per track)}.
static func unit_frame(spec: Dictionary, s: float) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = spec.size * s
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := Panel.new()
	a.add_theme_stylebox_override("panel", flat(spec.edge))
	a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(a)
	var icon: TextureRect = null
	if spec.has("portrait"):
		var pr: Rect2 = spec.portrait
		icon = TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = pr.position * s
		icon.size = pr.size * s
		root.add_child(icon)
		var ring := Panel.new()  # a thin edge over the portrait
		ring.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0), spec.edge, 2, 1, 0))
		ring.position = icon.position
		ring.size = icon.size
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(ring)
	var bars := []
	for t in spec.bars:
		var track := ColorRect.new()
		track.color = TRACK
		track.position = t.position * s
		track.size = t.size * s
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(track)
		var b := Bar.new(0.0)
		b.bare = true
		b.ratio = 0.0  # an unused track stays empty
		b.position = t.position * s
		b.size = t.size * s
		root.add_child(b)
		bars.append(b)
	return {"root": root, "art": a, "icon": icon, "bars": bars}


static func circle_mask() -> ShaderMaterial:
	if _mask == null:
		_mask = ShaderMaterial.new()
		_mask.shader = load("res://assets/shaders/circle_mask.gdshader")
	return _mask


## Round mask for the square painted ability icons: the picture is shrunk a little so the circle does not cut its
## corners and the subject does not fill the whole button.
static var _icon_mask: ShaderMaterial = null
const ICON_ZOOM := 0.86


static func icon_mask() -> ShaderMaterial:
	if _icon_mask == null:
		_icon_mask = ShaderMaterial.new()
		_icon_mask.shader = load("res://assets/shaders/circle_mask.gdshader")
		_icon_mask.set_shader_parameter("zoom", ICON_ZOOM)
	return _icon_mask
