extends TestBase
## Social home (no backend): Steam friends grouped for the side panel, the rich presence we publish, news from Steam
## (or the bundled file) with a local cache, and the hub wiring against a fake Steam.

const APP := 480
const SCRATCH := "user://test_social_settings.cfg"
const CACHE := "user://test_news_cache.json"


func _friend(id: int, name: String, state: int, app := 0, lobby := 0, status := "") -> Dictionary:
	return {"id": id, "name": name, "state": state, "app": app, "lobby": lobby, "status": status}


# ---------------------------------------------------------------- friends

func test_friends_are_grouped_playing_online_offline_and_sorted_by_name() -> void:
	var list := [
		_friend(1, "zoe", 0),
		_friend(2, "Bruno", 1, APP, 0, "En el menú"),
		_friend(3, "ana", 1),
		_friend(4, "Carla", 3, 730),
		_friend(5, "Ale", 1, APP),
	]
	var groups := Social.group(list, APP)
	eq(groups.map(func(g): return g.key), ["playing", "online", "offline"], "orden de los grupos")
	eq(groups[0].items.map(func(f): return f.name), ["Ale", "Bruno"], "jugando Imba Arena, por nombre")
	eq(groups[1].items.map(func(f): return f.name), ["ana", "Carla"], "en línea (sin distinguir mayúsculas)")
	eq(groups[2].items.map(func(f): return f.name), ["zoe"], "desconectados")
	eq(Social.group([_friend(1, "a", 0)], APP).map(func(g): return g.key), ["offline"], "los grupos vacíos no se muestran")
	eq(Social.group([], APP), [], "sin amigos: nada")


func test_friend_state_text_and_join_rule() -> void:
	eq(Social.state_text(_friend(1, "a", 1, APP, 0, "En sala (2/4)"), APP), "En sala (2/4)", "usa su rich presence")
	eq(Social.state_text(_friend(1, "a", 1, APP), APP), "Jugando Imba Arena", "en el juego sin estado")
	eq(Social.state_text(_friend(1, "a", 1, 730), APP), "En otro juego", "otro juego")
	eq(Social.state_text(_friend(1, "a", 1), APP), "En línea", "en línea")
	eq(Social.state_text(_friend(1, "a", 3), APP), "Ausente", "ausente")
	eq(Social.state_text(_friend(1, "a", 2), APP), "Ocupado", "ocupado")
	eq(Social.state_text(_friend(1, "a", 0), APP), "Desconectado", "desconectado")
	check(Social.can_join(_friend(1, "a", 1, APP, 99), APP), "en una sala de este juego: se puede unir")
	check(not Social.can_join(_friend(1, "a", 1, APP, 0), APP), "sin sala no")
	check(not Social.can_join(_friend(1, "a", 1, 730, 99), APP), "sala de otro juego no")


func test_rich_presence_per_place() -> void:
	eq(Social.presence({"where": "menu"}), {"status": "En el menú", "connect": ""}, "menú")
	eq(Social.presence({"where": "practice"}).status, "En la arena de práctica", "práctica")
	var lobby := Social.presence({"where": "lobby", "lobby": 1234, "members": 2, "max": 4})
	eq(lobby, {"status": "En sala (2/4)", "connect": "+connect_lobby 1234"}, "sala con lugar: se puede unir desde Steam")
	eq(Social.presence({"where": "lobby", "lobby": 1234, "members": 4, "max": 4}).connect, "", "sala llena: sin unirse")
	eq(Social.presence({"where": "match", "mode": 3, "map_name": "Tumba del Titán"}), {"status": "En partida 3v3 · Tumba del Titán", "connect": ""}, "partida")
	eq(Social.presence({"where": "match", "mode": 2}).status, "En partida 2v2", "partida sin mapa")
	eq(Social.presence({}).status, "En el menú", "por defecto, el menú")


func test_fake_steam_friends_see_each_other_and_presence() -> void:
	var net := FakeSteam.new()
	var ana := net.user(11, "Ana")
	var beto := net.user(12, "Beto")
	var caro := net.user(13, "Caro")
	net.befriend(11, 12)
	net.befriend(11, 13)
	caro.online = false
	eq(ana.friends().map(func(f): return f.name), ["Beto", "Caro"], "amigos de Ana")
	eq(beto.friends().map(func(f): return f.name), ["Ana"], "la amistad es mutua")
	var changed := [0]
	ana.friends_changed.connect(func(): changed[0] += 1)
	beto.set_presence({"status": "En el menú", "connect": ""})
	ana.run_callbacks()
	eq(changed[0], 1, "Ana se entera del cambio")
	var b: Dictionary = ana.friends().filter(func(f): return f.id == 12)[0]
	eq([b.state, b.app, b.status], [1, APP, "En el menú"], "Beto en línea, en el juego, con su estado")
	var c: Dictionary = ana.friends().filter(func(f): return f.id == 13)[0]
	eq([c.state, c.app], [0, 0], "Caro desconectada")
	beto.create_lobby(true, 4)
	beto.run_callbacks()
	b = ana.friends().filter(func(f): return f.id == 12)[0]
	check(int(b.lobby) != 0, "Beto en una sala: Ana la ve")
	ana.open_overlay("chat", 12)
	eq(ana.overlay_calls, [["chat", 12]], "abre la superposición")


# ---------------------------------------------------------------- news

const STEAM_JSON := """{"appnews": {"appid": 480, "newsitems": [
	{"gid": "100", "title": "Parche 0.7.0", "url": "https://store.steampowered.com/news/100", "contents": "[img]{STEAM_CLAN_IMAGE}/x.png[/img][b]Novedades[/b]: nuevo [url=https://x.y]mapa[/url].\\n\\nMás balance.", "date": 1761400000, "feedname": "steam_community_announcements", "tags": ["patchnotes"]},
	{"gid": "99", "title": "Torneo de octubre", "url": "https://store.steampowered.com/news/99", "contents": "Inscribite ya", "date": 1761000000, "feedname": "steam_community_announcements"}
]}}"""


func test_parse_steam_news_cleans_markup_and_tags_patches() -> void:
	var items := NewsFeed.parse_steam(STEAM_JSON)
	eq(items.size(), 2, "dos noticias")
	eq(items[0].id, "100", "id")
	eq(items[0].title, "Parche 0.7.0", "título")
	eq(items[0].body, "Novedades: nuevo mapa. Más balance.", "sin BBCode, imágenes ni saltos dobles")
	eq(items[0].tag, "Parche", "las notas de parche se marcan")
	eq(items[1].tag, "Noticia", "el resto es noticia")
	eq(items[0].url, "https://store.steampowered.com/news/100", "enlace")
	eq(items[0].date, 1761400000, "fecha")
	eq(NewsFeed.parse_steam("no es json"), [], "basura: nada")
	eq(NewsFeed.parse_steam("{}"), [], "sin noticias: nada")
	check(NewsFeed.clean("x".repeat(500)).length() <= NewsFeed.MAX_BODY + 1, "el cuerpo se recorta")


func test_bundled_news_load_and_newest_first() -> void:
	var items := NewsFeed.parse_local("""[{"id": "a", "title": "Vieja", "body": "x", "date": "2026-01-02"}, {"id": "b", "title": "Nueva", "body": "y", "date": "2026-10-20", "tag": "Parche"}]""")
	eq(items.map(func(i): return i.title), ["Nueva", "Vieja"], "más nueva primero")
	eq(items[0].tag, "Parche", "respeta la etiqueta")
	eq(items[1].tag, "Noticia", "etiqueta por defecto")
	check(int(items[0].date) > int(items[1].date), "fecha como número")
	var bundled := NewsFeed.load_bundled()
	check(bundled.size() >= 3, "el juego trae noticias propias (%d)" % bundled.size())
	check(bundled.all(func(i): return str(i.title) != "" and str(i.id) != ""), "todas con id y título")


func test_news_source_order_and_cache() -> void:
	var remote := [{"id": "r", "title": "R", "body": "", "date": 3, "tag": "Noticia", "url": ""}]
	var cache := [{"id": "c", "title": "C", "body": "", "date": 2, "tag": "Noticia", "url": ""}]
	var bundled := [{"id": "b", "title": "B", "body": "", "date": 1, "tag": "Noticia", "url": ""}]
	eq(NewsFeed.pick(remote, cache, bundled)[0].id, "r", "primero lo descargado")
	eq(NewsFeed.pick([], cache, bundled)[0].id, "c", "sin red: la caché")
	eq(NewsFeed.pick([], [], bundled)[0].id, "b", "sin nada: las del juego")
	check(NewsFeed.save_cache(remote, CACHE), "se guarda la caché")
	eq(NewsFeed.load_cache(CACHE), remote, "y se lee igual")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE))
	eq(NewsFeed.load_cache(CACHE), [], "sin archivo: vacía")
	check(not NewsFeed.remote_enabled(480), "con el app id de prueba no se descarga")
	check(not NewsFeed.remote_enabled(0), "sin Steam tampoco")
	check(NewsFeed.remote_enabled(3412345), "con el app id propio sí")
	check(NewsFeed.url(3412345).contains("appid=3412345"), "la URL lleva el app id")


func test_unseen_news_and_seen_setting() -> void:
	var items := [{"id": "a"}, {"id": "b"}, {"id": "c"}]
	eq(NewsFeed.unseen(items, ["b"]), ["a", "c"], "nuevas = las no vistas")
	SettingsStore.path = SCRATCH
	SettingsStore.clear_shared()
	var st := SettingsStore.new()
	eq(st.get_value("news_seen"), [], "por defecto ninguna vista")
	st.set_value("news_seen", ["a", 3, "b", "a"])
	eq(st.get_value("news_seen"), ["a", "3", "b"], "texto, sin repetidas")
	var many := []
	for i in 80:
		many.append(str(i))
	eq(st.set_value("news_seen", many).size(), NewsFeed.SEEN_KEEP, "se guardan las últimas")
	eq(st.set_value("news_seen", "x"), [], "basura: vacía")
	SettingsStore.path = SettingsStore.PATH
	SettingsStore.clear_shared()


# ---------------------------------------------------------------- hub

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


func test_hub_shows_friends_and_join_emits_the_lobby() -> void:
	var net := FakeSteam.new()
	var me := net.user(21, "Yo")
	var amigo := net.user(22, "Amigo")
	net.befriend(21, 22)
	amigo.create_lobby(true, 4)
	amigo.run_callbacks()
	var lobby_id: int = net.lobbies.keys()[0]
	var m := _menu()
	m.set_steam_backend(me)
	m._input(_key(KEY_SPACE))
	var panel := (m._views.hub as MHub).social
	eq(panel.rows.size(), 1, "una fila por amigo")
	eq(panel.rows[0].friend.name, "Amigo", "con su nombre")
	check(panel.rows[0].join != null and panel.rows[0].join.visible, "está en una sala: botón Unirse")
	var got := []
	m.steam_join.connect(func(id): got.append(id))
	panel.rows[0].join.pressed.emit()
	eq(got, [lobby_id], "Unirse pide entrar a su sala")
	amigo.leave_lobby(lobby_id)
	amigo.set_presence({"status": "En el menú", "connect": ""})
	me.run_callbacks()
	check(not panel.rows[0].join.visible, "sin sala ya no hay Unirse")
	_drop(m)


func test_overlay_buttons_explain_when_there_is_no_overlay() -> void:
	var net := FakeSteam.new()
	var me := net.user(31, "Yo")
	var amigo := net.user(32, "Amigo")
	net.befriend(31, 32)
	me.overlay = false  # like the simulated Steam
	var m := _menu()
	m.set_steam_backend(me)
	m._input(_key(KEY_SPACE))
	var panel := (m._views.hub as MHub).social
	panel.add_button.pressed.emit()
	check(m.status.text.contains("amigos"), "Agregar amigos explica qué pasa (%s)" % m.status.text)
	panel.rows[0].profile.pressed.emit()
	check(m.status.text.contains("perfil"), "y Perfil (%s)" % m.status.text)
	me.overlay = true
	m.set_status("")
	panel.add_button.pressed.emit()
	eq(m.status.text, "", "con la superposición de Steam no hace falta aviso")
	eq(me.overlay_calls.back(), ["friends", 0], "y la abre")
	_drop(m)


func test_overlay_notes_name_the_action() -> void:
	for kind in ["friends", "chat", "steamid", "friendadd"]:
		check(Social.overlay_note(kind) != "", "hay aviso para %s" % kind)
	check(Social.overlay_note("friends").contains("red"), "agregar amigos: en el simulado ya son amigos todas las copias de la red")


func test_steam_client_links_when_the_overlay_is_not_injected() -> void:
	eq(Social.steam_url("chat", 76561198000000001), "steam://friends/message/76561198000000001", "chat con el amigo en el cliente de Steam")
	eq(Social.steam_url("steamid", 76561198000000001), "steam://url/SteamIDPage/76561198000000001", "su perfil")
	eq(Social.steam_url("friendadd", 76561198000000001), "steam://friends/add/76561198000000001", "agregarlo")
	eq(Social.steam_url("friends", 0), "steam://open/friends", "la lista de amigos")
	eq(Social.steam_url("otra", 1), "", "lo desconocido no abre nada")


func test_hub_without_steam_explains_and_still_has_news() -> void:
	var m := _menu()
	m._input(_key(KEY_SPACE))
	var hub := m._views.hub as MHub
	eq(hub.social.rows.size(), 0, "sin Steam no hay amigos")
	check(hub.social.message.visible and hub.social.message.text != "", "explica por qué")
	check(hub.news.items.size() >= 3, "las noticias del juego se ven igual (%d)" % hub.news.items.size())
	_drop(m)


func test_news_marked_new_until_seen() -> void:
	var m := _menu()
	m._input(_key(KEY_SPACE))
	var hub := m._views.hub as MHub
	check(hub.news.new_ids.size() > 0, "la primera vez son nuevas")
	m.go("settings")
	m.back()
	eq(hub.news.new_ids, [], "al volver al inicio ya no")
	_drop(m)


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e
