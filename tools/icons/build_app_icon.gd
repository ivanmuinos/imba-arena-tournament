extends SceneTree
## The game's icon from the IMBA shield of the interface kit (referencias/interfaz_kit.jpeg), with rounded corners:
##   godot --headless --script res://tools/icons/build_app_icon.gd -- <interfaz_kit.jpeg> <out_dir>
## Writes icon_<size>.png for 16..1024; tools/icons/pack_app_icon.py packs them into icon.ico / icon.icns.

const CROP := Rect2i(150, 40, 528, 528)
const SIZES := [16, 32, 48, 64, 128, 256, 512, 1024]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(a[0])
	src.convert(Image.FORMAT_RGBA8)
	var base := src.get_region(CROP)
	base.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	var rad := 180.0
	for y in 1024:
		for x in 1024:
			var cx := clampf(x + 0.5, rad, 1024 - rad)
			var cy := clampf(y + 0.5, rad, 1024 - rad)
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, cy))
			if d > rad - 2.0:
				var c := base.get_pixel(x, y)
				c.a *= clampf((rad - d) / 2.0, 0.0, 1.0)
				base.set_pixel(x, y, c)
	for s in SIZES:
		var im := base.duplicate()
		im.resize(s, s, Image.INTERPOLATE_LANCZOS)
		im.save_png(a[1].path_join("icon_%d.png" % s))
	quit()
