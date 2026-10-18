extends SceneTree
## Rasterises assets/app_icon/icon.svg at every size the .ico/.icns need (called by build_app_icon.py).

func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://assets/app_icon/icon.svg")
	for s in [16, 32, 48, 64, 128, 256, 512, 1024]:
		var img := Image.new()
		var err := img.load_svg_from_string(svg, float(s) / 1024.0)
		if err != OK:
			printerr("svg error ", err)
		img.convert(Image.FORMAT_RGBA8)
		img.save_png("res://assets/app_icon/icon_%d.png" % s)
	quit()
