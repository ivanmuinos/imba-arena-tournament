extends TestBase
## Menu navigation state machine, persisted settings and input validation.


# ---------------------------------------------------------------- navigation

func test_nav_starts_on_splash_and_any_key_goes_to_hub_without_history() -> void:
	var n := MenuNav.new()
	eq(n.current, "splash", "arranca en la pantalla de título")
	check(not n.can_back(), "no se vuelve atrás desde el título")
	n.advance_from_splash()
	eq(n.current, "hub", "cualquier tecla: al menú principal")
	check(not n.can_back(), "el título no queda en el historial")


func test_nav_push_back_and_esc_behaviour() -> void:
	var n := MenuNav.new()
	n.advance_from_splash()
	n.go("play")
	n.go("setup")
	eq(n.current, "setup", "dos pasos adentro")
	eq(n.back(), "play", "Esc vuelve un paso")
	eq(n.back(), "hub", "y otro")
	eq(n.back(), "", "en el hub Esc no vuelve más")
	eq(n.current, "hub", "se queda en el hub")


func test_nav_ignores_duplicate_and_unknown_screens() -> void:
	var n := MenuNav.new()
	n.advance_from_splash()
	n.go("hub")
	check(not n.can_back(), "ir a la misma pantalla no apila")
	n.go("nowhere")
	eq(n.current, "hub", "pantalla inexistente ignorada")


func test_nav_reset_to_hub_clears_history() -> void:
	var n := MenuNav.new()
	n.advance_from_splash()
	n.go("play")
	n.go("setup")
	n.reset_to("hub")
	eq(n.current, "hub", "al hub")
	check(not n.can_back(), "sin historial")


func test_nav_flows_per_play_mode() -> void:
	eq(MenuNav.flow_for("practice"), ["setup", "champions"], "práctica: configurar y elegir campeón")
	eq(MenuNav.flow_for("host"), ["setup", "champions"], "crear partida")
	eq(MenuNav.flow_for("join"), ["join", "champions"], "unirse: dirección y campeón")
	eq(MenuNav.flow_for("steam_host"), ["setup", "champions"], "sala Steam")
	eq(MenuNav.flow_for("steam_browse"), ["champions"], "salas de Steam: ya se elige en la lista")
	eq(MenuNav.flow_for("???"), ["setup", "champions"], "desconocido = práctica")


func test_nav_flow_steps_advance_then_finish() -> void:
	var n := MenuNav.new()
	n.advance_from_splash()
	n.go("play")
	n.start_flow("practice")
	eq(n.current, "setup", "primer paso")
	check(not n.flow_done(), "falta elegir campeón")
	n.next()
	eq(n.current, "champions", "segundo paso")
	n.next()
	check(n.flow_done(), "terminó el flujo: se puede jugar")
	eq(n.mode, "practice", "recuerda el modo")


# ---------------------------------------------------------------- settings

func _tmp() -> String:
	return "user://test_settings_%d.cfg" % randi()


func test_settings_defaults_and_clamping() -> void:
	var s := SettingsStore.new()
	eq(s.get_value("master"), 0.8, "volumen por defecto")
	s.set_value("master", 7.0)
	eq(s.get_value("master"), 1.0, "volumen acotado a 1")
	s.set_value("music", -3.0)
	eq(s.get_value("music"), 0.0, "volumen acotado a 0")
	s.set_value("sens", 99.0)
	eq(s.get_value("sens"), SettingsStore.SENS_MAX, "sensibilidad acotada")
	eq(s.get_value("bar_scale"), 1.0, "barra de habilidades a tamaño normal")
	s.set_value("bar_scale", 9.0)
	eq(s.get_value("bar_scale"), SettingsStore.BAR_MAX, "tamaño de la barra acotado")
	s.set_value("bar_scale", "grande")
	eq(s.get_value("bar_scale"), 1.0, "tamaño inválido = normal")
	s.set_value("enemy_frame_scale", 0.1)
	eq(s.get_value("enemy_frame_scale"), SettingsStore.FRAME_MIN, "marcos de oponentes acotados")
	s.set_value("ally_frame_scale", "chico")
	eq(s.get_value("ally_frame_scale"), 1.0, "tamaño de marcos inválido = normal")
	s.set_value("gfx", "ultra")
	eq(s.get_value("gfx"), "auto", "calidad inválida = auto")
	s.set_value("map", "marte")
	eq(s.get_value("map"), "random", "mapa inválido = aleatorio")
	s.set_value("cls", "dragon")
	eq(s.get_value("cls"), "mage", "clase inválida")
	s.set_value("name", "  \u0007Ana  ")
	eq(s.get_value("name"), "Ana", "nombre limpio")


func test_settings_persist_round_trip_and_survive_garbage() -> void:
	var path := _tmp()
	var s := SettingsStore.new()
	s.set_value("name", "Luz")
	s.set_value("cls", "rogue")
	s.set_value("map", "tomb")
	s.set_value("invert", true)
	s.set_value("sens", 1.4)
	s.set_value("addr", "10.0.0.5")
	s.set_value("port", 9000)
	check(s.save(path), "guarda")
	var t := SettingsStore.new()
	check(t.load(path), "carga")
	eq([t.get_value("name"), t.get_value("cls"), t.get_value("map"), t.get_value("invert"), t.get_value("addr"), t.get_value("port")], ["Luz", "rogue", "tomb", true, "10.0.0.5", 9000], "todo vuelve")
	near(t.get_value("sens"), 1.4, 1e-6, "sensibilidad")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[menu]\nmaster=\"alto\"\nport=\"abc\"\nmode=99\n")
	f.close()
	var u := SettingsStore.new()
	u.load(path)
	eq(u.get_value("master"), 0.8, "valor de tipo inválido: se usa el defecto")
	eq(u.get_value("port"), 7777, "puerto basura: defecto")
	eq(u.get_value("mode"), 2, "modo inválido")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(not SettingsStore.new().load("user://no_existe.cfg"), "archivo inexistente: false y defectos")


func test_settings_migrates_old_map_ids() -> void:
	var s := SettingsStore.new()
	s.set_value("map", "magma")
	eq(s.get_value("map"), "random", "los mapas viejos (magma/moon) ya no existen")


# ---------------------------------------------------------------- validation

func test_port_and_address_validation() -> void:
	eq(SettingsStore.parse_port("7777"), 7777, "puerto válido")
	eq(SettingsStore.parse_port(" 20000 "), 20000, "con espacios")
	eq(SettingsStore.parse_port("0"), -1, "0 no vale")
	eq(SettingsStore.parse_port("70000"), -1, "fuera de rango")
	eq(SettingsStore.parse_port("abc"), -1, "texto")
	eq(SettingsStore.parse_port(""), -1, "vacío")
	check(SettingsStore.valid_address("192.168.0.10"), "IPv4")
	check(SettingsStore.valid_address("mi-servidor.ejemplo.com"), "nombre de host")
	check(SettingsStore.valid_address("100.64.1.2"), "IP de Tailscale")
	check(not SettingsStore.valid_address(""), "vacía")
	check(not SettingsStore.valid_address("a b"), "con espacio")
	check(not SettingsStore.valid_address("host;rm -rf"), "caracteres raros")
	check(not SettingsStore.valid_address("x".repeat(300)), "demasiado larga")
	eq(SettingsStore.split_address("10.0.0.1:9000"), {"addr": "10.0.0.1", "port": 9000}, "dirección con puerto")
	eq(SettingsStore.split_address("10.0.0.1"), {"addr": "10.0.0.1", "port": -1}, "sin puerto")


# ---------------------------------------------------------------- class meta for the champion screen

func test_every_class_has_menu_meta_and_icons() -> void:
	GameData.ensure_loaded()
	for id in GameData.classes:
		var c: Dictionary = GameData.classes[id]
		check(c.has("tags") and c.tags.size() >= 1, "%s: etiquetas de rol" % id)
		check(c.has("tagline") and str(c.tagline) != "", "%s: frase" % id)
		for k in ["hp", "mobility", "damage", "control", "difficulty"]:
			var v: int = int(c.stats.get(k, 0))
			check(v >= 1 and v <= 5, "%s: estadística %s entre 1 y 5" % [id, k])
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % c.icon), "%s: icono de clase existe" % id)
		for a in c.abilities:
			check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "%s/%s: icono existe" % [id, a.id])


func test_no_emoji_in_game_data() -> void:
	GameData.ensure_loaded()
	var re := RegEx.new()
	re.compile("[\\x{1F000}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{2B00}-\\x{2BFF}]")
	for path in ["res://data/classes.json", "res://data/powers.json", "res://data/maps.json"]:
		check(re.search(FileAccess.get_file_as_string(path)) == null, "%s sin emoji" % path)


# ---------------------------------------------------------------- the real MenuScreen, driven like a player would

const SCRATCH := "user://test_menu_flow.cfg"


func _menu() -> MenuScreen:
	SettingsStore.path = SCRATCH
	SettingsStore.clear_shared()
	var tree := tree
	var m := MenuScreen.new()
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


func test_menu_splash_any_key_then_practice_flow_launches_offline() -> void:
	var m := _menu()
	eq(m.nav.current, "splash", "arranca en el título")
	m._input(_key(KEY_SPACE))
	eq(m.nav.current, "hub", "cualquier tecla pasa al menú")
	var got := []
	m.play_offline.connect(func(cfg): got.append(cfg))
	m.go("play")
	m.start_flow("practice")
	eq(m.nav.current, "setup", "primero la configuración")
	m.next_step()
	eq(m.nav.current, "champions", "después el campeón")
	m.st.set_value("cls", "rogue")
	m.next_step()
	eq(got.size(), 1, "se lanza la práctica una sola vez")
	eq(got[0].cls, "rogue", "con la clase elegida")
	m.next_step()
	eq(got.size(), 1, "un segundo intento inmediato no duplica el lanzamiento")
	_drop(m)


func test_menu_esc_goes_back_and_hub_has_no_back() -> void:
	var m := _menu()
	m._input(_key(KEY_ENTER))
	m.go("play")
	m.start_flow("practice")
	m._input(_key(KEY_ESCAPE))
	eq(m.nav.current, "play", "Esc vuelve un paso")
	m._input(_key(KEY_ESCAPE))
	eq(m.nav.current, "hub", "y otro")
	m._input(_key(KEY_ESCAPE))
	eq(m.nav.current, "hub", "en el hub Esc no hace nada")
	_drop(m)


func test_menu_host_join_and_steam_flows_emit_the_right_signal() -> void:
	var m := _menu()
	m._input(_key(KEY_ENTER))
	var host := []
	var join := []
	var browse := []
	m.host.connect(func(cfg, port): host.append(port))
	m.join.connect(func(cfg, addr, port): join.append([addr, port]))
	m.steam_browse.connect(func(): browse.append(1))
	m.st.set_value("port", 9001)
	m.go("play")
	m.start_flow("host")
	m.next_step()
	m.next_step()
	eq(host, [9001], "crear partida usa el puerto guardado")
	m._launching = false
	m.nav.reset_to("hub")
	m.go("play")
	m.start_flow("join")
	eq(m.nav.current, "join", "unirse pide la dirección")
	var jv: MJoin = m._views.join
	jv._addr.text = "host con espacios"
	jv._submit()
	eq(m.nav.current, "join", "dirección inválida: no avanza")
	check(jv._err.text != "", "y explica el error")
	jv._addr.text = "10.1.2.3:8123"
	jv._submit()
	eq(m.nav.current, "champions", "dirección válida: elige campeón")
	m.next_step()
	eq(join, [["10.1.2.3", 8123]], "se une con IP y puerto parseados")
	m._launching = false
	m.nav.reset_to("hub")
	m.go("play")
	m.start_flow("steam_browse")
	eq(m.nav.current, "champions", "buscar salas de Steam: sólo campeón")
	m.next_step()
	eq(browse.size(), 1, "abre el explorador de salas")
	_drop(m)


func test_menu_settings_changes_persist_and_apply() -> void:
	var m := _menu()
	var gfx := []
	m.gfx_changed.connect(func(v): gfx.append(v))
	m.st.set_value("gfx", "baja")
	m.settings_changed("gfx")
	eq(gfx, ["baja"], "cambiar la calidad avisa a main")
	var reload := SettingsStore.new()
	check(reload.load(SCRATCH), "se guardó en disco")
	eq(reload.get_value("gfx"), "baja", "y vuelve igual")
	m.set_status("hola")
	eq(m.status.text, "hola", "el estado queda legible para main")
	_drop(m)


func test_tooltip_meta_line_describes_cooldown_and_range() -> void:
	eq(UiTip.meta_line({"cd": 6000, "range": 18}), "Recarga 6 s · Alcance 18 m", "recarga y alcance")
	eq(UiTip.meta_line({"cd": 0, "ult": true, "range": 30}), "Definitiva (una vez por partida) · Alcance 30 m", "definitiva")
	eq(UiTip.meta_line({"cd": 450, "cast": 1500}), "Recarga 0.5 s · Lanzamiento 1.5 s", "con lanzamiento")
	eq(UiTip.meta_line({"cd": 0}), "Sin recarga", "sin recarga")


# ---------------------------------------------------------------- tutorial and practice arena entries

func test_nav_has_howto_and_arena_flows() -> void:
	check(MenuNav.SCREENS.has("howto"), "pantalla Cómo jugar")
	eq(MenuNav.flow_for("arena"), ["champions"], "la arena de práctica sólo pide campeón")
	var n := MenuNav.new()
	n.advance_from_splash()
	n.go("howto")
	eq(n.current, "howto", "se llega desde el hub")
	eq(n.back(), "hub", "Esc vuelve al hub")


func test_menu_arena_flow_emits_practice_arena_with_the_chosen_champion() -> void:
	var m := _menu()
	m._input(_key(KEY_SPACE))
	var got := []
	var offline := []
	m.play_practice.connect(func(cfg): got.append(cfg))
	m.play_offline.connect(func(cfg): offline.append(cfg))
	m.go("play")
	m.start_flow("arena")
	eq(m.nav.current, "champions", "elige campeón")
	m.st.set_value("cls", "warlock")
	m.next_step()
	eq(got.size(), 1, "lanza la arena de práctica")
	eq(got[0].cls, "warlock", "con el campeón elegido")
	eq(offline.size(), 0, "no es una partida contra bots")
	_drop(m)


func test_menu_tutorial_signal_and_first_launch_flag() -> void:
	var m := _menu()
	m._input(_key(KEY_SPACE))
	var got := []
	m.start_tutorial.connect(func(cfg): got.append(cfg))
	m.launch_tutorial()
	eq(got.size(), 1, "arranca el tutorial")
	check(bool(m.st.get_value("tutorial_seen")), "queda marcado como visto")
	_drop(m)
	var st := SettingsStore.new()
	check(not bool(st.get_value("tutorial_seen")), "por defecto no lo vio")
	st.set_value("tutorial_seen", true)
	check(bool(st.get_value("tutorial_seen")), "se guarda")
	st.set_value("tutorial_seen", "yes")
	check(not bool(st.get_value("tutorial_seen")), "un valor inválido no cuenta como visto")


func test_first_launch_offers_the_tutorial_once_and_it_can_be_skipped() -> void:
	var m := _menu()
	m.st.set_value("tutorial_seen", false)
	m._input(_key(KEY_SPACE))
	var hub := m._views.hub as MHub
	check(hub.offer_visible(), "la primera vez el menú ofrece el tutorial")
	hub.dismiss_offer()
	check(not hub.offer_visible(), "Ahora no la cierra")
	check(bool(m.st.get_value("tutorial_seen")), "y no vuelve a aparecer sola")
	hub.menu_enter()
	check(not hub.offer_visible(), "al volver al hub tampoco")
	_drop(m)
	var m2 := _menu()
	m2.offer_tutorial = false
	m2.st.set_value("tutorial_seen", false)
	m2._input(_key(KEY_SPACE))
	check(not (m2._views.hub as MHub).offer_visible(), "las ejecuciones con argumentos (capturas, pruebas) no la muestran")
	_drop(m2)


func test_key_settings_name_the_abilities_of_your_champion() -> void:
	var m := _menu()
	var s: MSettings = m._views.settings
	m.st.set_value("cls", "mage")
	m.st.set_value("spec", "fire")
	s.menu_enter()
	var fire := GameData.abilities("mage", "fire")
	eq((s._bind_labels.slot_0 as Label).text, str(fire[0].name), "la tecla 1 dice qué habilidad es")
	eq((s._bind_labels.slot_6 as Label).text, "Definitiva: " + str(fire[6].name), "la definitiva")
	check(s._bind_caption.text.contains("Fuego"), "dice de qué campeón son")
	m.st.set_value("cls", "rogue")
	s.menu_enter()
	eq((s._bind_labels.slot_1 as Label).text, str(GameData.abilities("rogue", str(m.st.get_value("spec")))[1].name), "cambia con el campeón")
	eq((s._pad_labels.slot_1 as Label).text, (s._bind_labels.slot_1 as Label).text, "también en la tabla del mando")
	_drop(m)


func test_disabled_classes_are_not_offered_and_fall_back_to_mage() -> void:
	for id in GameData.DISABLED_CLASSES:
		check(GameData.classes.has(id), "%s sigue en los datos" % id)
		check(not MatchConfig.class_ids().has(id), "%s no sale para bots ni en las listas" % id)
		eq(MatchConfig.normalize({"cls": id}).cls, "mage", "pedir %s da mago" % id)
	var st := SettingsStore.new()
	eq(st.set_value("cls", "ki"), "mage", "un campeón guardado desactivado vuelve a mago")
	check(MatchConfig.class_ids().has("warlock"), "los demás siguen")
