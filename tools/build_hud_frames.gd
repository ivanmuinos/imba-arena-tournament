extends SceneTree
## Cuts the ability bar's rune frames out of the HUD reference (referencias/, a row of six stone frames on black):
##   godot --headless --script res://tools/build_hud_frames.gd -- <reference.jpeg> <out_dir>
## Writes slot_left/mid/right.png (first, inner and last button of a bar) and slot_solo.png (a lone button). The icon
## window and the black around the frame become transparent; the violet glow keeps its colour on any background.

const Y := [396, 632]          # crop rows (frame plus glow)
const FRAME_Y := [405, 620]    # stone frame rows: always opaque
const WIN_Y := [444, 580]      # icon window rows: transparent (minus INSET)
const INSET := 6               # the frame overlaps the button this much, so no background shows between them
## name -> [crop x0, crop x1, frame x0, frame x1, window x0, window x1]
const PIECES := {
	"left": [8, 186, 16, 186, 40, 170],
	"mid": [349, 512, 349, 512, 366, 496],
	"right": [837, 1018, 837, 1008, 854, 984],
}


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(a[0])
	src.convert(Image.FORMAT_RGBA8)
	var out := {}
	for k in PIECES:
		out[k] = _piece(src, PIECES[k])
		out[k].save_png(a[1].path_join("slot_%s.png" % k))
	# a lone button: the left frame's left half joined to the right frame's right half
	var l: Image = out.left
	var r: Image = out.right
	var lw: int = (PIECES.left[4] + PIECES.left[5]) / 2 - PIECES.left[0]
	var rx: int = (PIECES.right[4] + PIECES.right[5]) / 2 - PIECES.right[0]
	var solo := Image.create(lw + r.get_width() - rx, l.get_height(), false, Image.FORMAT_RGBA8)
	solo.blit_rect(l, Rect2i(0, 0, lw, l.get_height()), Vector2i.ZERO)
	solo.blit_rect(r, Rect2i(rx, 0, r.get_width() - rx, r.get_height()), Vector2i(lw, 0))
	solo.save_png(a[1].path_join("slot_solo.png"))
	quit()


func _piece(src: Image, p: Array) -> Image:
	var img := Image.create(p[1] - p[0], Y[1] - Y[0], false, Image.FORMAT_RGBA8)
	for y in range(Y[0], Y[1]):
		for x in range(p[0], p[1]):
			var c := src.get_pixel(x, y)
			if x >= p[4] + INSET and x < p[5] - INSET and y >= WIN_Y[0] + INSET and y < WIN_Y[1] - INSET:
				c = Color(0, 0, 0, 0)
			elif not (x >= p[2] and x < p[3] and y >= FRAME_Y[0] and y < FRAME_Y[1]):
				var lum := maxf(c.r, maxf(c.g, c.b))
				var al := clampf((lum - 0.03) * 3.0, 0.0, 1.0)
				c = Color(minf(c.r / al, 1.0), minf(c.g / al, 1.0), minf(c.b / al, 1.0), al) if al > 0.0 else Color(0, 0, 0, 0)
			img.set_pixel(x - p[0], y - Y[0], c)
	return img
