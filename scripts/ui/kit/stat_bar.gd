class_name StatBar
extends Control
## Five-segment stat bar (1-5) that animates to its value.

var value := 0.0:
	set(v):
		value = v
		queue_redraw()
var color := UiKit.LAVA
var _tw: Tween


func _init() -> void:
	custom_minimum_size = Vector2(0, 14)
	mouse_filter = Control.MOUSE_FILTER_PASS  # hover shows the numbers behind the bar


func animate_to(v: float, c: Color) -> void:
	color = c
	if _tw != null:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "value", v, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var gap := 5.0
	var w := (size.x - gap * 4.0) / 5.0
	for i in 5:
		var x := i * (w + gap)
		var r := Rect2(x, 2, w, size.y - 4)
		draw_rect(r, Color(1, 1, 1, 0.09))
		var fill := clampf(value - i, 0.0, 1.0)
		if fill > 0.0:
			draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), color)
			draw_rect(Rect2(r.position, Vector2(r.size.x * fill, 2)), color.lightened(0.45))
