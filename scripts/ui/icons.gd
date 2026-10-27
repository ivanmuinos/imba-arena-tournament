class_name Icons
extends RefCounted
## The SVG icon set (assets/icons, drawn by tools/icons/build_icons.py), plus PNG overrides. No emoji anywhere: they break
## on Windows.

static var _cache := {}
static var _blank: ImageTexture = null


static func tex(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path := "res://assets/icons/%s.png" % id  # a hand-made PNG overrides the generated SVG of the same id
	if not ResourceLoader.exists(path):
		path = "res://assets/icons/%s.svg" % id
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else _blank_tex()
	_cache[id] = t
	return t


static func _blank_tex() -> Texture2D:
	if _blank == null:
		_blank = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	return _blank


static func rect(id: String, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(id)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return r


static func clear_cache() -> void:
	_cache.clear()
	_blank = null
