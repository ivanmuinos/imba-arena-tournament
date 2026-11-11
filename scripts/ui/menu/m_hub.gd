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
var _chip_level: Label
var _chip_xp: ColorRect
var _cont: Button
var _cont_tier: Label
var _cont_next: Label


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
	social.invite_pressed.connect(func(friend): menu.invite_friend(friend))
	menu.online_changed.connect(func(): social.invite_enabled = menu.online_ready())
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
	_build_continue_card()
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
	_cont.position = news.position + Vector2(w + NewsPanel.GAP, NewsPanel.BANNER_H + NewsPanel.GAP)  # over the second news card
	_cont.size = Vector2(w, NewsPanel.CARD_H)


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
	# account level and XP along the bottom of the card
	_chip_level = UiKit.caption("", UiKit.GOLD, 11)
	_chip_level.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_chip_level.offset_left = 18
	_chip_level.offset_top = -30
	_chip_level.offset_bottom = -12
	_chip_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_champ.add_child(_chip_level)
	var xp_bg := ColorRect.new()
	xp_bg.color = Color(1, 1, 1, 0.1)
	xp_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	xp_bg.offset_top = -5
	xp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_champ.add_child(xp_bg)
	_chip_xp = ColorRect.new()
	_chip_xp.color = UiKit.GOLD
	_chip_xp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chip_xp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bg.add_child(_chip_xp)


## "Continuar torneo": shown over the second news card while a cup is in progress; opens the next match straight away.
func _build_continue_card() -> void:
	_cont = Button.new()
	_cont.focus_mode = Control.FOCUS_ALL
	_cont.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_cont.clip_contents = true
	_cont.visible = false
	_cont.add_theme_stylebox_override("normal", UiKit.box(Color(0.06, 0.04, 0.022, 1.0), UiKit.GOLD, 4, 1, 0))
	_cont.add_theme_stylebox_override("hover", UiKit.box(Color(0.1, 0.06, 0.03, 1.0), UiKit.GOLD, 4, 2, 0))
	_cont.add_theme_stylebox_override("pressed", UiKit.box(Color(0.1, 0.06, 0.03, 1.0), UiKit.GOLD, 4, 2, 0))
	_cont.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0), UiKit.GOLD, 4, 2, 0))
	_cont.pressed.connect(func(): menu.resume_tournament())
	add_child(_cont)
	var tc := VBoxContainer.new()
	tc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tc.offset_left = 18
	tc.offset_right = -14
	tc.alignment = BoxContainer.ALIGNMENT_CENTER
	tc.add_theme_constant_override("separation", 3)
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cont.add_child(tc)
	var cap := UiKit.caption("Torneo en curso", UiKit.GOLD, 11)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(cap)
	_cont_tier = UiKit.heading("", 28, UiKit.INK, 700, 1)
	_cont_tier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(_cont_tier)
	_cont_next = UiKit.label("", 14, UiKit.MUTED)
	_cont_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cont_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(_cont_next)
	var go := UiKit.caption("Continuar  >", UiKit.LAVA, 12)
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(go)


## First launch: a small skippable card offers the tutorial once (persisted in settings; "Cómo jugar" replays it any time).
var offer_button: MButton
var _offer: PanelContainer


func offer_visible() -> bool:
	return _offer != null and _offer.visible


func _maybe_offer() -> void:
	if not menu.offer_tutorial or bool(menu.st.get_value("tutorial_seen")) or AcademyStore.shared().offered or offer_visible():
		return
	if _offer == null:
		_offer = UiKit.glass(UiKit.LINE_STRONG, 14, 18, 3.0, 0.8)
		# top right of the banner, over the champion splash (first launch only)
		_offer.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_offer.position = Vector2(-TopBar.SIDE - PAD - 16 - 470, TopBar.HEIGHT + PAD + 16)
		_offer.custom_minimum_size = Vector2(470, 0)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		_offer.add_child(line)
		var face := TizonFace.new(84.0, "contenta")
		face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(face)
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 8)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(c)
		c.add_child(UiKit.heading("¿Primera vez en la arena?", 22, UiKit.GOLD, 700, 1))
		var t := UiKit.label("Soy Tizón. Te espero en el Valle de Brasas: %d misiones cortas con tu campeón, jugando de verdad, y una medalla en cada una." % AcademyCatalog.total(), 14, UiKit.MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(330, 0)
		c.add_child(t)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		c.add_child(row)
		offer_button = MButton.new("Ir al valle", "accent")
		offer_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		offer_button.pressed.connect(func():
			_offer.visible = false
			menu.launch_valley())
		var no := MButton.new("Ya sé jugar", "ghost")
		no.pressed.connect(dismiss_offer)
		row.add_child(offer_button)
		row.add_child(no)
		add_child(_offer)
	_offer.visible = true


## "Ahora no": hides the card and remembers it was offered, so it does not come back on its own.
func dismiss_offer() -> void:
	if _offer != null:
		_offer.visible = false
	menu.st.set_value("tutorial_seen", true)
	menu.st.save()
	AcademyStore.shared().mark_offered()
	AcademyStore.shared().save()



func menu_enter() -> void:
	_maybe_offer()
	news.show_news()
	social.bind(menu.steam_backend)
	var cls := str(menu.st.get_value("cls"))
	var spec: Dictionary = GameData.classes[cls]
	_chip_art.texture = Portraits.bust(cls)
	_chip_name.text = str(spec.name)
	_chip_role.text = ", ".join(spec.tags)
	menu.profile.load_file()
	var prog := menu.profile.progress()
	_chip_level.text = "NIVEL %d" % prog.level if prog.maxed else "NIVEL %d · %d / %d XP" % [prog.level, prog.into, prog.need]
	_chip_xp.anchor_right = 1.0 if prog.maxed else clampf(float(prog.into) / maxf(1.0, float(prog.need)), 0.0, 1.0)
	menu.tstore.load_file()
	var line := TournamentInfo.continue_text(menu.tstore)
	_cont.visible = line != ""
	if line != "":
		var parts := line.split(" · ")
		_cont_tier.text = parts[0]
		_cont_next.text = parts[1] if parts.size() > 1 else ""


func first_focus() -> Control:
	return menu.top_bar.play


func hints() -> Array:
	return [["Flechas", "Navegar"], ["Enter", "Aceptar"]]
