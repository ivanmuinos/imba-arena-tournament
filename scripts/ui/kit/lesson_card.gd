class_name LessonCard
extends PanelContainer
## The card of a guided step: who speaks, caption, title, a strip showing how far the lesson is, the text (typed out as if
## spoken), a checklist and buttons. Used by the tutorial and the Academia lessons. Nothing here blocks the game: the
## objectives are always written in full, and a click on the card finishes the typing.

const CARD_W := 420.0
## Letters per second of the typed text.
const TYPE_SPEED := 85.0

var portrait_slot: HBoxContainer
var buttons: HBoxContainer
var face: TizonFace
var _caption: Label
var _title: Label
var _body: RichTextLabel
var _list: VBoxContainer
var _pips: Control
var _status: Label
var _result: VBoxContainer
var _pip_index := 0
var _pip_total := 0
var _typed := 0.0
var _typing := false
var _source := ""


## BBCode of the step texts uses [key]..[/key] for key caps.
static func bb(text: String) -> String:
	return text.replace("[key]", "[bgcolor=#ffd27a][color=#1a0800] ").replace("[/key]", " [/color][/bgcolor]")


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.box(Color(0.05, 0.032, 0.027, 0.95), UiKit.LINE_STRONG, 14, 2, 16))
	custom_minimum_size = Vector2(CARD_W, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	col.add_child(header)
	portrait_slot = HBoxContainer.new()
	header.add_child(portrait_slot)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(titles)
	_caption = UiKit.caption("", UiKit.LAVA, 12)
	titles.add_child(_caption)
	_title = UiKit.heading("", 26, UiKit.GOLD, 700, 1)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(CARD_W - 130.0, 0)
	titles.add_child(_title)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 10)
	col.add_child(strip)
	_pips = Control.new()
	_pips.custom_minimum_size = Vector2(0, 6)
	_pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.draw.connect(_draw_pips)
	_pips.visible = false
	strip.add_child(_pips)
	_status = UiKit.label("", 13, UiKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_status.visible = false
	strip.add_child(_status)
	_result = VBoxContainer.new()
	_result.add_theme_constant_override("separation", 8)
	_result.visible = false
	col.add_child(_result)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(CARD_W - 34.0, 0)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_font_size_override("normal_font_size", 15)
	_body.add_theme_font_size_override("bold_font_size", 15)
	_body.add_theme_font_override("bold_font", UiKit.body(700))
	_body.add_theme_color_override("default_color", Color("#e6dccf"))
	_body.add_theme_constant_override("line_separation", 3)
	col.add_child(_body)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	col.add_child(_list)
	buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	col.add_child(buttons)
	set_process(false)


func show_step(caption: String, title: String, text: String, objectives: Array) -> void:
	_caption.text = caption
	_title.text = title
	set_text(text)
	_clear(_list)
	for o in objectives:
		_list.add_child(_objective_row(o))
	_clear(buttons)
	_fit()


## The same text again (an objective got ticked) keeps what was already typed; a new one is typed from the start.
func set_text(text: String) -> void:
	_body.text = bb(text)
	if text == _source:
		return
	_source = text
	if face == null or not is_inside_tree():
		_body.visible_characters = -1
		return
	_typed = 0.0
	_typing = true
	_body.visible_characters = 0
	set_process(true)


func set_title(title: String) -> void:
	_title.text = title


## Puts Tizón next to the title, with the face of this step.
func set_coach(mood: String) -> void:
	if face == null:
		face = TizonFace.new(68.0, mood)
		portrait_slot.add_child(face)
	face.mood = mood


## How far the lesson is: one segment per step, the current one lit.
func set_progress(index: int, total: int) -> void:
	_pip_index = index
	_pip_total = total
	_pips.visible = total > 1
	_pips.queue_redraw()


## A short line at the right of the strip (the medal still in reach). "" hides it.
func set_status(text: String, color: Color = UiKit.MUTED) -> void:
	_status.text = text
	_status.visible = text != ""
	_status.add_theme_color_override("font_color", color)


func is_typing() -> bool:
	return _typing


func finish_typing() -> void:
	_typing = false
	_body.visible_characters = -1
	set_process(false)


## The closing block of a lesson, over the text: the medal landing, what the run was like and what the next medal asks for.
## `rows`: [[label, value]...].
func show_result(medal: int, rows: Array, next_goal: String) -> MedalBadge:
	_clear(_result)
	_result.visible = true
	_pips.get_parent().visible = false
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	_result.add_child(top)
	var badge := MedalBadge.new(104.0)
	badge.medal = medal
	top.add_child(badge)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(grid)
	for r in rows:
		grid.add_child(UiKit.caption(str(r[0]).to_upper(), UiKit.MUTED, 11))
		grid.add_child(UiKit.heading(str(r[1]), 20, UiKit.INK, 700, 0, HORIZONTAL_ALIGNMENT_RIGHT))
	var ladder := HBoxContainer.new()
	ladder.add_theme_constant_override("separation", 6)
	ladder.alignment = BoxContainer.ALIGNMENT_CENTER
	_result.add_child(ladder)
	for m in [AcademyMedals.BRONZE, AcademyMedals.SILVER, AcademyMedals.GOLD]:
		var chip := PanelContainer.new()
		var on: bool = medal >= m
		var col: Color = AcademyMedals.COLORS[m]
		chip.add_theme_stylebox_override("panel", UiKit.box(Color(col, 0.2) if on else Color(0, 0, 0, 0.3), Color(col, 0.9) if on else Color(1, 1, 1, 0.08), 20, 1, 4))
		var l := UiKit.caption("  %s  " % str(AcademyMedals.NAMES[m]).to_upper(), col if on else UiKit.DIM, 11)
		chip.add_child(l)
		ladder.add_child(chip)
	if next_goal != "":
		var goal := RichTextLabel.new()
		goal.bbcode_enabled = true
		goal.fit_content = true
		goal.scroll_active = false
		goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		goal.custom_minimum_size = Vector2(CARD_W - 34.0, 0)
		goal.add_theme_font_size_override("normal_font_size", 14)
		goal.add_theme_font_size_override("bold_font_size", 14)
		goal.add_theme_color_override("default_color", UiKit.MUTED)
		goal.text = "[center]%s[/center]" % next_goal
		_result.add_child(goal)
	var rule := ColorRect.new()
	rule.color = UiKit.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	_result.add_child(rule)
	if medal > AcademyMedals.NONE and is_inside_tree():
		badge.pop.call_deferred()
	_fit()
	return badge


## Gone now, not at the end of the frame: the card measures itself right after.
static func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## The card shrinks back after a long step. Once more a frame later: wrapped text only knows its height after a layout pass.
func _fit() -> void:
	reset_size.call_deferred()
	if is_inside_tree():
		get_tree().process_frame.connect(func(): reset_size(), CONNECT_ONE_SHOT)


func add_button(text: String, variant: String, cb: Callable) -> MButton:
	var b := MButton.new(text, variant)
	b.custom_minimum_size = Vector2(118 if variant == "secondary" else 0, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	if variant == "primary":
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(b)
	return b


func _process(delta: float) -> void:
	if not _typing:
		set_process(false)
		return
	_typed += delta * TYPE_SPEED
	var total := _body.get_total_character_count()
	if _typed >= float(total):
		finish_typing()
	else:
		_body.visible_characters = int(_typed)


func _gui_input(event: InputEvent) -> void:
	if _typing and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		finish_typing()
		accept_event()


func _draw_pips() -> void:
	if _pip_total <= 0:
		return
	var gap := 4.0
	var w := (_pips.size.x - gap * float(_pip_total - 1)) / float(_pip_total)
	for i in _pip_total:
		var r := Rect2(float(i) * (w + gap), 1.0, w, 4.0)
		var col := UiKit.GOLD if i < _pip_index else UiKit.LAVA if i == _pip_index else Color(1, 1, 1, 0.12)
		_pips.draw_rect(r, col)


func _objective_row(o: Dictionary) -> PanelContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.box(Color(0.42, 0.87, 0.54, 0.09) if o.done else Color(1, 1, 1, 0.045), Color(0.42, 0.87, 0.54, 0.35) if o.done else Color(1, 1, 1, 0.07), 8, 1, 7))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var mark := Icons.rect("ui_check" if o.done else "ui_dot", 20)
	mark.modulate = UiKit.GREEN if o.done else UiKit.GOLD
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(mark)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size = Vector2(CARD_W - 92.0, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_size_override("normal_font_size", 14)
	t.add_theme_font_size_override("bold_font_size", 14)
	t.add_theme_font_override("bold_font", UiKit.body(700))
	t.add_theme_color_override("default_color", UiKit.MUTED if o.done else UiKit.INK)
	var need := int(o.get("need", 1))
	t.text = bb(str(o.text) + (" (%d/%d)" % [mini(int(o.get("n", 0)), need), need] if need > 1 else ""))
	row.add_child(t)
	return box
