class_name MHub
extends MenuView
## Home of the client (Riot-style, under the top bar): the news banner carousel and cards, the champion card next to
## them, and the friends column on the right edge. JUGAR, the tabs, settings and quit live in the top bar.

const PAD := 24.0

var news: NewsPanel
var social: SocialPanel
var dm_window: DmWindow

var _champ: Button
var _chip_art: TextureRect
var _chip_name: Label
var _chip_role: Label


func _ready() -> void:
	news = NewsPanel.new()
	news.menu = menu
	news.position = Vector2(PAD, TopBar.HEIGHT + PAD)
	add_child(news)
	social = SocialPanel.new()
	social.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	social.offset_left = -TopBar.SIDE
	social.offset_top = TopBar.HEIGHT
	social.join_pressed.connect(func(id): menu.steam_join.emit(id))
	social.notice.connect(menu.set_status)
	add_child(social)
	dm_window = DmWindow.new()
	dm_window.menu = menu
	dm_window.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	# above the key hints at the bottom; added last in _ready so it draws over the cards
	dm_window.position = Vector2(-TopBar.SIDE - 12 - DmWindow.W, -56 - DmWindow.H)
	social.friend_pressed.connect(dm_window.open)
	social.friends_refreshed.connect(_on_friends_refreshed)
	menu.steam_changed.connect(func():
		_bind_dm()
		social.bind(menu.steam_backend))
	_bind_dm()
	_build_champion_card()
	add_child(dm_window)
	resized.connect(_layout)
	_layout()


var _bound_dm: DirectChat = null


func _bind_dm() -> void:
	if menu.dm == _bound_dm:
		return
	_bound_dm = menu.dm
	social.dm = menu.dm
	if menu.dm != null:
		menu.dm.changed.connect(dm_window.on_changed)
		menu.dm.received.connect(_on_message)


## A message from a friend whose chat is not open: a short notice (the card also shows the unread count).
func _on_message(from: int, text: String) -> void:
	if dm_window.visible and dm_window.friend_id == from:
		return
	UiSound.play("uiConfirm")
	if is_visible_in_tree():
		menu.set_status("Mensaje de %s: %s" % [menu.steam_backend.persona_of(from), text])


## Keeps the open chat in step with the friend's state (they opened or closed the game).
func _on_friends_refreshed(friends: Array) -> void:
	if not dm_window.visible:
		return
	for f in friends:
		if int(f.id) == dm_window.friend_id:
			dm_window.refresh_friend(f)


func _layout() -> void:
	news.size = Vector2(size.x - TopBar.SIDE - PAD * 2, NewsPanel.BANNER_H + NewsPanel.GAP + NewsPanel.CARD_H)
	var w := news.card_width()
	_champ.position = news.position + Vector2(w * NewsPanel.CARDS + NewsPanel.GAP * NewsPanel.CARDS, NewsPanel.BANNER_H + NewsPanel.GAP)
	_champ.size = Vector2(w, NewsPanel.CARD_H)


## "Tu campeón": bust, name and roles; opens the champion screen.
func _build_champion_card() -> void:
	_champ = Button.new()
	_champ.focus_mode = Control.FOCUS_ALL
	_champ.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_champ.clip_contents = true
	_champ.add_theme_stylebox_override("normal", UiKit.box(Color(0.045, 0.028, 0.022, 0.92), UiKit.LINE, 4, 1, 0))
	_champ.add_theme_stylebox_override("hover", UiKit.box(Color(0.08, 0.045, 0.03, 0.95), UiKit.LINE_STRONG, 4, 1, 0))
	_champ.add_theme_stylebox_override("pressed", UiKit.box(Color(0.08, 0.045, 0.03, 0.95), UiKit.GOLD, 4, 1, 0))
	_champ.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0), UiKit.GOLD, 4, 2, 0))
	_champ.pressed.connect(func(): menu.go_tab("champions"))
	add_child(_champ)
	_chip_art = TextureRect.new()
	_chip_art.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_chip_art.offset_left = -150
	_chip_art.offset_top = 6
	_chip_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chip_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_chip_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_champ.add_child(_chip_art)
	var tc := VBoxContainer.new()
	tc.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	tc.offset_left = 18
	tc.offset_right = 170
	tc.alignment = BoxContainer.ALIGNMENT_CENTER
	tc.add_theme_constant_override("separation", 2)
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_champ.add_child(tc)
	var cap := UiKit.caption("Tu campeón", UiKit.GOLD, 11)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(cap)
	_chip_name = UiKit.heading("", 30, UiKit.INK, 700, 1)
	_chip_role = UiKit.label("", 13, UiKit.MUTED)
	_chip_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_role.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(_chip_name)
	tc.add_child(_chip_role)
	var change := UiKit.caption("Cambiar  >", UiKit.LAVA, 12)
	change.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(change)


## First launch: a small skippable card offers the tutorial once (persisted in settings; "Cómo jugar" replays it any time).
var _offer: PanelContainer


func offer_visible() -> bool:
	return _offer != null and _offer.visible


func _maybe_offer() -> void:
	if not menu.offer_tutorial or bool(menu.st.get_value("tutorial_seen")) or offer_visible():
		return
	if _offer == null:
		_offer = UiKit.glass(UiKit.LINE_STRONG, 14, 18, 3.0, 0.8)
		# top right of the banner, over the champion splash (first launch only)
		_offer.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_offer.position = Vector2(-TopBar.SIDE - PAD - 16 - 430, TopBar.HEIGHT + PAD + 16)
		_offer.custom_minimum_size = Vector2(430, 0)
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 8)
		_offer.add_child(c)
		c.add_child(UiKit.heading("¿Primera vez en la arena?", 22, UiKit.GOLD, 700, 1))
		var t := UiKit.label("Hacé el tutorial: unos minutos, jugando de verdad. Después lo encontrás en \"Cómo jugar\".", 14, UiKit.MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(390, 0)
		c.add_child(t)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		c.add_child(row)
		var yes := MButton.new("Hacer el tutorial", "accent")
		yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		yes.pressed.connect(func():
			_offer.visible = false
			menu.launch_tutorial())
		var no := MButton.new("Ahora no", "ghost")
		no.pressed.connect(dismiss_offer)
		row.add_child(yes)
		row.add_child(no)
		add_child(_offer)
	_offer.visible = true


## "Ahora no": hides the card and remembers it was offered, so it does not come back on its own.
func dismiss_offer() -> void:
	if _offer != null:
		_offer.visible = false
	menu.st.set_value("tutorial_seen", true)
	menu.st.save()



func menu_enter() -> void:
	_maybe_offer()
	news.show_news()
	social.bind(menu.steam_backend)
	var cls := str(menu.st.get_value("cls"))
	var spec: Dictionary = GameData.classes[cls]
	_chip_art.texture = Portraits.bust(cls)
	_chip_name.text = str(spec.name)
	_chip_role.text = ", ".join(spec.tags)


func first_focus() -> Control:
	return menu.top_bar.play


func hints() -> Array:
	return [["Flechas", "Navegar"], ["Enter", "Aceptar"]]
