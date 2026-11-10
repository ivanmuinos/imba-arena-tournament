class_name ActionBarFrame
extends Control
## The action bar: one flat panel docked to the bottom edge of the screen, with your health and the ultimate's charge
## as two bars along its top and a row of six buttons under them (basic, 3 abilities, ultimate and the trinket).

const BUTTON := 60.0  # the HUD builds its buttons at this size; they are scaled into the slots
const SLOT := 46.0
const GAP := 4.0
const PAD := 6.0
const BAR_H := 14.0
const HOLES_X := [6.0, 56.0, 106.0, 156.0, 206.0, 256.0]  # left edge of each slot: PAD + i * (SLOT + GAP)
const SLOT_Y := PAD + BAR_H + 5.0
const SIZE := Vector2(PAD * 2.0 + 6.0 * SLOT + 5.0 * GAP, SLOT_Y + SLOT + PAD)
const ULT_W := 92.0

var _buttons: Array = []
var _hp: Bar
var _ult: Bar


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	var back := Panel.new()
	back.add_theme_stylebox_override("panel", HudArt.flat(HudArt.EDGE, 0, "bottom"))
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var w := SIZE.x - PAD * 2.0
	_hp = _bar(Rect2(PAD, PAD, w - ULT_W - GAP, BAR_H), Hud.HP_ALLY)
	_ult = _bar(Rect2(PAD + w - ULT_W, PAD, ULT_W, BAR_H), Color("#3d8ee6"))
	for x in HOLES_X:  # empty slots: a dark well with a dim edge, so a short kit still shows a whole bar
		var well := Panel.new()
		well.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.6), HudArt.EDGE_DIM, 2, 1, 0))
		well.position = Vector2(x, SLOT_Y)
		well.size = Vector2(SLOT, SLOT)
		well.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(well)


func _bar(r: Rect2, color: Color) -> Bar:
	var track := ColorRect.new()
	track.color = HudArt.TRACK
	track.position = r.position
	track.size = r.size
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(track)
	var b := Bar.new(0.0, color)
	b.bare = true
	b.position = r.position
	b.size = r.size
	add_child(b)
	return b


func clear() -> void:
	for b in _buttons:
		remove_child(b)
		b.queue_free()
	_buttons.clear()


## Puts the next button (BUTTON x BUTTON) into the next slot.
func add_button(b: Control) -> void:
	var i := _buttons.size()
	var x: float = HOLES_X[mini(i, HOLES_X.size() - 1)] + maxf(0, i - HOLES_X.size() + 1) * (SLOT + GAP)
	var k := SLOT / BUTTON
	b.scale = Vector2(k, k)
	b.position = Vector2(x, SLOT_Y)
	add_child(b)
	_buttons.append(b)


func set_health(hp: float, max_hp: float) -> void:
	_hp.ratio = hp / maxf(max_hp, 1.0)
	_hp.text = "%d / %d" % [int(hp), int(max_hp)]


func set_ult(pct: float) -> void:
	_ult.ratio = pct / 100.0
	_ult.text = "%d%%" % int(pct)


## A kit without an ultimate (Frost: Blink with charges on R): the bar stays empty and unlabelled.
func set_no_ult() -> void:
	_ult.ratio = 0.0
	_ult.text = ""
