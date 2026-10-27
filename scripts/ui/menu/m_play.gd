class_name MPlay
extends MenuView
## "Jugar": big mode cards (practice / host / join / Steam).

var _cards := {}
var _steam_panel: PanelContainer
var _privacy: Segmented


func _ready() -> void:
	header("Jugar", "Elegí cómo querés pelear.")
	var row := HBoxContainer.new()
	row.position = Vector2(72, 200)
	row.custom_minimum_size = Vector2(1136, 330)
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var defs := [
		["practice", "ui_sword", "Contra bots", "Peleá contra bots en cualquier arena. Sin conexión ni cuentas.", UiKit.LAVA],
		["arena", "ui_target", "Arena de práctica", "Muñecos y medidor de daño para practicar rotaciones.", UiKit.GREEN],
		["host", "ui_people", "Crear partida", "Sos el anfitrión: tus amigos entran con tu IP y puerto.", UiKit.GOLD],
		["join", "ui_globe", "Unirse", "Entrá a la partida de un amigo con su dirección.", UiKit.BLUE],
		["steam", "ui_steam", "Steam", "Salas por Steam: invitá o buscá partidas sin abrir puertos.", Color("#66c0f4")],
	]
	for d in defs:
		var c := Card.new(d[1], d[2], d[3], d[4])
		c.custom_minimum_size = Vector2(210, 330)
		c.set_title_size(28)
		c.set_art_height(140)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)
		_cards[d[0]] = c
	_cards.practice.pressed.connect(func(): menu.start_flow("practice"))
	_cards.arena.pressed.connect(func(): menu.start_flow("arena"))
	_cards.host.pressed.connect(func(): menu.start_flow("host"))
	_cards.join.pressed.connect(func(): menu.start_flow("join"))
	_cards.steam.pressed.connect(_toggle_steam)
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


func _toggle_steam() -> void:
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


func menu_enter() -> void:
	_refresh_steam()
	_steam_panel.visible = false
	_cards.steam.selected = false


func first_focus() -> Control:
	return _cards.practice


func hints() -> Array:
	return [["Flechas", "Navegar"], ["Enter", "Elegir"], ["Esc", "Volver"]]


func section() -> String:
	return "Jugar"
