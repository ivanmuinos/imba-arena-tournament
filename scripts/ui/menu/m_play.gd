class_name MPlay
extends MenuView
## "Jugar": big mode cards (vs bots / practice yard / host / join / tournament / Steam).

var _cards := {}
var _steam_panel: PanelContainer
var _privacy: Segmented
var _online_panel: PanelContainer
var _q_mode: Segmented
var _q_who: Segmented
var _q_button: MButton
var _q_note: Label


func _ready() -> void:
	header("Jugar", "Elegí cómo querés pelear.")
	var row := HBoxContainer.new()
	row.position = Vector2(72, 200)
	row.custom_minimum_size = Vector2(1136, 330)
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var defs := [
		["practice", "ui_sword", "Contra bots", "Peleá contra bots en cualquier arena, sin conexión.", UiKit.LAVA],
		["arena", "ui_target", "Arena de práctica", "Muñecos y medidor de daño para practicar.", UiKit.GREEN],
		["host", "ui_people", "Crear partida", "Sos el anfitrión: tus amigos entran con tu IP y puerto.", UiKit.GOLD],
		["join", "ui_globe", "Unirse", "Entrá a la partida de un amigo con su dirección.", UiKit.BLUE],
		["tournament", "ui_star", "Torneo", "Copas de 8 equipos contra bots, desafíos y recompensas.", UiKit.GOLD],
		["steam", "ui_steam", "Steam", "Salas por Steam: invitá o buscá partidas sin abrir puertos.", Color("#66c0f4")],
		["online", "ui_globe", "En línea", "Buscá una partida contra otros jugadores: solo, en grupo o con tu equipo.", UiKit.GREEN],
	]
	for d in defs:
		var c := Card.new(d[1], d[2], d[3], d[4])
		c.custom_minimum_size = Vector2(140, 330)
		c.set_title_size(24)
		c.set_art_height(140)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)
		_cards[d[0]] = c
	_cards.practice.pressed.connect(func(): menu.start_flow("practice"))
	_cards.arena.pressed.connect(func(): menu.start_flow("arena"))
	_cards.host.pressed.connect(func(): menu.start_flow("host"))
	_cards.join.pressed.connect(func(): menu.start_flow("join"))
	_cards.tournament.pressed.connect(func(): menu.go("tournament"))
	_cards.steam.pressed.connect(_toggle_steam)
	_cards.online.pressed.connect(_toggle_online)
	_cards.online.visible = false  # only with the online features (MenuScreen.set_online)
	# Steam sub-options
	_steam_panel = UiKit.glass(Color("#66c0f4"), 12, 14, 3.0, 0.7)
	_steam_panel.position = Vector2(72, 556)
	_steam_panel.custom_minimum_size = Vector2(1136, 0)
	_steam_panel.visible = false
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 14)
	_steam_panel.add_child(sr)
	var cap := UiKit.heading("STEAM", 20, Color("#66c0f4"), 700, 3)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sr.add_child(cap)
	_privacy = Segmented.new().setup([["friends", "Sólo amigos"], ["public", "Pública"]], "friends")
	_privacy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sr.add_child(_privacy)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(sp)
	var create := MButton.new("Crear sala", "steam")
	create.custom_minimum_size = Vector2(190, 46)
	var find := MButton.new("Buscar salas", "secondary")
	find.custom_minimum_size = Vector2(190, 46)
	sr.add_child(create)
	sr.add_child(find)
	create.pressed.connect(func():
		menu.st.set_value("steam_friends", _privacy.value == "friends")
		menu.start_flow("steam_host"))
	find.pressed.connect(func(): menu.start_flow("steam_browse"))
	add_child(_steam_panel)
	menu.steam_changed.connect(_refresh_steam)
	_build_online_panel()
	menu.online_changed.connect(_refresh_online)


func _toggle_steam() -> void:
	_online_panel.visible = false
	_cards.online.selected = false
	_steam_panel.visible = not _steam_panel.visible
	_cards.steam.selected = _steam_panel.visible
	if _steam_panel.visible:
		_steam_panel.get_child(0).get_child(3).grab_focus()


func _refresh_steam() -> void:
	var c: Card = _cards.steam
	c.disabled = not menu.steam_ok
	c.set_subtitle("Salas por Steam: invitá o buscá partidas sin abrir puertos." if menu.steam_ok else menu.steam_text)
	c.set_badge("" if menu.steam_ok else "No disponible")
	c.tooltip_text = "" if menu.steam_ok else menu.steam_text
	if not menu.steam_ok:
		_steam_panel.visible = false
		c.selected = false


func _build_online_panel() -> void:
	_online_panel = UiKit.glass(UiKit.GREEN, 12, 14, 3.0, 0.7)
	_online_panel.position = Vector2(72, 556)
	_online_panel.custom_minimum_size = Vector2(1136, 0)
	_online_panel.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_online_panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var cap := UiKit.heading("EN LÍNEA", 20, UiKit.GREEN, 700, 3)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	_q_mode = Segmented.new().setup([["1", "1v1"], ["2", "2v2"], ["3", "3v3"]], "1")
	_q_mode.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_q_mode.changed.connect(func(_v): _refresh_online())
	row.add_child(_q_mode)
	_q_who = Segmented.new().setup([["solo", "Solo"], ["group", "Con mi grupo"]], "solo")
	_q_who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_q_who)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_q_button = MButton.new("Buscar partida", "accent")
	_q_button.custom_minimum_size = Vector2(220, 46)
	_q_button.pressed.connect(_on_queue_button)
	row.add_child(_q_button)
	_q_note = UiKit.label("", 14, UiKit.MUTED)
	_q_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_q_note)
	add_child(_online_panel)


func _toggle_online() -> void:
	_steam_panel.visible = false
	_cards.steam.selected = false
	_online_panel.visible = not _online_panel.visible
	_cards.online.selected = _online_panel.visible
	_refresh_online()


func _on_queue_button() -> void:
	if menu.queue == null:
		return
	if menu.queue.state != "idle":
		menu.queue_cancel()
		return
	var use_group: bool = _q_who.value == "group"
	var mode := int(_q_mode.value)
	if use_group and menu.queue.in_group():
		mode = int(menu.queue.group.mode)  # a group searches in its own modality
	menu.queue_join(mode, use_group)


## The card and its panel follow the online session and the queue; nothing here touches the network.
func _refresh_online() -> void:
	if _online_panel == null:
		return
	var on: bool = menu.online_session != null
	_cards.online.visible = on
	if not on:
		_online_panel.visible = false
		return
	var ready: bool = menu.online_ready()
	var c: Card = _cards.online
	c.disabled = not ready
	c.set_badge("" if ready else "No disponible")
	c.tooltip_text = "" if ready else menu.online_notice()
	if not ready:
		_online_panel.visible = false
	c.selected = ready and _online_panel.visible  # (re)applies the dimmed look: Card only redraws when selected changes
	if not ready:
		return
	var q: QueueService = menu.queue
	var busy: bool = q != null and q.state != "idle"
	_q_button.text = "Cancelar búsqueda" if busy else "Buscar partida"
	_q_mode.set_locked(busy)
	_q_who.set_locked(busy)
	var note := "Las partidas normales no tienen ranking visible. Podés seguir navegando o jugar contra bots mientras esperás."
	if _q_who.value == "group":
		if q == null or not q.in_group():
			note = "Armá un grupo o un equipo en la pestaña Equipos para buscar juntos."
		else:
			note = "Buscás con tu grupo de %dv%d." % [q.group.mode, q.group.mode]
	_q_note.text = note


func menu_enter() -> void:
	_refresh_steam()
	_refresh_online()
	_steam_panel.visible = false
	_online_panel.visible = false
	_cards.steam.selected = false
	_cards.online.selected = false


func first_focus() -> Control:
	return _cards.practice


func hints() -> Array:
	return [["Flechas", "Navegar"], ["Enter", "Elegir"], ["Esc", "Volver"]]


func section() -> String:
	return "Jugar"
