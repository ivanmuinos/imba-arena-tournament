extends SceneTree
## The 11 ability icons the first sheet lacked, from referencias/iconos_faltantes.jpeg (circles on a 1024 sheet):
##   godot --headless --script res://tools/slice_missing_icons.gd -- <sheet.jpeg> <out_dir>   (copy the PNGs to assets/icons)
## Cropped inside the rune ring like the rest, 128 px.

const SIDE := 150.0
## id -> centre of its circle on the sheet
const CELLS := {
	"darkpact": Vector2(137, 160), "drainlife": Vector2(388, 160), "strike": Vector2(640, 160), "pummel": Vector2(890, 160),
	"smite": Vector2(137, 495), "rejuv": Vector2(388, 495), "bash": Vector2(640, 495), "slash": Vector2(890, 495),
	"sweep": Vector2(212, 830), "upcut": Vector2(512, 830), "spark": Vector2(818, 830),
}


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(a[0])
	src.convert(Image.FORMAT_RGBA8)
	for id in CELLS:
		var c: Vector2 = CELLS[id]
		var ic := src.get_region(Rect2i(int(c.x - SIDE / 2), int(c.y - SIDE / 2), int(SIDE), int(SIDE)))
		ic.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		ic.save_png(a[1].path_join(id + ".png"))
	quit()
