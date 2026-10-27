class_name ActionBarFrame
extends PanelContainer
## The ability bar: every button sits in a carved stone frame with violet runes (assets/ui/hud, cut from the HUD reference
## by tools/build_hud_frames.gd). The frames touch, so the row reads as one bar; this container itself draws nothing.

const BUTTON := 60.0  # side of the button inside each frame
const ART_WIN := Vector2(130, 136)  # the icon window in the art
const S := BUTTON / 130.0  # art px -> HUD px
const WIN_X := {"left": 32, "mid": 17, "right": 17, "solo": 32}  # left edge of the window in each piece (art px)
const WIN_Y := 48

static var _tex := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())


## Which piece the button at `i` of `n` takes: the end ones carry the outer glow.
static func piece_for(i: int, n: int) -> String:
	if n == 1:
		return "solo"
	return "left" if i == 0 else ("right" if i == n - 1 else "mid")


## Puts `button` (BUTTON x BUTTON) in the window of a frame piece; returns the framed control for the bar.
static func framed(button: Control, piece: String) -> Control:
	if not _tex.has(piece):
		_tex[piece] = load("res://assets/ui/hud/slot_%s.png" % piece)
	var t: Texture2D = _tex[piece]
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(t.get_size()) * S
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.position = Vector2(WIN_X[piece], WIN_Y + (ART_WIN.y - ART_WIN.x) / 2.0) * S
	holder.add_child(button)
	var art := TextureRect.new()  # over the button: only its window is see-through
	art.texture = t
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	holder.add_child(art)
	return holder
