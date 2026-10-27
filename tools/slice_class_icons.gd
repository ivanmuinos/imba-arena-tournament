extends SceneTree
## Class portraits from referencias/iconos_clases.jpeg (12 rune circles, the classes in data/classes.json order):
##   godot --headless --script res://tools/slice_class_icons.gd -- <sheet.jpeg> <out_dir>   (copy the PNGs to assets/icons)
## Cropped inside the rune ring, 128 px; the HUD shows them in round portraits.

const IDS := ["mage", "warlock", "hunter", "warrior", "priest", "rogue", "druid", "ct", "ronin", "crack", "wizard", "ki"]
const COLS := [177, 405, 631, 856]
const ROWS := [96, 280, 463]
const SIDE := 124


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(a[0])
	src.convert(Image.FORMAT_RGBA8)
	for i in IDS.size():
		var c := Vector2i(COLS[i % 4], ROWS[i / 4])
		var ic := src.get_region(Rect2i(c - Vector2i(SIDE, SIDE) / 2, Vector2i(SIDE, SIDE)))
		ic.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		ic.save_png(a[1].path_join("class_%s.png" % IDS[i]))
	quit()
