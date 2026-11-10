class_name MedalBadge
extends Control
## A lesson's medal: a ribbon and a struck disc in its metal, or an empty ring when it has none yet.

var medal := AcademyMedals.NONE:
	set(v):
		medal = v
		queue_redraw()
## 0..1 sweep of the shine across the disc (-1: none). Animated by pop().
var shine := -1.0:
	set(v):
		shine = v
		queue_redraw()


func _init(size_px := 34.0) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Lands with a bounce and a shine: the moment a medal is won.
func pop() -> void:
	pivot_offset = size / 2.0
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "shine", 1.0, 0.6).from(0.0)
	tw.tween_callback(func(): shine = -1.0)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := Vector2(size.x / 2.0, size.y / 2.0 + s * 0.06)
	var r := s * 0.36
	var col: Color = AcademyMedals.COLORS[clampi(medal, AcademyMedals.NONE, AcademyMedals.GOLD)]
	if medal <= AcademyMedals.NONE:
		draw_arc(c, r, 0.0, TAU, 40, Color(col, 0.9), maxf(1.5, s * 0.05), true)
		draw_circle(c, r * 0.18, Color(col, 0.6))
		return
	# ribbon: two tails behind the disc
	var top := c.y - r * 1.25
	for sx in [-1.0, 1.0]:
		var tail := PackedVector2Array([Vector2(c.x + sx * r * 0.15, top), Vector2(c.x + sx * r * 0.85, top), Vector2(c.x + sx * r * 0.55, c.y), Vector2(c.x - sx * r * 0.05, c.y)])
		draw_colored_polygon(tail, Color("#b3271c") if sx < 0.0 else Color("#d8382a"))
	draw_circle(c + Vector2(0, s * 0.03), r, Color(0, 0, 0, 0.35))
	draw_circle(c, r, col.darkened(0.5))
	draw_circle(c, r * 0.9, col.darkened(0.12))
	draw_circle(c - Vector2(0, r * 0.06), r * 0.74, col)
	draw_arc(c, r * 0.74, PI * 1.05, PI * 1.75, 16, col.lightened(0.55), maxf(1.0, s * 0.035), true)
	# a five-point star struck in the middle
	var star := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		star.append(c - Vector2(0, r * 0.04) + Vector2(cos(a), sin(a)) * r * (0.46 if i % 2 == 0 else 0.2))
	draw_colored_polygon(star, col.darkened(0.3))
	if shine >= 0.0:
		var x := c.x - r + shine * r * 2.0
		for i in 5:
			var dx := x + (float(i) - 2.0) * r * 0.07
			var half := sqrt(maxf(0.0, r * r * 0.81 - (dx - c.x) * (dx - c.x)))
			if half > 0.5:
				draw_line(Vector2(dx, c.y - half), Vector2(dx, c.y + half), Color(1, 1, 1, 0.28 - absf(float(i) - 2.0) * 0.08), maxf(1.0, r * 0.07))
