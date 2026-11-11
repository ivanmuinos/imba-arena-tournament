class_name TizonFace
extends Control
## Tizón's face in a round frame, with the expression of the moment. He nods when the mood changes.

const MOODS := ["neutral", "contenta", "burlona", "seria", "orgullosa"]
## The part of the portrait (512x640) that holds his head.
const HEAD := Rect2(51.0, 45.0, 410.0, 410.0)
const RING := {"neutral": Color("#ffb060"), "contenta": Color("#ffc15a"), "burlona": Color("#ff8a3c"), "seria": Color("#ff5a52"), "orgullosa": Color("#ffe08a")}

var mood := "neutral":
	set(v):
		var next: String = v if MOODS.has(v) else "neutral"
		if next == mood and _tex != null:
			return
		mood = next
		_tex = load("res://assets/ui/portraits/tizon_%s.png" % mood) as Texture2D
		queue_redraw()
		if is_inside_tree():
			_nod()
var bob := 0.0:
	set(v):
		bob = v
		queue_redraw()

var _tex: Texture2D
var _tw: Tween


func _init(size_px := 64.0, p_mood := "neutral") -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	mood = p_mood
	if _tex == null:
		_tex = load("res://assets/ui/portraits/tizon_%s.png" % mood) as Texture2D


func _nod() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "bob", 1.0, 0.09)
	_tw.tween_property(self, "bob", 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var r := s / 2.0 - 2.0
	var ring: Color = RING.get(mood, UiKit.GOLD)
	draw_circle(c, r, Color(0.16, 0.07, 0.04, 0.96))
	draw_circle(c, r * 0.86, Color(ring, 0.16))
	if _tex != null:
		var grow := s * 0.05 * bob
		draw_texture_rect_region(_tex, Rect2(c.x - r * 0.9 - grow / 2.0, c.y - r * 0.86 + s * 0.05 * bob - grow / 2.0, r * 1.8 + grow, r * 1.8 + grow), HEAD)
	draw_arc(c, r, 0.0, TAU, 48, ring, maxf(2.0, s * 0.04), true)
	draw_arc(c, r + 1.5, 0.0, TAU, 48, Color(0, 0, 0, 0.55), 1.5, true)
