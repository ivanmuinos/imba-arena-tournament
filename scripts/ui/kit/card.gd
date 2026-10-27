class_name Card
extends Button
## Big selectable glass card (mode cards, map cards): icon or picture, title, one-liner.
## Hover lifts it (scale + glow border), focus draws an outline, selected keeps the accent border.

var accent := UiKit.LAVA
var glow := 0.0
var selected := false:
	set(v):
		selected = v
		_apply()

var _panel: PanelContainer
var _style: StyleBoxFlat
var _tw: Tween
var _art: Control
var _title: Label
var _sub: Label
var _badge: Label
var _col: VBoxContainer


## art: optional Control shown big on top (e.g. a map thumbnail); otherwise `icon_id` is drawn large.
func _init(icon_id := "", title := "", subtitle := "", accent_: Color = UiKit.LAVA, art: Control = null) -> void:
	accent = accent_
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	flat = true
	for s in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	_panel = UiKit.glass(UiKit.LINE, 14, 0, 3.4, 0.55)
	_panel.show_behind_parent = true
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style = _panel.get_theme_stylebox("panel") as StyleBoxFlat
	add_child(_panel)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_col = col
	col.minimum_size_changed.connect(update_minimum_size)  # a long title or subtitle grows the card instead of spilling out
	if art != null:
		_art = art
	elif icon_id != "":
		_art = _icon_art(icon_id)
	if _art != null:
		_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(_art)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sp)
	_title = UiKit.heading(title, 34, UiKit.INK, 700, 1)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_title)
	_sub = UiKit.label(subtitle, 14, UiKit.MUTED)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_sub)
	_badge = UiKit.caption("", UiKit.GOLD, 11)
	_badge.visible = false
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_badge)


## Big icon centred on a soft radial glow in the accent colour.
## Smaller, wrapping title (rows with five cards).
func set_title_size(px: int) -> void:
	_title.add_theme_font_size_override("font_size", px)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Height of the icon area (170 by default); rows of narrow cards use less so wrapped titles fit.
func set_art_height(px: int) -> void:
	if _art != null:
		_art.custom_minimum_size.y = px


func _get_minimum_size() -> Vector2:
	return _col.get_combined_minimum_size() + Vector2(36, 36) if _col != null else Vector2.ZERO


func _icon_art(icon_id: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 170)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(accent.r, accent.g, accent.b, 0.55), Color(accent.r, accent.g, accent.b, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var glow_tex := TextureRect.new()
	glow_tex.texture = gt
	glow_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow_tex.stretch_mode = TextureRect.STRETCH_SCALE
	glow_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow_tex)
	var ic := Icons.rect(icon_id, 112)
	ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ic.position -= Vector2(56, 56)
	ic.size = Vector2(112, 112)
	holder.add_child(ic)
	holder.set_meta("icon", ic)
	return holder


func _ready() -> void:
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	focus_entered.connect(_hover.bind(true))
	focus_exited.connect(_hover.bind(false))
	pressed.connect(func(): UiSound.play("uiSelect"))
	_apply()


func set_subtitle(t: String) -> void:
	_sub.text = t


func set_badge(t: String) -> void:
	_badge.text = t
	_badge.visible = t != ""


func _hover(on: bool) -> void:
	if disabled:
		return
	if on and glow < 0.5:
		UiSound.play("uiHover")
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "glow", 1.0 if on else 0.0, 0.18)
	_tw.tween_property(self, "scale", Vector2.ONE * (1.015 if on else 1.0), 0.18)
	_tw.tween_method(func(_v): _apply(), 0.0, 1.0, 0.2)


func _apply() -> void:
	if _style == null:
		return
	var hot := maxf(glow, 1.0 if selected else 0.0)
	_style.border_color = UiKit.LINE.lerp(Color(accent.r, accent.g, accent.b, 1.0), hot)
	_style.set_border_width_all(2 if selected else 1)
	if _title != null:
		_title.add_theme_color_override("font_color", UiKit.INK.lerp(accent.lightened(0.4), hot * 0.6))
	if _art != null and _art.has_meta("icon"):
		(_art.get_meta("icon") as Control).modulate = Color.WHITE.lerp(Color(1.3, 1.2, 1.1), glow)
	modulate = Color(1, 1, 1, 0.45) if disabled else Color.WHITE
	queue_redraw()


## Client look: no halo; a lit edge on hover, and the selected card carries a bar in its accent along the bottom.
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if glow > 0.01 and not selected:
		draw_rect(r, Color(1, 1, 1, 0.035 * glow))
	if selected:
		draw_rect(Rect2(Vector2(0, size.y - 4), Vector2(size.x, 4)), accent)
	if has_focus():
		var f := UiKit.box(Color(0, 0, 0, 0), Color(1, 0.93, 0.75, 0.95), UiKit.CORNER + 2, 2, 0)
		f.draw_center = false
		draw_style_box(f, r.grow(4))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		_apply()
