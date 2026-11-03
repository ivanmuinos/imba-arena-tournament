extends SceneTree
## The 6-hole action bar (basic, 3 abilities, ultimate, trinket) cut from the 8-hole one (assets/ui/hud/bar.png):
##   godot --headless --path . --script res://tools/build_bar6.gd
## Two full columns are taken out, each one hole wide from the middle of a separator to the middle of the next: the
## 2nd hole (left of the centre skull) and the 7th (right of it), so both halves keep their end caps and the centre.
## Coordinates are bar.png px (kit px - 430); scripts/ui/kit/action_bar_frame.gd places the buttons with the result.

const SRC := "res://assets/ui/hud/bar.png"
const OUT := "res://assets/ui/hud/bar6.png"
## [from, to) columns removed, left to right.
const CUTS := [[323, 449], [970, 1097]]


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	src.convert(Image.FORMAT_RGBA8)
	var removed := 0
	for c in CUTS:
		removed += c[1] - c[0]
	var out := Image.create(src.get_width() - removed, src.get_height(), false, Image.FORMAT_RGBA8)
	var x := 0
	var dst := 0
	for c in CUTS + [[src.get_width(), src.get_width()]]:
		var w: int = c[0] - x
		out.blit_rect(src, Rect2i(x, 0, w, src.get_height()), Vector2i(dst, 0))
		dst += w
		x = c[1]
	out.save_png(ProjectSettings.globalize_path(OUT))
	print("bar6: %dx%d" % [out.get_width(), out.get_height()])
	quit()
