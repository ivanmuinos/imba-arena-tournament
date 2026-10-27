extends SceneTree
## Cuts the menu pieces out of the interface kit (referencias/interfaz_kit.jpeg, 2752x1536, drawn over a scene):
##   godot --headless --script res://tools/build_menu_kit.gd -- <interfaz_kit.jpeg> <out_dir>
## The pieces are rectangles, so they are cut by shape (rounded corners) instead of by colour. Buttons lose their
## baked-in word: each is rebuilt as left cap + a smooth middle (each row's average over a clean stretch of the face)
## + right cap, a 9-slice whose middle stretches.
## btn_primary.png (the orange JUGAR), btn_secondary.png (the dark ember INICIO, without its flames),
## panel_wood.png (the wood square with gold corners), logo.png (the IMBA shield, its scene faded out round the edges).

## name -> [outer rect, left cap end x, clean stretch of the face [x0, x1], right cap start x, corner radius, scale]
const BUTTONS := {
	"btn_primary": [Rect2i(456, 703, 336, 106), 490, [494, 532], 762, 12.0, 0.5],
	"btn_secondary": [Rect2i(476, 914, 298, 144), 506, [508, 542], 748, 9.0, 0.36],
}
const PANEL := [Rect2i(258, 1036, 156, 172), 8.0, 0.6]
const LOGO := Rect2i(70, 80, 690, 500)


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(a[0])
	src.convert(Image.FORMAT_RGBA8)
	for name in BUTTONS:
		var b: Array = BUTTONS[name]
		var r: Rect2i = b[0]
		var left: int = b[1] - r.position.x
		var strip: Array = b[2]
		var right: int = r.end.x - b[3]
		var sw := 8
		var img := Image.create(left + sw + right, r.size.y, false, Image.FORMAT_RGBA8)
		img.blit_rect(src, Rect2i(r.position.x, r.position.y, left, r.size.y), Vector2i(0, 0))
		for y in r.size.y:
			var acc := Color(0, 0, 0, 0)
			for x in range(strip[0], strip[1]):
				acc += src.get_pixel(x, r.position.y + y)
			acc /= float(strip[1] - strip[0])
			for x in sw:
				img.set_pixel(left + x, y, acc)
		img.blit_rect(src, Rect2i(b[3], r.position.y, right, r.size.y), Vector2i(left + sw, 0))
		_round(img, b[4])
		_save(img, b[5], a[1].path_join(name + ".png"))
		print(name, " margins L%d R%d strip%d h%d (before scale %.2f)" % [left, right, sw, r.size.y, b[5]])
	var p := src.get_region(PANEL[0])
	_round(p, PANEL[1])
	_save(p, PANEL[2], a[1].path_join("panel_wood.png"))
	var logo := src.get_region(LOGO)
	var c := Vector2(LOGO.size) / 2.0
	for y in LOGO.size.y:
		for x in LOGO.size.x:
			var q := (Vector2(x, y) - c) / (c * Vector2(0.98, 0.96))  # elliptical fade: solid middle, soft rim
			var col := logo.get_pixel(x, y)
			col.a = 1.0 - smoothstep(0.62, 1.0, q.length())
			logo.set_pixel(x, y, col)
	logo.save_png(a[1].path_join("logo.png"))
	quit()


## Clears what lies outside a rounded rectangle the size of the image (the scene behind the piece).
func _round(img: Image, rad: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, rad, w - rad)
			var cy := clampf(y + 0.5, rad, h - rad)
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, cy))
			if d > rad - 1.0:
				var c := img.get_pixel(x, y)
				c.a *= clampf(rad - d, 0.0, 1.0)
				img.set_pixel(x, y, c)


func _save(img: Image, s: float, path: String) -> void:
	img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_LANCZOS)
	img.save_png(path)
