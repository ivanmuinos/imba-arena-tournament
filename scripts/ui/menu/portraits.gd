class_name Portraits
extends RefCounted
## Class portraits and map thumbnails rendered from the real assets by tools/render_menu_art.gd.

static var _cache := {}


static func tex(cls: String) -> Texture2D:
	return _load("res://assets/ui/portraits/%s.png" % cls)


## Head and shoulders crop (top of the portrait) for small tiles and chips.
static func bust(cls: String) -> Texture2D:
	var key := "bust_" + cls
	if not _cache.has(key):
		var full := tex(cls)
		if full == null:
			_cache[key] = null
		else:
			var at := AtlasTexture.new()
			at.atlas = full
			at.region = Rect2(0, 0, full.get_width(), full.get_height() * 0.62)
			_cache[key] = at
	return _cache[key]


static func map_tex(map_id: String) -> Texture2D:
	return _load("res://assets/ui/maps/%s.png" % map_id)


static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


static func clear_cache() -> void:
	_cache.clear()
