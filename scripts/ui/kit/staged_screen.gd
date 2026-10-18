class_name StagedScreen
extends Control
## Full-window screen with a 1280x720 design stage scaled uniformly to the window (same approach as the HUD).

var stage: Control


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	add_child(UiKit.backdrop(1.0))
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)


func _enter_tree() -> void:
	_rescale()
	if not get_viewport().size_changed.is_connected(_rescale):
		get_viewport().size_changed.connect(_rescale)


func _rescale() -> void:
	var win := Vector2(get_viewport().get_visible_rect().size)
	var s := Hud.ui_scale_for(win)
	var box := MenuScreen.content_box(win)
	stage.scale = Vector2(s, s)
	stage.position = box.position
	stage.size = box.size


static func shade() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.02, 0.01, 0.01, 0.35)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
