class_name MenuLogo
extends VBoxContainer
## IMBA ARENA TOURNAMENT logo: the shield from the interface kit (assets/ui/menu/logo.png, its edges faded so it sits
## on any background), with a slow breathing glow.

const SIZE := Vector2(620, 449)

var _art: TextureRect
var _glow_tw: Tween


func _init(scale_ := 1.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art = TextureRect.new()
	_art.texture = load("res://assets/ui/menu/logo.png")
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.custom_minimum_size = SIZE * scale_
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)


func _ready() -> void:
	_glow_tw = create_tween().set_loops()
	_glow_tw.tween_method(_set_glow, 0.0, 1.0, 1.8).set_trans(Tween.TRANS_SINE)
	_glow_tw.tween_method(_set_glow, 1.0, 0.0, 1.8).set_trans(Tween.TRANS_SINE)


func _set_glow(a: float) -> void:
	_art.modulate = Color(1.0 + 0.12 * a, 1.0 + 0.06 * a, 1.0)
