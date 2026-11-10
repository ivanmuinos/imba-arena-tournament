class_name LessonCard
extends PanelContainer
## The card of a guided step: caption, title, text, a checklist and buttons. Used by the tutorial and the Academia lessons.
## `portrait_slot` is empty until a lesson has someone to show next to the title.

const CARD_W := 390.0

var portrait_slot: HBoxContainer
var buttons: HBoxContainer
var _caption: Label
var _title: Label
var _body: RichTextLabel
var _list: VBoxContainer


## BBCode of the step texts uses [key]..[/key] for key caps.
static func bb(text: String) -> String:
	return text.replace("[key]", "[bgcolor=#ffd27a][color=#1a0800] ").replace("[/key]", " [/color][/bgcolor]")


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.box(Color(0.045, 0.03, 0.026, 0.93), UiKit.LINE_STRONG, 12, 2, 14))
	custom_minimum_size = Vector2(CARD_W, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	col.add_child(header)
	portrait_slot = HBoxContainer.new()
	header.add_child(portrait_slot)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	_caption = UiKit.caption("", UiKit.LAVA, 12)
	titles.add_child(_caption)
	_title = UiKit.heading("", 26, UiKit.GOLD, 700, 1)
	titles.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(CARD_W - 30.0, 0)
	_body.add_theme_font_size_override("normal_font_size", 15)
	_body.add_theme_font_size_override("bold_font_size", 15)
	_body.add_theme_color_override("default_color", Color("#e6dccf"))
	col.add_child(_body)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	col.add_child(_list)
	buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	col.add_child(buttons)


func show_step(caption: String, title: String, text: String, objectives: Array) -> void:
	_caption.text = caption
	_title.text = title
	set_text(text)
	for c in _list.get_children():
		c.queue_free()
	for o in objectives:
		_list.add_child(_objective_row(o))
	for c in buttons.get_children():
		c.queue_free()
	reset_size.call_deferred()  # the card shrinks back after a long step


func set_text(text: String) -> void:
	_body.text = bb(text)


func set_title(title: String) -> void:
	_title.text = title


func add_button(text: String, variant: String, cb: Callable) -> MButton:
	var b := MButton.new(text, variant)
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 16)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	if variant == "primary":
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(b)
	return b


func _objective_row(o: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var mark := Icons.rect("ui_check" if o.done else "ui_dot", 20)
	mark.modulate = UiKit.GREEN if o.done else UiKit.DIM
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(mark)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size = Vector2(CARD_W - 70.0, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_size_override("normal_font_size", 14)
	t.add_theme_font_size_override("bold_font_size", 14)
	t.add_theme_color_override("default_color", UiKit.DIM if o.done else UiKit.INK)
	var need := int(o.get("need", 1))
	t.text = bb(str(o.text) + (" (%d/%d)" % [int(o.get("n", 0)), need] if need > 1 else ""))
	row.add_child(t)
	return row
