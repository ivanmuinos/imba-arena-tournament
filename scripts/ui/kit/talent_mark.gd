class_name TalentMark
extends Control
## Overlay for an ability icon changed by a talent: a gold ring and a small seal with what changed
## (sword = damage, clock = cooldown, bolt = cast time, target = range, flame = burn/dot, snowflake = slow/shatter,
## star = crit, cross = healing, arrows = swapped ability, hop = bounce, three dots = every Nth). Put it full-rect over the icon; `kind` "" hides it.

const GOLD := Color("#ffc15a")
const INK := Color("#2a1606")

## One of: dmg, heal, cd, cast, range, burn, frost, crit, swap, bounce, nth ("" = no talent).
var kind := "":
	set(v):
		kind = v
		visible = v != ""
		queue_redraw()
## Round icons (menus) get a ring; square ones (the action bar) a frame.
var round := true
## Seal size relative to the icon.
var seal := 0.42


func _init(p_round := true) -> void:
	round = p_round
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## The mark of an ability (Talents.apply stores it as ability.talent.kind).
static func kind_of(a: Dictionary) -> String:
	return str(a.get("talent", {}).get("kind", ""))


func _draw() -> void:
	if kind == "":
		return
	var s := minf(size.x, size.y)
	if round:
		draw_arc(size / 2.0, s / 2.0 + 1.0, 0.0, TAU, 48, GOLD, 2.5, true)
	else:
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), GOLD, false, 2.0)
	var r := s * seal / 2.0
	var c := Vector2(size.x - r * 0.85, size.y - r * 0.85)
	draw_circle(c, r + 1.5, Color(0, 0, 0, 0.6))
	draw_circle(c, r, GOLD)
	_glyph(c, r * 0.62)


func _glyph(c: Vector2, g: float) -> void:
	var w := maxf(1.5, g * 0.28)
	match kind:
		"dmg":  # sword
			draw_line(c + Vector2(-g, g), c + Vector2(g, -g), INK, w, true)
			draw_line(c + Vector2(-g * 0.75, g * 0.05), c + Vector2(-g * 0.05, g * 0.75), INK, w, true)
		"heal":
			draw_line(c + Vector2(0, -g), c + Vector2(0, g), INK, w * 1.3, true)
			draw_line(c + Vector2(-g, 0), c + Vector2(g, 0), INK, w * 1.3, true)
		"cd":  # clock
			draw_arc(c, g, 0.0, TAU, 24, INK, w * 0.8, true)
			draw_line(c, c + Vector2(0, -g * 0.7), INK, w * 0.8, true)
			draw_line(c, c + Vector2(g * 0.55, 0), INK, w * 0.8, true)
		"cast":  # lightning bolt
			draw_colored_polygon(PackedVector2Array([c + Vector2(g * 0.3, -g), c + Vector2(-g * 0.6, g * 0.15), c + Vector2(-g * 0.05, g * 0.15),
				c + Vector2(-g * 0.3, g), c + Vector2(g * 0.6, -g * 0.15), c + Vector2(g * 0.05, -g * 0.15)]), INK)
		"range":  # target
			draw_arc(c, g, 0.0, TAU, 24, INK, w * 0.8, true)
			draw_circle(c, g * 0.3, INK)
		"burn":  # flame
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -g), c + Vector2(g * 0.55, -g * 0.1), c + Vector2(g * 0.65, g * 0.45),
				c + Vector2(g * 0.3, g * 0.9), c + Vector2(-g * 0.3, g * 0.9), c + Vector2(-g * 0.65, g * 0.45), c + Vector2(-g * 0.3, -g * 0.2)]), INK)
		"frost":  # snowflake
			for i in 3:
				var d := Vector2.from_angle(PI / 2.0 + i * PI / 3.0) * g
				draw_line(c - d, c + d, INK, w * 0.8, true)
		"crit":  # star
			var pts := PackedVector2Array()
			for i in 10:
				pts.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * (g if i % 2 == 0 else g * 0.45))
			draw_colored_polygon(pts, INK)
		"bounce":  # a hop between two dots
			draw_arc(c + Vector2(0, g * 0.35), g * 0.75, PI, TAU, 16, INK, w * 0.8, true)
			draw_circle(c + Vector2(-g * 0.75, g * 0.4), g * 0.28, INK)
			draw_circle(c + Vector2(g * 0.75, g * 0.4), g * 0.28, INK)
		"nth":  # three dots, the last one big
			draw_circle(c + Vector2(-g * 0.7, g * 0.1), g * 0.2, INK)
			draw_circle(c + Vector2(-g * 0.05, g * 0.1), g * 0.2, INK)
			draw_circle(c + Vector2(g * 0.62, g * 0.1), g * 0.36, INK)
		"swap":  # two arrows
			draw_line(c + Vector2(-g, -g * 0.4), c + Vector2(g, -g * 0.4), INK, w * 0.8, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(g, -g * 0.85), c + Vector2(g, g * 0.05), c + Vector2(g * 1.35, -g * 0.4)]), INK)
			draw_line(c + Vector2(g, g * 0.4), c + Vector2(-g, g * 0.4), INK, w * 0.8, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-g, g * 0.85), c + Vector2(-g, -g * 0.05), c + Vector2(-g * 1.35, g * 0.4)]), INK)
