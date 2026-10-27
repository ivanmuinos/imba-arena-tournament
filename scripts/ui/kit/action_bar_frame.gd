class_name ActionBarFrame
extends PanelContainer
## The ornate frame around the ability bar: dark leather plate with a double gold rim, a warm sheen along the top, rivets on
## the corners, a crest on the top edge and a lava gem on each end cap. Everything is drawn here; no textures.

const GOLD_DARK := Color("#7a5426")
const GOLD_MID := Color("#c8913e")
const GOLD_LIGHT := Color("#ffd98a")
const PLATE_TOP := Color(0.11, 0.07, 0.05, 0.95)
const PLATE_BOTTOM := Color(0.04, 0.025, 0.02, 0.95)
const GEM := Color("#ff6a1a")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := StyleBoxEmpty.new()  # the plate is drawn in _draw; this only spaces the buttons from the rim
	pad.content_margin_left = 14
	pad.content_margin_right = 14
	pad.content_margin_top = 10
	pad.content_margin_bottom = 9
	add_theme_stylebox_override("panel", pad)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# drop shadow, then the plate with a vertical gradient
	draw_style_box(_flat(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0), 0, 12, Color(0, 0, 0, 0.55), 14), r)
	draw_style_box(_flat(PLATE_BOTTOM, GOLD_DARK, 3, 12), r)
	draw_style_box(_flat(PLATE_TOP, Color(0, 0, 0, 0), 0, 10), Rect2(4, 4, size.x - 8, size.y * 0.55))
	# warm sheen on the upper half (kept clear of the rounded corners), bright rim, fine inner line
	var sheen := Rect2(12, 3, size.x - 24, size.y * 0.42)
	draw_polygon(PackedVector2Array([sheen.position, Vector2(sheen.end.x, sheen.position.y), sheen.end, Vector2(sheen.position.x, sheen.end.y)]),
		PackedColorArray([Color(1, 0.75, 0.4, 0.10), Color(1, 0.75, 0.4, 0.10), Color(1, 0.75, 0.4, 0), Color(1, 0.75, 0.4, 0)]))
	draw_style_box(_flat(Color(0, 0, 0, 0), GOLD_MID, 2, 12), r)
	draw_style_box(_flat(Color(0, 0, 0, 0), Color(GOLD_LIGHT, 0.28), 1, 9), r.grow(-5))
	draw_line(Vector2(16, 1.5), Vector2(size.x - 16, 1.5), Color(GOLD_LIGHT, 0.55), 1.0)  # light catching the top edge
	# rivets on the corners
	for p in [Vector2(9, 9), Vector2(size.x - 9, 9), Vector2(9, size.y - 9), Vector2(size.x - 9, size.y - 9)]:
		draw_circle(p, 3.2, GOLD_DARK)
		draw_circle(p, 2.3, GOLD_MID)
		draw_circle(p + Vector2(-0.7, -0.7), 0.9, GOLD_LIGHT)
	# crest on the top edge: a small gold diamond with wings
	var top := Vector2(size.x / 2, 0)
	for side in [-1.0, 1.0]:
		draw_line(top + Vector2(side * 12, 0), top + Vector2(side * 46, 0), GOLD_LIGHT, 2.0)
		draw_line(top + Vector2(side * 46, 0), top + Vector2(side * 54, 3), GOLD_MID, 2.0)
	_diamond(top, 9, GOLD_DARK)
	_diamond(top, 7, GOLD_MID)
	_diamond(top, 3.5, GEM)
	# end caps: a gold lozenge holding a glowing lava gem on each side
	for x in [0.0, size.x]:
		var c := Vector2(x, size.y / 2)
		draw_circle(c, 15, Color(GEM, 0.10))
		_diamond(c, 15, GOLD_DARK, 1.35)
		_diamond(c, 12.5, GOLD_MID, 1.35)
		_diamond(c, 8, Color("#5a1a06"), 1.35)
		_diamond(c, 6, GEM, 1.35)
		_diamond(c + Vector2(-1.5, -2.5), 2, Color("#ffd2a0"), 1.35)


## A diamond centred on `c`, `h` from centre to the side points; `tall` stretches it vertically.
func _diamond(c: Vector2, h: float, col: Color, tall := 1.0) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * tall), c + Vector2(h, 0), c + Vector2(0, h * tall), c + Vector2(-h, 0)]), col)


static func _flat(bg: Color, border: Color, bw: int, radius: int, shadow := Color(0, 0, 0, 0), shadow_size := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.shadow_color = shadow
	s.shadow_size = shadow_size
	s.anti_aliasing = true
	return s
