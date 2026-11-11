class_name MinimapImage
extends RefCounted
## Paints a map from above for the minimap: ground by what it is made of, shaded by its relief, with everything solid on
## top. North (-z) is up. Pure data in, an Image out: no nodes, so it is tested headless.

const GROUND := {"grass": Color("#3d5c24"), "path": Color("#a3855a"), "stone": Color("#827a72"), "lava": Color("#f26a14"), "water": Color("#3a8a9c")}
const ART := {"tree": Color("#1c3a14"), "rock": Color("#6e6a66"), "pillar": Color("#b8b0a4"), "broken_column": Color("#b8b0a4"), "statue": Color("#d8c9a0"), "crystal": Color("#7fe8ff"), "torch": Color("#ffb050")}
const WALL := Color("#2a2420")


## World point -> position on the image (0..1, 0..1).
static func uv_of(map: GameMap, x: float, z: float) -> Vector2:
	return Vector2(x / (2.0 * map.half_x) + 0.5, z / (2.0 * map.half_z) + 0.5)


static func paint(map: GameMap, px := 256) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var sx := 2.0 * map.half_x / float(px)
	var sz := 2.0 * map.half_z / float(px)
	for j in px:
		var z := -map.half_z + (float(j) + 0.5) * sz
		for i in px:
			var x := -map.half_x + (float(i) + 0.5) * sx
			var c: Color = GROUND.get(map.ground_kind(x, z), GROUND.grass)
			if map.relief:  # lit from the north-west, like a drawn map
				c = c.lightened(clampf((map.height_at(x, z) - map.height_at(x - 1.5, z - 1.5)) * 0.35, -0.3, 0.3)) if map.height_at(x, z) >= map.height_at(x - 1.5, z - 1.5) else c.darkened(clampf((map.height_at(x - 1.5, z - 1.5) - map.height_at(x, z)) * 0.35, 0.0, 0.3))
			img.set_pixel(i, j, c)
	for o in map.statics:
		if o.k == "c":
			var art := str(o.get("art", "rock"))
			var kind := "tree" if art.begins_with("tree") else "rock" if art.begins_with("rock") else art
			_disc(img, map, o.x, o.z, o.r * (2.0 if kind == "tree" else 1.2), ART.get(kind, ART.rock))
		else:
			_rect(img, map, o.x, o.z, o.hx, o.hz, WALL)
	return img


static func _disc(img: Image, map: GameMap, x: float, z: float, r: float, c: Color) -> void:
	var px := img.get_width()
	var centre := uv_of(map, x, z) * float(px)
	var rp := maxf(1.0, r / (2.0 * map.half_x) * float(px))
	for j in range(int(centre.y - rp), int(centre.y + rp) + 1):
		for i in range(int(centre.x - rp), int(centre.x + rp) + 1):
			if i >= 0 and j >= 0 and i < px and j < px and Vector2(float(i) + 0.5, float(j) + 0.5).distance_to(centre) <= rp:
				img.set_pixel(i, j, c)


static func _rect(img: Image, map: GameMap, x: float, z: float, hx: float, hz: float, c: Color) -> void:
	var px := img.get_width()
	var a := uv_of(map, x - hx, z - hz) * float(px)
	var b := uv_of(map, x + hx, z + hz) * float(px)
	for j in range(int(a.y), maxi(int(b.y), int(a.y) + 1) + 1):
		for i in range(int(a.x), maxi(int(b.x), int(a.x) + 1) + 1):
			if i >= 0 and j >= 0 and i < px and j < px:
				img.set_pixel(i, j, c)
