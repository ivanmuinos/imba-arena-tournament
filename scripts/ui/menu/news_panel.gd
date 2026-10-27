class_name NewsPanel
extends Control
## Home news (Riot-style): a big banner with map art and a champion splash that rotates through the stories (dots to
## pick one, auto-advance every ROTATE seconds), and CARDS cards under it (a click puts that story on the banner).
## Items come from NewsFeed: downloaded from Steam when the game runs under its own app id, else the cache, else
## data/news.json. Stories not seen before carry a "Nuevo" badge until the home is shown again.

const CARDS := 2
const BANNER_H := 380.0
const CARD_H := 170.0
const GAP := 16.0
const ROTATE := 8.0
## Art for stories that do not name any (cycled by position).
const FALLBACK_ART := [["tomb", "mage"], ["pillars", "warrior"], ["living", "warlock"], ["bridge", "hunter"], ["spire", "priest"], ["tomb", "rogue"]]

var menu: MenuScreen
var items: Array = []
## Ids marked "Nuevo" on the current showing.
var new_ids: Array = []
var featured := 0
var banner_art: TextureRect
var banner_title: Label
var cards: Array[Button] = []
var dots: Array[Button] = []

var _banner: Control
var _splash: TextureRect
var _text: VBoxContainer
var _tag: Label
var _badge: Label
var _date: Label
var _body: Label
var _open: MButton
var _dots_row: HBoxContainer
var _cards_row: HBoxContainer
var _timer: Timer
var _http: HTTPRequest
var _fetched := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_banner()
	_cards_row = HBoxContainer.new()
	_cards_row.position = Vector2(0, BANNER_H + GAP)
	_cards_row.add_theme_constant_override("separation", int(GAP))
	_cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards_row)
	_timer = Timer.new()
	_timer.wait_time = ROTATE
	_timer.timeout.connect(advance)
	add_child(_timer)
	items = NewsFeed.pick([], NewsFeed.load_cache(), NewsFeed.load_bundled())


## Width of one card: the row holds CARDS news cards plus the home's champion card, all the same width.
func card_width() -> float:
	return (size.x - GAP * CARDS) / (CARDS + 1)


func _build_banner() -> void:
	_banner = Control.new()
	_banner.clip_contents = true
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	banner_art = TextureRect.new()
	banner_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	banner_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(banner_art)
	_splash = TextureRect.new()
	# The whole bust, standing on the banner's bottom edge (placed in _place_splash once its size is known).
	_splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_splash.stretch_mode = TextureRect.STRETCH_SCALE
	_splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_splash)
	_banner.add_child(_shade(true))
	_banner.add_child(_shade(false))
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0), UiKit.LINE, 4, 1, 0))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(frame)
	_text = VBoxContainer.new()
	_text.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_text.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_text.position = Vector2(36, -32)
	_text.custom_minimum_size = Vector2(500, 0)
	_text.add_theme_constant_override("separation", 6)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_text)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_child(top)
	_tag = UiKit.caption("", UiKit.GOLD, 12)
	top.add_child(_tag)
	_badge = _new_badge()
	top.add_child(_badge)
	_date = UiKit.label("", 12, UiKit.MUTED)
	top.add_child(_date)
	banner_title = UiKit.heading("", 44, UiKit.INK, 700, 1)
	UiKit.outlined(banner_title, 6, Color(0, 0, 0, 0.55))
	banner_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_title.custom_minimum_size = Vector2(500, 0)
	banner_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_child(banner_title)
	_body = UiKit.label("", 15, Color("#d8cdc2"))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(480, 0)
	_body.max_lines_visible = 3
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_child(_body)
	_open = MButton.new("Leer más", "secondary")
	_open.custom_minimum_size = Vector2(150, 40)
	_open.add_theme_font_size_override("font_size", 15)
	_open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_open.pressed.connect(func(): _open_url(items[featured]))
	_text.add_child(_open)
	_dots_row = HBoxContainer.new()
	_dots_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_dots_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dots_row.position = Vector2(-28, -30)
	_dots_row.add_theme_constant_override("separation", 8)
	_banner.add_child(_dots_row)


## Dark gradients so the text reads over any art: from the left edge, and up from the bottom.
func _shade(horizontal: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.012, 0.01, 0.94))
	g.set_color(1, Color(0.02, 0.012, 0.01, 0.0))
	g.add_point(0.45 if horizontal else 0.5, Color(0.02, 0.012, 0.01, 0.55 if horizontal else 0.35))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	gt.fill_from = Vector2(0, 0) if horizontal else Vector2(0, 1)
	gt.fill_to = Vector2(0.75, 0) if horizontal else Vector2(0, 0.35)
	var t := TextureRect.new()
	t.texture = gt
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## {map, champion} for a story: its own "map"/"champion" fields when valid, else the fallback list by position.
static func art_for(it: Dictionary, index: int) -> Dictionary:
	var fb: Array = FALLBACK_ART[index % FALLBACK_ART.size()]
	var m := str(it.get("map", ""))
	var c := str(it.get("champion", ""))
	return {"map": m if GameMap.IDS.has(m) else str(fb[0]), "champion": c if GameData.playable(c) else str(fb[1])}


## Every time the home is shown: works out what is new, draws, and remembers everything shown as seen.
func show_news() -> void:
	var seen: Array = menu.st.get_value("news_seen")
	new_ids = NewsFeed.unseen(items, seen)
	featured = 0
	_rebuild()
	_mark_seen()
	_maybe_fetch()
	if is_inside_tree():
		_timer.start()


## Next story on the banner (the carousel wraps around).
func advance() -> void:
	if items.is_empty():
		return
	featured = (featured + 1) % items.size()
	_show_featured()


func _pick(index: int) -> void:
	UiSound.play("uiConfirm")
	featured = index
	_show_featured()
	if is_inside_tree():
		_timer.start()  # a manual pick restarts the countdown


func _mark_seen() -> void:
	var seen: Array = menu.st.get_value("news_seen").duplicate()
	for i in items:
		if not seen.has(str(i.id)):
			seen.append(str(i.id))
	menu.st.set_value("news_seen", seen)
	menu.st.save()


func _layout() -> void:
	_banner.position = Vector2.ZERO
	_banner.size = Vector2(size.x, BANNER_H)
	_cards_row.position = Vector2(0, BANNER_H + GAP)
	_place_splash()


## Keeps the bust's own proportions, its foot on the banner's bottom edge, near the right side.
func _place_splash() -> void:
	var t := _splash.texture
	if t == null or t.get_height() == 0:
		return
	var h := BANNER_H - 28.0
	var w := h * t.get_width() / t.get_height()
	_splash.size = Vector2(w, h)
	_splash.position = Vector2(size.x - w - 48.0, BANNER_H - h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		for c in cards:
			c.custom_minimum_size = Vector2(card_width(), CARD_H)


func _rebuild() -> void:
	visible = not items.is_empty()
	if items.is_empty():
		return
	_layout()
	for d in dots:
		d.queue_free()
	dots.clear()
	for i in items.size():
		var d := Button.new()
		d.custom_minimum_size = Vector2(26, 10)
		d.focus_mode = Control.FOCUS_NONE
		d.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		d.tooltip_text = str(items[i].title)
		var idx := i
		d.pressed.connect(func(): _pick(idx))
		_dots_row.add_child(d)
		dots.append(d)
	_show_featured()


func _show_featured() -> void:
	var f: Dictionary = items[featured]
	var art := art_for(f, featured)
	banner_art.texture = Portraits.map_tex(art.map)
	_splash.texture = Portraits.bust(art.champion)
	_place_splash()
	_tag.text = str(f.tag).to_upper()
	_badge.visible = new_ids.has(str(f.id))
	_date.text = date_text(int(f.date))
	banner_title.text = str(f.title)
	_body.text = str(f.body)
	_open.visible = str(f.get("url", "")).begins_with("https://")
	for i in dots.size():
		var on := i == featured
		var sb := UiKit.box(UiKit.GOLD if on else Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 5, 0, 0)
		for s in ["normal", "hover", "pressed", "focus"]:
			dots[i].add_theme_stylebox_override(s, sb)
	if is_inside_tree():
		_text.modulate.a = 0.0
		create_tween().tween_property(_text, "modulate:a", 1.0, 0.35)
	_rebuild_cards()


## The stories after the featured one, in order (wrapping), one card each.
func _rebuild_cards() -> void:
	for c in cards:
		_cards_row.remove_child(c)
		c.queue_free()
	cards.clear()
	for k in mini(CARDS, items.size() - 1):
		var idx := (featured + 1 + k) % items.size()
		var c := _card(idx)
		_cards_row.add_child(c)
		cards.append(c)


func _card(index: int) -> Button:
	var it: Dictionary = items[index]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(card_width(), CARD_H)
	b.clip_contents = true
	b.add_theme_stylebox_override("normal", UiKit.box(Color(0.045, 0.028, 0.022, 0.92), UiKit.LINE, 4, 1, 0))
	b.add_theme_stylebox_override("hover", UiKit.box(Color(0.08, 0.045, 0.03, 0.95), UiKit.LINE_STRONG, 4, 1, 0))
	b.add_theme_stylebox_override("pressed", UiKit.box(Color(0.08, 0.045, 0.03, 0.95), UiKit.GOLD, 4, 1, 0))
	b.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0), UiKit.GOLD, 4, 2, 0))
	var art := TextureRect.new()
	art.texture = Portraits.map_tex(art_for(it, index).map)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	art.offset_left = 1
	art.offset_right = -1
	art.offset_top = 1
	art.offset_bottom = 78
	art.modulate = Color(0.8, 0.8, 0.8)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(art)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 14
	col.offset_right = -14
	col.offset_top = 88
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var tag := UiKit.caption(str(it.tag), UiKit.GOLD, 11)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tag)
	if new_ids.has(str(it.id)):
		top.add_child(_new_badge())
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(fill)
	var d := UiKit.label(date_text(int(it.date)), 11, UiKit.DIM)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(d)
	var t := UiKit.heading(str(it.title), 18, UiKit.INK, 700, 0)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.max_lines_visible = 2
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(t)
	b.pressed.connect(func(): _pick(index))
	return b


func _new_badge() -> Label:
	var l := UiKit.heading("NUEVO", 11, Color("#1a0800"), 700, 1, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_stylebox_override("normal", UiKit.box(UiKit.LAVA, Color(0, 0, 0, 0), 3, 0, 3))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _open_url(it: Dictionary) -> void:
	var u := str(it.get("url", ""))
	if u.begins_with("https://"):
		OS.shell_open(u)


## "26 oct 2026"
static func date_text(unix: int) -> String:
	if unix <= 0:
		return ""
	var d := Time.get_date_dict_from_unix_time(unix)
	var months := ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
	return "%d %s %d" % [d.day, months[d.month - 1], d.year]


## Steam's public news feed of our own app (no key needed). Once per run; the cache serves the next start offline.
func _maybe_fetch() -> void:
	if _fetched or menu.steam_backend == null or not menu.steam_backend.available():
		return
	var app := menu.steam_backend.app_id()
	if not NewsFeed.remote_enabled(app):
		return
	_fetched = true
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_fetched)
	if _http.request(NewsFeed.url(app)) != OK:
		_http.queue_free()


func _on_fetched(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var fresh := NewsFeed.parse_steam(body.get_string_from_utf8())
	if fresh.is_empty():
		return
	NewsFeed.save_cache(fresh)
	var seen: Array = menu.st.get_value("news_seen")
	items = fresh
	new_ids = NewsFeed.unseen(items, seen)
	featured = 0
	_rebuild()
	_mark_seen()
