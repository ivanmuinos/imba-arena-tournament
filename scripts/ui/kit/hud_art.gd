class_name HudArt
extends RefCounted
## The match HUD art (assets/ui/hud, cut from referencias/hud_kit_2.jpeg by tools/build_hud_kit.gd). Every number here
## is in kit px, the same ones the build script uses; `s` scales kit px to HUD px.

## Unit frames: art origin and size, the round portrait (centre, radius) and the bar tracks, top to bottom.
const ALLY := {"tex": "frame_ally", "origin": Vector2(1163, 792), "size": Vector2(798, 246), "circle": [Vector2(1295, 938), 82.0],
	"bars": [Rect2(1412, 884, 338, 36), Rect2(1412, 932, 340, 28), Rect2(1411, 969, 344, 31)]}
const ENEMY := {"tex": "frame_enemy", "origin": Vector2(1891, 17), "size": Vector2(832, 344), "circle": [Vector2(2070, 200), 112.0],
	"bars": [Rect2(2235, 107, 311, 32), Rect2(2241, 150, 306, 33)]}
const FOCUS := {"tex": "bar_focus", "origin": Vector2(2245, 256), "size": Vector2(470, 90), "bars": [Rect2(2329, 298, 362, 30)]}

static var _tex := {}
static var _mask: ShaderMaterial = null
static var _panel: Texture2D = null


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://assets/ui/hud/%s.png" % name)
	return _tex[name]


## A TextureRect that stretches a piece of art over its rect.
static func art(name: String) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return r


## The stone panel with gold corners as a 9-slice, for every HUD panel.
static func panel_style(pad := 10) -> StyleBoxTexture:
	if _panel == null:
		_panel = tex("panel")
	var s := StyleBoxTexture.new()
	s.texture = _panel
	s.set_texture_margin_all(20)
	s.set_content_margin_all(pad)
	return s


## A unit frame built on `spec` at scale `s`: {root, art, icon (round portrait or null), bars (Bar per track)}.
## The root has the art's size; the bars are drawn into the art's empty tracks.
static func unit_frame(spec: Dictionary, s: float) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = spec.size * s
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := art(spec.tex)
	a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(a)
	var icon: TextureRect = null
	if spec.has("circle"):
		var r: float = spec.circle[1] * s
		icon = TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = (spec.circle[0] - spec.origin) * s - Vector2(r, r)
		icon.size = Vector2(r, r) * 2.0
		icon.material = circle_mask()
		root.add_child(icon)
	var bars := []
	for t in spec.bars:
		var b := Bar.new(0.0)
		b.bare = true
		b.ratio = 0.0  # an unused track stays empty
		b.position = (t.position - spec.origin) * s
		b.size = t.size * s
		root.add_child(b)
		bars.append(b)
	return {"root": root, "art": a, "icon": icon, "bars": bars}


static func circle_mask() -> ShaderMaterial:
	if _mask == null:
		_mask = ShaderMaterial.new()
		_mask.shader = load("res://assets/shaders/circle_mask.gdshader")
	return _mask
