class_name Bar
extends Control
## Flat progress bar (health, casts) with an optional text.

var ratio := 1.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
var fill := Color("#4caf50"):
	set(v):
		fill = v
		queue_redraw()
var back := Color(0, 0, 0, 0.7)
var edge := Color(0, 0, 0, 0.9)
var text := "":
	set(v):
		text = v
		queue_redraw()


func _init(h := 10.0, color := Color("#4caf50")) -> void:
	custom_minimum_size = Vector2(0, h)
	fill = color
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), back)
	draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * ratio, size.y - 2)), fill)
	draw_rect(Rect2(Vector2.ZERO, size), edge, false, 1.0)
	if text != "":
		var f := get_theme_default_font()
		var fs := int(maxf(9.0, size.y - 3.0))
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string_outline(f, Vector2((size.x - ts.x) / 2.0, size.y / 2.0 + ts.y / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2((size.x - ts.x) / 2.0, size.y / 2.0 + ts.y / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
