class_name DmWindow
extends PanelContainer
## In-client chat window with one friend (Riot-style, docked beside the friends column): header with their name and
## state, the conversation (yours on the right in gold, theirs on the left), and the text box. A friend who is not in
## the game cannot get messages here, so the window says so and offers the Steam chat instead.

signal closed

const W := 340.0
const H := 400.0

var menu: MenuScreen
var friend_id := 0
var entry: LineEdit
var offline_note: VBoxContainer
var steam_button: MButton
var close_button: Button

var _name: Label
var _state: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _friend := {}


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.019, 0.016, 1.0)
	sb.border_color = UiKit.LINE_STRONG
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.set_corner_radius_all(UiKit.CORNER)
	sb.set_content_margin_all(0)
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	# header
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 0, 0, 12))
	col.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	head.add_child(hrow)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", -2)
	hrow.add_child(texts)
	_name = UiKit.heading("", 18, UiKit.INK, 700, 1)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(_name)
	_state = UiKit.label("", 12, UiKit.MUTED)
	texts.add_child(_state)
	close_button = Button.new()
	close_button.icon = Icons.tex("ui_close")
	close_button.expand_icon = true
	close_button.flat = true
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.add_theme_constant_override("icon_max_width", 16)
	close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.tooltip_text = "Cerrar"
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for k in ["icon_normal_color", "icon_focus_color"]:
		close_button.add_theme_color_override(k, UiKit.MUTED)
	close_button.add_theme_color_override("icon_hover_color", UiKit.INK)
	close_button.pressed.connect(close)
	hrow.add_child(close_button)
	# conversation
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	pad.add_child(_list)
	# not in the game
	offline_note = VBoxContainer.new()
	offline_note.add_theme_constant_override("separation", 8)
	var note_pad := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		note_pad.add_theme_constant_override("margin_" + side, 12)
	note_pad.add_child(offline_note)
	col.add_child(note_pad)
	var msg := UiKit.label("No está jugando Imba Arena: el chat del juego sólo llega a amigos que lo tienen abierto.", 13, UiKit.MUTED)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	offline_note.add_child(msg)
	steam_button = MButton.new("Abrir el chat de Steam", "secondary", "ui_steam")
	steam_button.add_theme_font_size_override("font_size", 15)
	steam_button.pressed.connect(_open_steam)
	offline_note.add_child(steam_button)
	# text box
	var entry_pad := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		entry_pad.add_theme_constant_override("margin_" + side, 12)
	col.add_child(entry_pad)
	entry = LineEdit.new()
	entry.max_length = Wire.CHAT_MAX
	entry.add_theme_font_size_override("font_size", 14)
	entry.text_submitted.connect(_send)
	entry_pad.add_child(entry)
	visible = false


func open(friend: Dictionary) -> void:
	_friend = friend
	friend_id = int(friend.id)
	menu.dm.open(friend_id)
	_name.text = str(friend.name)
	visible = true
	refresh_friend(friend)
	_render()
	if entry.visible:
		entry.grab_focus.call_deferred()


func close() -> void:
	visible = false
	if menu.dm != null:
		menu.dm.close()
	friend_id = 0
	closed.emit()


## The friend's state changed (joined or left the game): what can be done here follows.
func refresh_friend(friend: Dictionary) -> void:
	_friend = friend
	var app := menu.steam_backend.app_id() if menu.steam_backend != null else 0
	var can := DirectChat.can_chat(friend, app)
	_state.text = Social.state_text(friend, app)
	_state.add_theme_color_override("font_color", UiKit.GREEN if can else UiKit.MUTED)
	entry.visible = can
	entry.placeholder_text = "Escribile a %s · Enter para enviar" % friend.name
	offline_note.visible = not can


func _send(text: String) -> void:
	if friend_id != 0 and menu.dm.send(friend_id, text):
		entry.clear()


func _open_steam() -> void:
	if menu.steam_backend != null and not menu.steam_backend.open_overlay("chat", friend_id):
		menu.set_status(Social.overlay_note("chat"))


## Called when the conversation changes (sent or received).
func on_changed(id: int) -> void:
	if visible and id == friend_id:
		_render()


func _render() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var history := menu.dm.history_of(friend_id)
	if history.is_empty():
		var empty := UiKit.label("Todavía no hablaron. Mandale un mensaje.", 13, UiKit.DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	for m in history:
		_list.add_child(_bubble(m))
	_scroll_to_end.call_deferred()


func _bubble(m: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if m.me else BoxContainer.ALIGNMENT_BEGIN
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(0.42, 0.24, 0.06, 0.55) if m.me else Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), UiKit.CORNER + 2, 0, 8))
	var l := UiKit.label(str(m.text), 14, UiKit.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(230.0, 16.0 + str(m.text).length() * 7.5), 0)
	p.add_child(l)
	row.add_child(p)
	return row


func _scroll_to_end() -> void:
	if is_inside_tree():
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Plain text of the conversation (tests).
func log_text() -> String:
	return "\n".join(menu.dm.history_of(friend_id).map(func(m): return str(m.text)))
