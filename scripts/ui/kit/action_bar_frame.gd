class_name ActionBarFrame
extends Control
## The action bar from the HUD kit (see HudArt): the skull-and-lava bar with eight holes for the buttons, the red orb
## (your health) on the left and the blue orb (the ultimate's charge) on the right; both empty from the top.

const S := 0.5  # kit px -> HUD px
const BUTTON := 60.0  # the HUD's buttons, scaled into the holes
const BAR := {"origin": Vector2(430, 36), "at": Vector2(365, 18)}
const RED := {"tex": "orb_red_frame", "origin": Vector2(22, 16), "at": Vector2(0, 0), "orb": [Vector2(273, 204), 98.0], "fill": "orb_red"}
const BLUE := {"tex": "orb_blue_frame", "origin": Vector2(22, 793), "at": Vector2(1770, 2), "orb": [Vector2(243, 989), 97.0], "fill": "orb_blue"}
const HOLES_X := [639, 765, 892, 1019, 1161, 1287, 1412, 1540]  # left edge of each hole's inside (kit px)
const HOLE_Y := 191
const HOLE := 102.0
const SIZE := Vector2(2212, 344)

var _buttons: Array = []
var _hp: TextureProgressBar
var _ult: TextureProgressBar
var _hp_text: Label
var _ult_text: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE * S
	var bar := HudArt.art("bar")
	bar.position = BAR.at * S
	bar.size = bar.texture.get_size() * S
	add_child(bar)
	_hp = _orb(RED)
	_ult = _orb(BLUE)
	_hp_text = _orb_label(RED)
	_ult_text = _orb_label(BLUE)


func _orb(spec: Dictionary) -> TextureProgressBar:
	var frame := HudArt.art(spec.tex)
	frame.position = spec.at * S
	frame.size = frame.texture.get_size() * S
	add_child(frame)
	var r: float = spec.orb[1]
	var o := TextureProgressBar.new()
	o.texture_progress = HudArt.tex(spec.fill)
	o.fill_mode = TextureProgressBar.FILL_BOTTOM_TO_TOP
	o.nine_patch_stretch = true
	o.max_value = 1.0
	o.step = 0.001
	o.value = 1.0
	o.position = (spec.orb[0] - Vector2(r + 1, r + 1) - spec.origin + spec.at) * S
	o.size = Vector2(r * 2 + 2, r * 2 + 2) * S
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(o)
	return o


func _orb_label(spec: Dictionary) -> Label:
	var l := UiKit.label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(l, 6)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var c: Vector2 = (spec.orb[0] - spec.origin + spec.at) * S
	l.position = c - Vector2(50, 15)
	l.size = Vector2(100, 30)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func clear() -> void:
	for b in _buttons:
		remove_child(b)
		b.queue_free()
	_buttons.clear()


## Puts the next button (BUTTON x BUTTON) into the next hole.
func add_button(b: Control) -> void:
	var i := _buttons.size()
	var x: float = HOLES_X[mini(i, HOLES_X.size() - 1)] + maxf(0, i - HOLES_X.size() + 1) * 126.0
	var k := (HOLE * S) / BUTTON
	b.scale = Vector2(k, k)
	b.position = (Vector2(x - 1, HOLE_Y - 1) - BAR.origin + BAR.at) * S
	add_child(b)
	_buttons.append(b)


func set_health(hp: float, max_hp: float) -> void:
	_hp.value = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_hp_text.text = str(int(hp))


func set_ult(pct: float) -> void:
	_ult.value = clampf(pct / 100.0, 0.0, 1.0)
	_ult_text.text = "%d%%" % int(pct)
