extends TestBase
## Riot-style client shell: top bar (JUGAR, tabs, back, profile card, settings/quit) over every menu screen but the
## splash, and the home: a news banner carousel, news cards and the champion card, with the friends column.

const SCRATCH := "user://test_shell_settings.cfg"


func _menu() -> MenuScreen:
	SettingsStore.path = SCRATCH
	SettingsStore.clear_shared()
	var m := MenuScreen.new()
	m.offer_tutorial = false
	m.visible = false
	tree.root.add_child(m)
	m.visible = true
	return m


func _drop(m: MenuScreen) -> void:
	tree.root.remove_child(m)
	m.free()
	SettingsStore.path = SettingsStore.PATH
	SettingsStore.clear_shared()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_top_bar_hidden_on_splash_and_navigates() -> void:
	var m := _menu()
	check(not m.top_bar.is_visible_in_tree(), "en el título no hay barra")
	m._input(_key(KEY_SPACE))
	check(m.top_bar.is_visible_in_tree(), "en el inicio sí")
	eq(m.top_bar.active, "hub", "pestaña Inicio activa")
	m.top_bar.play.pressed.emit()
	eq(m.nav.current, "play", "JUGAR abre la pantalla de juego")
	eq(m.top_bar.active, "play", "y JUGAR queda marcado")
	m.top_bar.tab("champions").pressed.emit()
	eq(m.nav.current, "champions", "pestaña Campeones")
	eq(m.top_bar.active, "champions", "marcada")
	m.top_bar.tab("howto").pressed.emit()
	eq(m.nav.current, "howto", "pestaña Cómo jugar")
	m.top_bar.tab("hub").pressed.emit()
	eq(m.nav.current, "hub", "pestaña Inicio vuelve al inicio")
	check(not m.nav.can_back(), "las pestañas no apilan historial infinito: el inicio no tiene Volver")
	m.top_bar.settings.pressed.emit()
	eq(m.nav.current, "settings", "el engranaje abre la configuración")
	_drop(m)


func test_back_button_only_inside_a_flow() -> void:
	var m := _menu()
	m._input(_key(KEY_SPACE))
	check(not m.top_bar.back.visible, "en el inicio no hay Volver")
	m.go("play")
	m.start_flow("practice")
	check(m.top_bar.back.visible, "dentro de un flujo sí")
	m.top_bar.back.pressed.emit()
	eq(m.nav.current, "play", "y vuelve un paso")
	_drop(m)


func test_profile_card_without_and_with_steam() -> void:
	var m := _menu()
	m.st.set_value("name", "Ana")
	m._input(_key(KEY_SPACE))
	check(m.top_bar.name_edit.visible, "sin Steam el nombre se edita")
	eq(m.top_bar.name_edit.text, "Ana", "con el nombre guardado")
	check(m.top_bar.status.text.contains("Sin Steam"), "estado: sin Steam (%s)" % m.top_bar.status.text)
	var net := FakeSteam.new()
	var me := net.user(41, "Reukest")
	var asked := []
	me.avatar_ready.connect(func(id, _t): asked.append(id))
	m.set_steam_backend(me)
	check(not m.top_bar.name_edit.visible and m.top_bar.persona.visible, "con Steam se muestra el nombre de Steam")
	eq(m.top_bar.persona.text, "Reukest", "nombre de Steam")
	eq(m.top_bar.status.text, "En línea", "en línea")
	_drop(m)


func test_home_banner_carousel_and_cards() -> void:
	var m := _menu()
	m._input(_key(KEY_SPACE))
	var news := (m._views.hub as MHub).news
	check(news.items.size() >= 4, "hay noticias para el carrusel (%d)" % news.items.size())
	eq(news.featured, 0, "arranca con la más nueva")
	eq(news.banner_title.text, str(news.items[0].title), "el banner muestra su título")
	check(news.banner_art.texture != null, "con arte de fondo")
	eq(news.cards.size(), NewsPanel.CARDS, "tarjetas debajo")
	news.cards[0].pressed.emit()
	check(news.featured != 0, "una tarjeta pasa al banner")
	eq(news.banner_title.text, str(news.items[news.featured].title), "y el banner cambia")
	news.featured = news.items.size() - 1
	news.advance()
	eq(news.featured, 0, "el carrusel da la vuelta")
	news.dots[2].pressed.emit()
	eq(news.featured, 2, "los puntos eligen la noticia")
	_drop(m)


func test_news_art_for_every_item() -> void:
	for it in NewsFeed.load_bundled():
		var a := NewsPanel.art_for(it, 0)
		check(GameMap.IDS.has(a.map), "mapa válido para %s (%s)" % [it.id, a.map])
		check(GameData.playable(a.champion), "campeón jugable para %s (%s)" % [it.id, a.champion])
	var fallback := NewsPanel.art_for({"id": "x"}, 3)
	check(GameMap.IDS.has(fallback.map) and GameData.playable(fallback.champion), "una noticia sin arte recibe uno")


func test_friends_column_only_on_home() -> void:
	var m := _menu()
	m._input(_key(KEY_SPACE))
	var hub := m._views.hub as MHub
	check(hub.social.is_visible_in_tree(), "la columna de amigos está en el inicio")
	m.debug_goto("settings")  # instant, without the slide animation
	check(not hub.social.is_visible_in_tree(), "en las demás pantallas no tapa su contenido")
	_drop(m)
