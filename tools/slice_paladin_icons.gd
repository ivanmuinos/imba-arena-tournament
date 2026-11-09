extends SceneTree
## Paladin icons from referencias/Habilidades paladin.jpeg (6 rune circles, 3x2) and referencias/Paladin.jpeg (class):
##   godot --headless --path . --script res://tools/slice_paladin_icons.gd -- <out_dir>   (copy the PNGs to assets/icons)
## 128 px, cropped inside the rune ring like the other hand-made icons; the class one is centred on the head.
const CELLS := {"crusader": Vector2(172, 205), "holylight": Vector2(512, 205), "hammer": Vector2(852, 205),
	"blessing": Vector2(172, 722), "layhands": Vector2(512, 722), "cleanse": Vector2(852, 722)}
const SIDE := 205.0
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(ProjectSettings.globalize_path("res://referencias/Habilidades paladin.jpeg"))
	src.convert(Image.FORMAT_RGBA8)
	var sheet := Image.create(7 * 132, 132, false, Image.FORMAT_RGBA8)
	var i := 0
	for id in CELLS:
		var c: Vector2 = CELLS[id]
		var ic := src.get_region(Rect2i(int(c.x - SIDE / 2), int(c.y - SIDE / 2), int(SIDE), int(SIDE)))
		ic.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		ic.save_png(a[0].path_join(id + ".png"))
		sheet.blit_rect(ic, Rect2i(0, 0, 128, 128), Vector2i(132 * i, 0))
		i += 1
	var cls := Image.load_from_file(ProjectSettings.globalize_path("res://referencias/Paladin.jpeg"))
	cls.convert(Image.FORMAT_RGBA8)
	var ci := cls.get_region(Rect2i(512 - 172, 205 - 172, 344, 344))
	ci.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	ci.save_png(a[0].path_join("class_paladin.png"))
	sheet.blit_rect(ci, Rect2i(0, 0, 128, 128), Vector2i(132 * 6, 0))
	sheet.save_png(a[0].path_join("_sheet.png"))
	quit()
