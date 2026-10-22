class_name ChatPanel
extends CanvasLayer
## Shared lobby/match chat; plain text prevents markup injection.

signal submitted(text: String)
var entry: LineEdit
var panel: PanelContainer
var log_label: Label
var toggle: Button
var lines: Array[String] = []
var enabled := false


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	toggle = Button.new()
	toggle.text = "Chat (Enter)"
	toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	toggle.position = Vector2(-160, 8)
	toggle.size = Vector2(144, 32)
	toggle.pressed.connect(func():
		if typing(): close_entry()
		else: open_entry())
	root.add_child(toggle)
	panel = PanelContainer.new()
	panel.position = Vector2(16, 170)
	panel.custom_minimum_size = Vector2(340, 0)
	panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.02, 0.02, 0.04, 0.88), UiKit.LINE, 8, 1, 10))
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	log_label = UiKit.label("Enter: chat de la sala", 13, UiKit.INK)
	log_label.custom_minimum_size = Vector2(320, 0)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(log_label)
	entry = LineEdit.new()
	entry.max_length = Wire.CHAT_MAX
	entry.placeholder_text = "Todos · Enter enviar · Esc cerrar"
	entry.text_submitted.connect(func(text):
		if not text.strip_edges().is_empty(): submitted.emit(text)
		close_entry())
	box.add_child(entry)
	entry.hide()
	panel.hide()
	toggle.hide()


func activate(on: bool) -> void:
	enabled = on
	toggle.visible = on
	close_entry()


func typing() -> bool:
	return enabled and entry.visible


func close_entry() -> void:
	entry.clear()
	entry.release_focus()
	entry.hide()
	panel.hide()


func open_entry() -> void:
	panel.show()
	entry.show()
	entry.grab_focus()
	toggle.text = "Chat (Enter)"


func blocks_mouse(point: Vector2) -> bool:
	return enabled and (toggle.get_global_rect().has_point(point) or (panel.visible and panel.get_global_rect().has_point(point)))


func receive(msg: Dictionary) -> void:
	lines.append("%s: %s" % [msg.name, msg.text])
	while lines.size() > 4: lines.pop_front()
	log_label.text = "\n".join(lines)
	if not typing(): toggle.text = "Chat · nuevo"


func _input(event: InputEvent) -> void:
	if not enabled or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and typing():
		close_entry()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and not typing():
		open_entry()
		get_viewport().set_input_as_handled()
