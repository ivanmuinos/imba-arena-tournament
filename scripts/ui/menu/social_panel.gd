class_name SocialPanel
extends PanelContainer
## Right-hand panel of the home screen: Steam friends grouped (playing Imba Arena / online / offline) with their rich
## presence, and per friend Unirse (their lobby has room), Chat and Perfil (both in the Steam overlay).
## Without Steam it only explains why. Grouping and texts come from Social (unit tested).

signal join_pressed(lobby_id: int)
## The friend's card was clicked: open the in-client chat with them.
signal friend_pressed(friend: Dictionary)
## The list was rebuilt with fresh friend data.
signal friends_refreshed(friends: Array)
## A short explanation for the player (e.g. the overlay could not open).
signal notice(text: String)

const AVATAR := 30

## One row per friend shown, in display order (tests read these).
var rows: Array[Row] = []
var message: Label
var add_button: MButton
## In-client chat: unread counts on the cards (set by the home).
var dm: DirectChat = null:
	set(v):
		if dm != null and dm.changed.is_connected(_on_dm):
			dm.changed.disconnect(_on_dm)
		dm = v
		if dm != null:
			dm.changed.connect(_on_dm)

var _backend: SteamBackend = null
var _list: VBoxContainer
var _count: Label
var _avatars := {}  # steam_id -> Texture2D
var _asked := {}    # steam_id -> true once its avatar was requested


## A friend's card: the whole card is a button (opens the chat); Unirse and Perfil are buttons inside it.
class Row:
	extends Button
	var friend: Dictionary
	var box: HBoxContainer
	var avatar: TextureRect
	var badge: Label
	var join: MButton
	var profile: MButton


func _init() -> void:
	# A flat column docked to the right edge under the profile card (client style), not a floating card.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.022, 0.018, 0.93)
	sb.border_color = UiKit.LINE
	sb.border_width_left = 1
	sb.content_margin_left = 16
	sb.content_margin_right = 14
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var title := UiKit.caption("Amigos", UiKit.LAVA, 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count = UiKit.label("", 13, UiKit.MUTED)
	head.add_child(_count)
	message = UiKit.label("", 14, UiKit.MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(message)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	add_button = MButton.new("Agregar amigos", "ghost", "ui_plus")
	add_button.add_theme_font_size_override("font_size", 15)
	add_button.pressed.connect(func(): _overlay("friends", 0))
	col.add_child(add_button)


## Called when Steam becomes known (or changes): listens to its friend updates and avatars.
func bind(backend: SteamBackend) -> void:
	if _backend == backend:
		refresh()
		return
	if _backend != null:
		_backend.friends_changed.disconnect(_on_changed)
		_backend.avatar_ready.disconnect(_on_avatar)
	_backend = backend
	if _backend != null:
		_backend.friends_changed.connect(_on_changed)
		_backend.avatar_ready.connect(_on_avatar)
	refresh()


func refresh() -> void:
	rows.clear()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var ok := _backend != null and _backend.available()
	message.visible = not ok
	add_button.visible = ok
	if not ok:
		message.text = "Conectate a Steam para ver a tus amigos y unirte a sus salas.\n%s" % (_backend.status_text() if _backend != null else "Steam no disponible")
		_count.text = ""
		return
	var app := _backend.app_id()
	var all := _backend.friends()
	var groups := Social.group(all, app)
	var online := all.filter(func(f): return int(f.state) != 0).size()
	_count.text = "%d en línea" % online
	friends_refreshed.emit(all)
	if groups.is_empty():
		message.visible = true
		message.text = "Todavía no tenés amigos en Steam. Agregalos desde \"Agregar amigos\"."
	for g in groups:
		var cap := UiKit.caption("%s  %d" % [g.title, g.items.size()], UiKit.DIM, 11)
		_list.add_child(cap)
		for f in g.items:
			var r := _row(f, app, g.key)
			rows.append(r)
			_list.add_child(r)


func _row(f: Dictionary, app: int, group_key: String) -> Row:
	var r := Row.new()
	r.friend = f
	r.focus_mode = Control.FOCUS_ALL
	r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	r.custom_minimum_size = Vector2(0, 44)
	r.tooltip_text = "Chatear con %s" % f.name
	r.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	r.add_theme_stylebox_override("hover", UiKit.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), UiKit.CORNER, 0, 0))
	r.add_theme_stylebox_override("pressed", UiKit.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), UiKit.CORNER, 0, 0))
	r.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0), UiKit.GOLD, UiKit.CORNER, 1, 0))
	r.pressed.connect(func(): friend_pressed.emit(r.friend))
	r.modulate.a = 0.55 if group_key == "offline" else 1.0
	r.box = HBoxContainer.new()
	r.box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.box.offset_left = 4
	r.box.offset_right = -2
	r.box.add_theme_constant_override("separation", 8)
	r.box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(r.box)
	r.avatar = TextureRect.new()
	r.avatar.custom_minimum_size = Vector2(AVATAR, AVATAR)
	r.avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id := int(f.id)
	if _avatars.has(id):
		r.avatar.texture = _avatars[id]
	else:
		r.avatar.texture = Icons.tex("ui_user")
		r.avatar.modulate = UiKit.MUTED
		if not _asked.has(id):
			_asked[id] = true
			_backend.request_avatar(id)
	r.avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.box.add_child(r.avatar)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", -2)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := UiKit.heading(str(f.name), 16, UiKit.INK, 600, 0)
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(name)
	var state := UiKit.label(Social.state_text(f, app), 12, UiKit.GREEN if group_key == "playing" else UiKit.MUTED)
	state.clip_text = true
	state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(state)
	r.box.add_child(texts)
	r.badge = UiKit.heading("", 12, Color("#1a0800"), 700, 0, HORIZONTAL_ALIGNMENT_CENTER)
	r.badge.add_theme_stylebox_override("normal", UiKit.box(UiKit.LAVA, Color(0, 0, 0, 0), 9, 0, 0))
	r.badge.custom_minimum_size = Vector2(20, 18)
	r.badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.box.add_child(r.badge)
	_set_badge(r)
	r.join = _small("Unirse", "", "Entrar a su sala")
	r.join.visible = Social.can_join(f, app)
	r.join.add_theme_color_override("font_color", UiKit.GOLD)
	r.join.pressed.connect(func(): join_pressed.emit(int(r.friend.lobby)))
	r.box.add_child(r.join)
	r.profile = _small("", "ui_user", "Ver su perfil de Steam")
	r.profile.pressed.connect(func(): _overlay("steamid", int(r.friend.id)))
	r.box.add_child(r.profile)
	return r


## Unread private messages from that friend (DirectChat), as a small count on the card.
func _set_badge(r: Row) -> void:
	var n := dm.unread_of(int(r.friend.id)) if dm != null else 0
	r.badge.text = str(n) if n < 100 else "99+"
	r.badge.visible = n > 0


func update_badges() -> void:
	for r in rows:
		_set_badge(r)


func _overlay(kind: String, steam_id: int) -> void:
	if _backend != null and not _backend.open_overlay(kind, steam_id):
		notice.emit(Social.overlay_note(kind))


func _small(text: String, icon_id: String, tip: String) -> MButton:
	var b := MButton.new(text, "ghost", icon_id)
	b.custom_minimum_size = Vector2(30 if text == "" else 0, 28)
	b.add_theme_font_size_override("font_size", 13)
	b.tooltip_text = tip
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## The backend coalesces Steam's bursts of persona updates into one signal per frame.
func _on_changed() -> void:
	refresh()


func _on_dm(_friend_id: int) -> void:
	update_badges()


func _on_avatar(steam_id: int, tex: Texture2D) -> void:
	_avatars[steam_id] = tex
	for r in rows:
		if int(r.friend.id) == steam_id:
			r.avatar.texture = tex
			r.avatar.modulate = Color.WHITE
