class_name Textures
extends RefCounted
## Procedural tiling textures (no external assets): ground, glowing cracks, lava, moon water.

static var _cache := {}


static func clear_cache() -> void:
	_cache.clear()


static func _noise(kind: int, freq: float, seed_v: int, cellular_dist2sub := false) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = kind
	n.frequency = freq
	n.seed = seed_v
	if cellular_dist2sub:
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		n.cellular_jitter = 1.0
	return n


static func _field(n: FastNoiseLite, size: int) -> Image:
	return n.get_seamless_image(size, size, false, false, 0.15, true)


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## [albedo, glow] for the arena floor.
static func ground(moon: bool) -> Array:
	var key := "ground_moon" if moon else "ground_magma"
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var speck := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 11), size)
	var grain := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.4, 12), size)
	var cells := _field(_noise(FastNoiseLite.TYPE_CELLULAR, 0.035, 13, true), size)
	var albedo := Image.create(size, size, true, Image.FORMAT_RGB8)
	var glow := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var s := speck.get_pixel(x, y).r
			var g := grain.get_pixel(x, y).r
			var c := cells.get_pixel(x, y).r
			var crack := 1.0 - smoothstep(0.0, 0.11, c)
			var col: Color
			var gl := Color.BLACK
			if moon:
				# Moss, leaf litter and dark soil under the giant trees.
				col = Color(0.2, 0.26, 0.3).lerp(Color(0.26, 0.36, 0.38), smoothstep(0.35, 0.8, s) * 0.6)
				col = col.lerp(Color(0.3, 0.22, 0.4), smoothstep(0.7, 0.95, g) * 0.15)
				col = col.lerp(Color(0.04, 0.05, 0.08), crack * 0.6)
				if g > 0.93:
					gl = Color(0.25, 0.85, 1.0) if s > 0.5 else Color(0.7, 0.4, 1.0)
			else:
				col = Color(0.27, 0.17, 0.13).lerp(Color(0.44, 0.29, 0.22), smoothstep(0.3, 0.8, s))
				col = col * (0.94 + g * 0.12)
				col = col.lerp(Color(0.05, 0.025, 0.015), crack * 0.5)
				gl = Color(1.0, 0.3, 0.0) * crack
			albedo.set_pixel(x, y, col)
			glow.set_pixel(x, y, gl)
	_cache[key] = [_tex(albedo), _tex(glow)]
	return _cache[key]


## Basalt strata for cliffs and slopes (tiling, triplanar in the terrain shader).
static func rock() -> ImageTexture:
	if _cache.has("rock"):
		return _cache["rock"]
	var size := 256
	var a := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.03, 41), size)
	var b := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.18, 42), size)
	var c := _field(_noise(FastNoiseLite.TYPE_CELLULAR, 0.05, 43, true), size)
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := a.get_pixel(x, y).r * 0.5 + b.get_pixel(x, y).r * 0.3
			var edge := 1.0 - smoothstep(0.0, 0.14, c.get_pixel(x, y).r)
			var col := Color(0.2, 0.17, 0.15).lerp(Color(0.42, 0.36, 0.32), v)
			img.set_pixel(x, y, col.lerp(Color(0.05, 0.04, 0.04), edge * 0.7))
	_cache["rock"] = _tex(img)
	return _cache["rock"]


static func lava() -> ImageTexture:
	if _cache.has("lava"):
		return _cache["lava"]
	var size := 256
	var a := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.02, 21), size)
	var b := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.07, 22), size)
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(0.35, 0.02, 0.0), Color(0.85, 0.2, 0.0), Color(1.0, 0.45, 0.05), Color(1.0, 0.9, 0.45)])
	for y in size:
		for x in size:
			var v := a.get_pixel(x, y).r * 0.65 + b.get_pixel(x, y).r * 0.35
			img.set_pixel(x, y, ramp.sample(clampf(v, 0.0, 1.0)))
	_cache["lava"] = _tex(img)
	return _cache["lava"]


static func moonwell() -> ImageTexture:
	if _cache.has("moonwell"):
		return _cache["moonwell"]
	var size := 256
	var a := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.025, 31), size)
	var b := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.09, 32), size)
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(0.1, 0.3, 0.6), Color(0.3, 0.7, 1.0), Color(0.6, 0.92, 1.0), Color(0.95, 1.0, 1.0)])
	for y in size:
		for x in size:
			var v := a.get_pixel(x, y).r * 0.6 + b.get_pixel(x, y).r * 0.4
			img.set_pixel(x, y, ramp.sample(clampf(v, 0.0, 1.0)))
	_cache["moonwell"] = _tex(img)
	return _cache["moonwell"]


## Soft round sprite for particles (white centre fading out).
static func glow_dot() -> ImageTexture:
	if _cache.has("dot"):
		return _cache["dot"]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size / 2.0 + 0.5, y - size / 2.0 + 0.5).length() / (size / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_cache["dot"] = ImageTexture.create_from_image(img)
	return _cache["dot"]


## Calm floor for the Tomb: slate flagstones with slow tonal drift and faint seams. Deliberately no
## high-frequency noise and no glowing specks (the old texture was tiring on large surfaces).
static func ground_calm() -> Array:
	if _cache.has("ground_calm"):
		return _cache["ground_calm"]
	var size := 256
	var drift := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 61), size)
	var mid := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.035, 62), size)
	var cells := _field(_noise(FastNoiseLite.TYPE_CELLULAR, 0.016, 63, true), size)
	var albedo := Image.create(size, size, true, Image.FORMAT_RGB8)
	var glow := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var d := drift.get_pixel(x, y).r
			var m := mid.get_pixel(x, y).r
			var seam := 1.0 - smoothstep(0.0, 0.06, cells.get_pixel(x, y).r)
			var col := Color(0.16, 0.175, 0.2).lerp(Color(0.25, 0.265, 0.3), d * 0.8 + m * 0.2)
			col = col.lerp(col * 0.62, seam * 0.5)
			albedo.set_pixel(x, y, col)
			glow.set_pixel(x, y, Color.BLACK)
	_cache["ground_calm"] = [_tex(albedo), _tex(glow)]
	return _cache["ground_calm"]


## Kit-material textures: [albedo, normal] per kind: "stone" (carved, pitted), "wood" (bark), "metal" (pitted iron).
static func kit(kind: String) -> Array:
	var key := "kit_" + kind
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var big := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.02, 71), size)
	var mid := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.06, 72), size)
	var fine := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.22, 73), size)
	var cells := _field(_noise(FastNoiseLite.TYPE_CELLULAR, 0.045, 74, true), size)
	var streak := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 75), size)
	var albedo := Image.create(size, size, true, Image.FORMAT_RGB8)
	var height := Image.create(size, size, true, Image.FORMAT_L8)
	for y in size:
		for x in size:
			var b := big.get_pixel(x, y).r
			var m := mid.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r
			var c := cells.get_pixel(x, y).r
			var edge := 1.0 - smoothstep(0.0, 0.1, c)
			var v := 0.0
			var h := 0.0
			match kind:
				"wood":
					# vertical grain: stretch the streak noise along y by sampling a narrow column band
					var s := streak.get_pixel(x, (y * 7) % size).r
					v = 0.55 + (s - 0.5) * 0.7 + (b - 0.5) * 0.3
					h = s * 0.8 + f * 0.2
				"metal":
					v = 0.6 + (b - 0.5) * 0.35 + (f - 0.5) * 0.1 - edge * 0.12
					h = 0.5 + (f - 0.5) * 0.3 + (m - 0.5) * 0.2
				_:
					v = 0.62 + (b - 0.5) * 0.2 + (m - 0.5) * 0.1 + (f - 0.5) * 0.05 - edge * 0.16
					h = 0.5 + (m - 0.5) * 0.5 + (f - 0.5) * 0.3 - edge * 0.5
			albedo.set_pixel(x, y, Color(v, v * 0.98, v * 0.95))
			height.set_pixel(x, y, Color(h, h, h))
	height.bump_map_to_normal_map(5.0 if kind != "metal" else 2.0)
	height.convert(Image.FORMAT_RGB8)
	_cache[key] = [_tex(albedo), _tex(height)]
	return _cache[key]


## Seamless soft noise used by the spell shaders (orb breakup, trails, scorch marks).
static func spell_noise() -> ImageTexture:
	if _cache.has("spell_noise"):
		return _cache["spell_noise"]
	var img := _field(_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.03, 91), 128)
	img.convert(Image.FORMAT_L8)
	_cache["spell_noise"] = _tex(img)
	return _cache["spell_noise"]
