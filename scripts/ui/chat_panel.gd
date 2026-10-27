class_name ChatPanel
extends CanvasLayer
## Shared lobby/match chat; plain text prevents markup injection.
## Lobby: always on screen (top right, beside the title) with the text box visible, so nobody has to guess that Enter
## talks. Match: the last lines show bottom left and fade a while after the last message, with a small "Enter para
## chatear" hint; the text box appears on Enter. Laid out on the 1280x720 design stage like the lobby and the HUD.

signal submitted(text: String)

const HISTORY := 50
const SHOW_LOBBY := 3
const SHOW_MATCH := 6
## Seconds a match message stays fully visible before fading out.
const FADE_AFTER := 10.0
const FADE_TIME := 1.5
const LOBBY_RECT := Rect2(668, 14, 540, 120)
## End screen: bottom right, beside the buttons and under the scoreboards (the big VICTORIA/DERROTA title is on top).
const END_RECT := Rect2(668, 560, 540, 120)
const MATCH_WIDTH := 380.0
## Above the kill feed (bottom left) and clear of the ally frames (top left).
const MATCH_BOTTOM := 150.0

var entry: LineEdit
var panel: PanelContainer
var log_label: Label
var hint: Label
var lines: Array[String] = []
var enabled := false
var mode := "lobby"

var _stage: Control
var _caption: Label
var _quiet := 0.0  # seconds since the last message (match fading)


func _ready() -> void:
	layer = 20
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_caption = UiKit.caption("Chat de la sala", UiKit.LAVA, 11)
	box.add_child(_caption)
	log_label = UiKit.label("", 13, UiKit.INK)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_constant_override("outline_size", 4)
	log_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	box.add_child(log_label)
	entry = LineEdit.new()
	entry.max_length = Wire.CHAT_MAX
	entry.placeholder_text = "Escribí un mensaje · Enter para enviar"
	entry.add_theme_font_size_override("font_size", 14)
	entry.text_submitted.connect(func(text):
		if not text.strip_edges().is_empty(): submitted.emit(text)
		close_entry())
	box.add_child(entry)
	hint = UiKit.label("Enter para chatear", 12, UiKit.MUTED)
	hint.add_theme_constant_override("outline_size", 4)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(hint)
	panel.hide()
	hint.hide()
	_rescale()
	get_viewport().size_changed.connect(_rescale)


func _rescale() -> void:
	var win := Vector2(get_viewport().get_visible_rect().size)
	var s := Hud.ui_scale_for(win)
	var b := MenuScreen.content_box(win)
	_stage.scale = Vector2(s, s)
	_stage.position = b.position
	_stage.size = b.size
	_layout()


func _layout() -> void:
	if mode != "match":
		var r := END_RECT if mode == "end" else LOBBY_RECT
		panel.position = r.position
		panel.custom_minimum_size = Vector2(r.size.x, 0)
		panel.size = Vector2(r.size.x, 0)
		log_label.custom_minimum_size = Vector2(r.size.x - 20, 0)
	else:
		panel.custom_minimum_size = Vector2(MATCH_WIDTH, 0)
		panel.size = Vector2(MATCH_WIDTH, 0)
		log_label.custom_minimum_size = Vector2(MATCH_WIDTH - 20, 0)
		panel.reset_size()
		panel.position = Vector2(16, _stage.size.y - MATCH_BOTTOM - panel.size.y)
		hint.position = Vector2(20, _stage.size.y - MATCH_BOTTOM + 4)


## on: lobby/match/end screens. `p_mode`: "lobby", "end" (same as the lobby, placed elsewhere) or "match".
func activate(on: bool, p_mode := "lobby") -> void:
	enabled = on
	mode = p_mode
	var lobby := mode != "match"
	panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.03, 0.02, 0.02, 0.82 if lobby else 0.55), UiKit.LINE, 10, 1, 10))
	_caption.visible = lobby
	# The lobby box has a fixed height (the teams start right under it): one line per message, cut with "…".
	log_label.autowrap_mode = TextServer.AUTOWRAP_OFF if lobby else TextServer.AUTOWRAP_WORD_SMART
	log_label.clip_text = lobby
	log_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if lobby else TextServer.OVERRUN_NO_TRIMMING
	entry.release_focus()
	entry.clear()
	_render()
	_quiet = 0.0
	panel.modulate.a = 1.0
	if not on:
		panel.hide()
		hint.hide()
		return
	entry.visible = lobby
	hint.visible = not lobby
	panel.visible = lobby or not lines.is_empty()
	_layout()


func typing() -> bool:
	return enabled and entry.visible and entry.has_focus()


## After sending or Esc: the lobby keeps the box on screen, the match hides it again.
func close_entry() -> void:
	entry.clear()
	entry.release_focus()
	if mode == "match":
		entry.hide()
		if lines.is_empty():
			panel.hide()
		_layout()


func open_entry() -> void:
	panel.show()
	entry.show()
	panel.modulate.a = 1.0
	_quiet = 0.0
	_layout()
	entry.grab_focus()


func blocks_mouse(point: Vector2) -> bool:
	return enabled and panel.visible and panel.modulate.a > 0.05 and panel.get_global_rect().has_point(point)


func receive(msg: Dictionary) -> void:
	lines.append("%s: %s" % [msg.name, msg.text])
	while lines.size() > HISTORY:
		lines.pop_front()
	_render()
	if enabled:
		panel.show()
		panel.modulate.a = 1.0
		_quiet = 0.0
		_layout()


## Clears the history (a new session).
func clear() -> void:
	lines.clear()
	_render()


func _render() -> void:
	var n := SHOW_MATCH if mode == "match" else SHOW_LOBBY
	var shown := lines.slice(maxi(0, lines.size() - n))
	if shown.is_empty() and mode != "match":
		log_label.text = "Todavía no hay mensajes."
		log_label.add_theme_color_override("font_color", UiKit.DIM)
	else:
		log_label.text = "\n".join(shown)
		log_label.add_theme_color_override("font_color", UiKit.INK)


## Match only: after FADE_AFTER quiet seconds the lines fade out (typing keeps them).
func fade(delta: float) -> void:
	if not enabled or mode != "match" or typing() or not panel.visible:
		return
	_quiet += delta
	panel.modulate.a = clampf(1.0 - (_quiet - FADE_AFTER) / FADE_TIME, 0.0, 1.0)


func _process(delta: float) -> void:
	fade(delta)


func _input(event: InputEvent) -> void:
	if not enabled or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and typing():
		close_entry()
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not typing():
		var fo := get_viewport().gui_get_focus_owner()
		if fo is LineEdit:
			return  # another text field (e.g. a name) keeps its Enter
		open_entry()
		get_viewport().set_input_as_handled()
