class_name MedalBadge
extends Control
## A lesson's medal: a coloured disc, or an empty ring when it has none yet.

var medal := AcademyMedals.NONE:
	set(v):
		medal = v
		queue_redraw()


func _init(size_px := 34.0) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	var col: Color = AcademyMedals.COLORS[clampi(medal, AcademyMedals.NONE, AcademyMedals.GOLD)]
	if medal <= AcademyMedals.NONE:
		draw_arc(c, r, 0.0, TAU, 40, col, 2.0, true)
		return
	draw_circle(c, r, col.darkened(0.45))
	draw_circle(c, r * 0.78, col)
	draw_arc(c, r, 0.0, TAU, 40, col.lightened(0.3), 1.5, true)
