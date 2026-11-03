class_name ForfeitPanel
extends Control
## "Rendirse" confirmation inside the match (never an OS dialog): a dimmed full-screen layer with a small card.
## Esc opens it when there is nothing else to cancel; in a tournament a forfeit counts as a loss. Only offline matches use it.

signal confirmed
signal cancelled

var confirm_button: MButton
var stay_button: MButton

var _text: Label


## Esc opens the panel only when it would otherwise do nothing: no ground spell, no cast and no target to drop.
static func esc_opens(pending_ground: bool, casting: bool, has_target: bool, enabled: bool) -> bool:
	return enabled and not pending_ground and not casting and not has_target


static func message(tournament: bool) -> String:
	if tournament:
		return "Rendirte cuenta como una derrota en el torneo."
	return "Vas a perder esta partida."


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.box(Color(0.045, 0.03, 0.026, 0.96), UiKit.LINE_STRONG, 12, 1, 22))
	card.custom_minimum_size = Vector2(440, 0)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	col.add_child(UiKit.heading("¿RENDIRTE?", 30, UiKit.GOLD, 700, 2, HORIZONTAL_ALIGNMENT_CENTER))
	_text = UiKit.label("", 16, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	stay_button = MButton.new("Seguir peleando", "accent")
	confirm_button = MButton.new("Rendirme", "secondary")
	col.add_child(stay_button)
	col.add_child(confirm_button)
	stay_button.pressed.connect(func(): close(); cancelled.emit())
	confirm_button.pressed.connect(func(): close(); confirmed.emit())


func open(text: String) -> void:
	_text.text = text
	visible = true
	stay_button.grab_focus.call_deferred()


func close() -> void:
	visible = false
