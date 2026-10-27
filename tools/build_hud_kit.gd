extends SceneTree
## Cuts the match HUD out of the HUD kit reference (referencias/hud_kit_2.jpeg, 2752x1536, pieces on dark slate):
##   godot --headless --script res://tools/build_hud_kit.gd -- <hud_kit_2.jpeg> <out_dir>
## The background is removed by flood fill from the crop's edges (so dark outlines stay solid). Bar tracks are emptied
## (the game draws the fill) and the orbs drained (the game fills them back from the bottom with orb_*.png).
## Every coordinate here is in kit px; scripts/ui/kit/hud_art.gd places things with the same numbers.

const PIECES := {
	"bar": {"rect": Rect2i(430, 36, 1430, 326), "erase": [Rect2i(430, 336, 592, 26), Rect2i(1262, 336, 598, 26)]},
	"orb_red_frame": {"rect": Rect2i(22, 16, 390, 344), "orb": [Vector2(273, 204), 98.0], "orb_out": "orb_red"},
	"orb_blue_frame": {"rect": Rect2i(22, 793, 442, 342), "orb": [Vector2(243, 989), 97.0], "orb_out": "orb_blue"},
	"frame_ally": {"rect": Rect2i(1163, 792, 798, 246), "erase": [Rect2i(1945, 792, 16, 246)],
		"tracks": [Rect2i(1412, 884, 338, 36), Rect2i(1412, 932, 340, 28), Rect2i(1411, 969, 344, 31)], "empty_x": 1745, "empty_y": [969, 1000]},
	"frame_enemy": {"rect": Rect2i(1891, 17, 832, 344), "erase": [Rect2i(2232, 240, 491, 121)],
		"tracks": [Rect2i(2235, 107, 311, 32), Rect2i(2241, 150, 306, 33)], "empty_x": 2540, "empty_y": [107, 138]},
	"bar_focus": {"rect": Rect2i(2245, 256, 470, 90), "tracks": [Rect2i(2329, 298, 362, 30)], "empty_x": 2655, "empty_y": [298, 327]},
	"panel": {"rect": Rect2i(1998, 1193, 318, 324), "scale": 0.35},
}


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(a[0])
	src.convert(Image.FORMAT_RGBA8)
	for name in PIECES:
		var p: Dictionary = PIECES[name]
		var r: Rect2i = p.rect
		var img := src.get_region(r)
		for e in p.get("erase", []):
			img.fill_rect(Rect2i(e.position - r.position, e.size), _bg(src, r))
		_key_out(img, _bg(src, r))
		for t in p.get("tracks", []):
			_empty_track(src, img, r, t, p.empty_x, p.empty_y)
		if p.has("orb"):
			_drain(img, r, p.orb[0], p.orb[1], a[1].path_join(p.orb_out + ".png"))
		if p.has("scale"):
			img.resize(int(r.size.x * p.scale), int(r.size.y * p.scale), Image.INTERPOLATE_LANCZOS)
		img.save_png(a[1].path_join(name + ".png"))
	quit()


func _bg(src: Image, r: Rect2i) -> Color:
	var c := src.get_pixel(r.position.x + 2, r.position.y + 2)
	c.a = 1.0
	return c


## Flood fill from the edges over pixels close to the slate: those become transparent, with a 1 px soft edge.
func _key_out(img: Image, bg: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if seen[i] == 1:
			continue
		var c := img.get_pixel(i % w, i / w)
		if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.11:
			continue
		seen[i] = 1
		var x := i % w
		var y := i / w
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	for i in w * h:
		var x := i % w
		var y := i / w
		if seen[i] == 1:
			img.set_pixel(x, y, Color(0, 0, 0, 0))
		elif (x > 0 and seen[i - 1] == 1) or (x < w - 1 and seen[i + 1] == 1) or (y > 0 and seen[i - w] == 1) or (y < h - 1 and seen[i + w] == 1):
			var c := img.get_pixel(x, y)
			c.a = 0.55
			img.set_pixel(x, y, c)


## Paints a track with the colours of an empty stretch of a track (one column, stretched to this track's height).
func _empty_track(src: Image, img: Image, r: Rect2i, t: Rect2i, ex: int, ey: Array) -> void:
	for y in t.size.y:
		var sy := int(lerpf(ey[0], ey[1], float(y) / maxf(1.0, t.size.y - 1)))
		var c := src.get_pixel(ex, sy)
		for x in t.size.x:
			img.set_pixel(t.position.x - r.position.x + x, t.position.y - r.position.y + y, c)


## Saves the round orb on its own and leaves a dark, empty glass in the frame.
func _drain(img: Image, r: Rect2i, centre: Vector2, rad: float, out: String) -> void:
	var c := centre - Vector2(r.position)
	var n := int(rad * 2) + 2
	var orb := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var off := Vector2(x - rad - 1, y - rad - 1)
			var d := off.length()
			if d > rad + 1:
				continue
			var p := Vector2i(c + off)
			var col := img.get_pixel(p.x, p.y)
			var edge := clampf(rad + 1 - d, 0.0, 1.0)
			orb.set_pixel(x, y, Color(col.r, col.g, col.b, edge))
			var lum := col.get_luminance()
			var dark := Color(lum, lum, lum).lerp(col, 0.3) * 0.22
			img.set_pixel(p.x, p.y, col.lerp(Color(dark.r, dark.g, dark.b, 1.0), edge))
	orb.save_png(out)
