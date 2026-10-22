extends Node
## Application shell: menu -> offline | host | join -> lobby -> match -> end screen.
## Also the entry point of the dedicated server (`godot --headless --path . -- --server`).
##
## Command line (after `--`):
##   --server [--port=7777] [--mode=2|3] [--map=magma|moon] [--diff=easy|normal|hard] [--wait=SEC]
##   --offline | --host | --join=IP[:PORT]   skip the menu   (+ --name= --cls= --team= --mode= --map= --diff=)
##   --practice[=tutorial]   the training yard (or the guided tutorial in it)
##   --god              (playtests) human players take no damage and cannot be crowd controlled
##   --autopilot        bots drive the human units too (demos, smoke tests)
##   --target           keep an enemy selected (screenshots)
##   --drive            the local player is scripted (random moves/casts/targets): exercises the input paths
##   --shot=PREFIX --shot-times=3,8,14   save screenshots (PREFIX_1.png ...) then quit
##   --gfx=auto|alta|media|baja
##   --no-capture       do not grab the mouse
##   --time-scale=N     debug: simulate N times faster
##   --rounds=N         debug: rounds needed to win the match

const DEFAULT_PORT := 7777

var args := {}
var server: GameServer = null
var client: GameClient = null
var offline := false
var last_cfg := {}

var _headless := false
var _ui := CanvasLayer.new()
var _menu: MenuScreen
var _lobby: LobbyScreen
var _chat: ChatPanel
var _end: EndScreen
var _match: MatchView = null
var _preview: Node3D = null
var _preview_cam: CameraRig = null
var _preview_map := ""
var _preview_t := 0.0
var _preview_dof := false
var _preview_first := 0
var _cut_fade: ColorRect
var perf: PerfOverlay
var _perf_log := 0.0
var _perf_left := -1.0
var gfx_choice := "auto"
var _lobby_port := 0
var steam: SteamBackend = null
var steam_lobbies: SteamLobbies = null
var _browser: SteamBrowser
var _steam_cfg := {}
var _via_steam := false
var _last_error := ""
var _tutorial_next := false
var _state := "menu"
var _auto_start := false
var _started_at := 0.0
var _shot_times: Array = []
var _shot_n := 0
var _menu_script: Array = []  # debug: scripted menu actions [[seconds, action, arg], ...]


func _ready() -> void:
	GameData.ensure_loaded()
	_headless = DisplayServer.get_name() == "headless"
	args = _parse(OS.get_cmdline_user_args())
	for k in ["render-scale", "upscaler", "shadows", "ssr", "ssao", "sdfgi", "volumetric_fog", "glow", "msaa", "fx_lights", "shadow_size", "embers", "dof"]:
		if args.has(k):
			var raw := str(args[k])
			Quality.overrides[k.replace("render-scale", "scale")] = raw if k == "upscaler" else (float(raw) if k in ["render-scale"] else (raw == "1" if raw in ["0", "1"] and k not in ["msaa", "shadow_size", "embers"] else float(raw)))
	_started_at = Time.get_ticks_msec()
	if args.has("time-scale"):  # debug: run the whole game faster than real time
		Engine.time_scale = float(args["time-scale"])
	if args.has("rounds"):  # debug: shorter matches (rounds needed to win)
		GameData.C["ROUNDS_TO_WIN"] = float(args.rounds)
	if args.has("server"):
		_run_dedicated()
		return
	_ui.layer = 20
	add_child(_ui)
	CursorKit.refit(Vector2(get_window().size))
	CursorKit.reset()  # the molten pointer replaces the system arrow everywhere, menus included
	perf = PerfOverlay.new()
	add_child(perf)
	if args.has("perf"):  # profiling: print numbers every second for N seconds, then quit (see tools/perf.sh)
		_perf_left = float(args.perf) if str(args.perf) != "true" else 30.0
		perf.toggle()
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 19
	add_child(fade_layer)
	_cut_fade = ColorRect.new()
	_cut_fade.color = Color(0.01, 0.005, 0.004, 1.0)
	_cut_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cut_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_fade.modulate.a = 0.0
	fade_layer.add_child(_cut_fade)
	_menu = MenuScreen.new()
	_menu.play_offline.connect(_start_offline)
	_menu.play_practice.connect(func(cfg): _start_practice(cfg))
	_menu.start_tutorial.connect(func(cfg): _start_practice(cfg, true))
	_menu.offer_tutorial = not (args.has("menu") or args.has("shot-times") or args.has("playtest") or args.has("menu-script") or args.has("offline"))
	_menu.host.connect(_start_host)
	_menu.join.connect(_start_join)
	_menu.map_changed.connect(_set_preview)
	_menu.backdrop_requested.connect(_on_backdrop)
	_menu.gfx_changed.connect(_on_gfx)
	_menu.steam_host.connect(_start_steam_host)
	_menu.steam_browse.connect(_open_steam_browser)
	_lobby = LobbyScreen.new()
	_chat = ChatPanel.new()
	add_child(_chat)
	_chat.submitted.connect(func(text): if client != null: client.send_chat(text))
	_lobby.settings.connect(func(s): if client != null: client.send_set(s))
	_lobby.start_pressed.connect(func(): if client != null: client.send_start())
	_lobby.ready_changed.connect(func(on): if client != null: client.send_ready(on))
	_lobby.leave_pressed.connect(_to_menu)
	_end = EndScreen.new()
	_end.again_pressed.connect(_again)
	_end.menu_pressed.connect(_to_menu)
	_lobby.invite_pressed.connect(func(): if steam != null and steam_lobbies != null: steam.invite_dialog(steam_lobbies.lobby_id))
	for s in [_menu, _lobby, _end]:
		s.visible = false
		_ui.add_child(s)
	_browser = SteamBrowser.new()
	_browser.visible = false
	_browser.refresh_pressed.connect(func(): if steam_lobbies != null: steam_lobbies.refresh())
	_browser.closed.connect(func(): _browser.visible = false)
	_browser.join_entry.connect(_on_browser_join)
	_ui.add_child(_browser)
	_init_steam()
	if args.has("shot-times"):
		for t in str(args["shot-times"]).split(","):
			_shot_times.append(float(t))
	_show("menu")
	_set_preview(_menu.selected_map())
	if args.has("playtest"):  # real-input automated playtest (see scripts/dev/playtest.gd, tools/playtest.sh)
		var pt: Playtest = (PracticePlaytest.new() if args.has("practice-test") else (TutorialPlaytest.new() if args.has("tutorial-test") else Playtest.new()))
		add_child(pt)
		pt.run.call_deferred(self, str(args.get("cls", "mage")), str(args.get("shot", "/tmp/playtest")), str(args.get("spec", "")))
	if args.has("menu-script"):  # e.g. --menu-script=1:key,2:go:play,3:flow:practice,4:next  (screenshots of transitions)
		for part in str(args["menu-script"]).split(","):
			var f := part.split(":")
			_menu_script.append([float(f[0]), f[1], f[2] if f.size() > 2 else ""])
	if args.has("menu"):  # debug/screenshots: jump to a menu screen ("hub", "setup", "champions:rogue", "settings:audio"...)
		_menu.debug_goto(str(args.menu))
		if args.has("menu-tip"):
			(_menu._views.champions as MChampions).debug_tip(int(args["menu-tip"]))
	var cfg := _cfg_from_args()
	if args.has("end-demo"):  # visual check of the end screen
		_show("end")
		_end.show_result(true, {"red": 2, "blue": 1}, [
			{"name": "Ana", "team": "red", "cls": "mage", "dmg": 1480, "kills": 2, "deaths": 1, "heal": 0},
			{"name": "Ignis", "team": "blue", "cls": "rogue", "dmg": 1120, "kills": 1, "deaths": 2, "heal": 0},
			{"name": "Brasa", "team": "red", "cls": "priest", "dmg": 210, "kills": 0, "deaths": 1, "heal": 1650},
			{"name": "Ceniza", "team": "blue", "cls": "warrior", "dmg": 900, "kills": 1, "deaths": 2, "heal": 0}], "JUGAR OTRA")
	elif args.has("lobby-demo"):  # visual check of the lobby
		_show("lobby")
		_lobby.show_lobby({"mode": 3, "map": "tomb", "diff": "normal", "you": 1, "host": 1, "members": [{"peer": 1, "pref": "red"}, {"peer": 2, "pref": "any"}],
			"teams": {"red": [{"bot": false, "peer": 1, "name": "Ana", "cls": "mage"}, {"bot": false, "peer": 2, "name": "Brasa", "cls": "priest"}, {"bot": true, "peer": -1, "name": "Bot", "cls": "warrior"}],
			"blue": [{"bot": true, "peer": -1, "name": "Bot", "cls": "rogue"}, {"bot": true, "peer": -1, "name": "Bot", "cls": "hunter"}, {"bot": true, "peer": -1, "name": "Bot", "cls": "mage"}]}}, true)
		_lobby.show_connect_info(["192.168.0.23"], 7777)
		_lobby._http.cancel_request()  # the demo must not look up (or show) the real public IP
		_lobby._refresh_info("203.0.113.7")
	elif args.has("practice"):  # --practice[=tutorial]: the training yard (see also --cls= --spec=)
		_start_practice(cfg, str(args.practice) == "tutorial")
	elif args.has("offline"):
		_start_offline(cfg)
	elif args.has("host"):
		_start_host(cfg, int(args.get("port", DEFAULT_PORT)))
	elif args.has("join"):
		var parts := str(args.join).split(":")
		_start_join(cfg, parts[0], int(parts[1]) if parts.size() > 1 else DEFAULT_PORT)


func _parse(list: PackedStringArray) -> Dictionary:
	var d := {}
	for a in list:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		d[kv[0]] = kv[1] if kv.size() > 1 else true
	return d


func _cfg_from_args() -> Dictionary:
	var base := {"name": "Jugador", "cls": "mage", "mode": 2, "diff": "normal", "map": "random", "pref": "any"}
	if _menu != null and not args.has("offline") and not args.has("host") and not args.has("join") and not args.has("practice"):
		return _menu._cfg()
	for k in ["name", "cls", "spec", "mode", "diff", "map"]:
		if args.has(k):
			base[k] = args[k]
	if args.has("team"):
		base["pref"] = args.team
	return MatchConfig.normalize(base)


# ---------------------------------------------------------------- Steam (optional)

func _init_steam() -> void:
	steam = SteamBackendReal.new()
	_menu.set_steam(steam.available(), steam.status_text())
	if not steam.available():
		return
	steam_lobbies = SteamLobbies.new(steam)
	steam_lobbies.hosted.connect(_on_steam_hosted)
	steam_lobbies.list_changed.connect(func(e): _browser.show_entries(e))
	steam_lobbies.joined.connect(_on_steam_joined)
	steam_lobbies.failed.connect(func(text): _browser.set_status(text); _menu.set_status(text); _lobby.flash(text))
	steam_lobbies.backend.join_requested.connect(func(_id): _browser.visible = false)  # invite accepted from the overlay


func _steam_name(cfg: Dictionary) -> String:
	return NetChoice.player_name(cfg.name, steam.persona_name() if steam != null else "", true)


func _start_steam_host(cfg: Dictionary, friends_only: bool) -> void:
	var choice := NetChoice.resolve("steam", steam != null and steam.available(), steam.status_text() if steam != null else "")
	if choice.use != "steam":
		_menu.set_status(choice.note)
		return
	_teardown_session()
	last_cfg = cfg
	offline = false
	_via_steam = true
	_steam_cfg = cfg
	var scfg := {"mode": cfg.mode, "diff": cfg.diff, "map": cfg.map, "dedicated": false, "autopilot": args.has("autopilot")}
	server = GameServer.new(scfg)
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	client = _new_client(cfg)
	client.attach(link[1], {"name": _steam_name(cfg), "cls": cfg.cls, "spec": cfg.get("spec", ""), "pref": cfg.pref})
	steam_lobbies.host(friends_only, {"mode": cfg.mode, "map": cfg.map, "name": _steam_name(cfg)})
	_menu.set_status("Creando la sala de Steam…")


func _on_steam_hosted(lobby_id: int) -> void:
	if server == null:
		return
	server.attach(SteamTransport.host(steam, lobby_id))


func _open_steam_browser() -> void:
	if steam_lobbies == null:
		_menu.set_status(NetChoice.resolve("steam", false, steam.status_text()).note)
		return
	_browser.visible = true
	_browser.set_status("Buscando…")
	steam_lobbies.refresh()


func _on_browser_join(entry: Dictionary) -> void:
	_teardown_session()
	_via_steam = true
	_browser.set_status("Entrando a la sala…")
	steam_lobbies.join(int(entry.id))


## Joined a Steam lobby (from the list or from an overlay invite): talk to its owner over Steam messages.
func _on_steam_joined(lobby_id: int, owner: int) -> void:
	_browser.visible = false
	var cfg: Dictionary = _menu._cfg() if _state == "menu" else last_cfg
	last_cfg = cfg
	offline = false
	_via_steam = true
	client = _new_client(cfg)
	client.attach(SteamTransport.join(steam, lobby_id, owner), {"name": _steam_name(cfg), "cls": cfg.cls, "spec": cfg.get("spec", ""), "pref": cfg.pref})
	_menu.set_status("Conectando con el anfitrión por Steam…")


# ---------------------------------------------------------------- dedicated server

func _run_dedicated() -> void:
	var cfg := MatchConfig.normalize({"mode": args.get("mode", 2), "diff": args.get("diff", "normal"), "map": args.get("map", "random")})
	cfg["dedicated"] = true
	cfg["auto_start_ms"] = float(args.get("wait", 10)) * 1000.0
	cfg["autopilot"] = args.has("autopilot")
	server = GameServer.new(cfg)
	var port := int(args.get("port", DEFAULT_PORT))
	var t := PeerTransport.host(port, 8)
	if t == null:
		push_error("No se pudo abrir el puerto %d" % port)
		get_tree().quit(1)
		return
	server.attach(t)
	server.match_started.connect(func(): print("[servidor] empezó una partida %dv%d en %s" % [server.cfg.mode, server.cfg.mode, server.cfg.map]))
	server.match_ended.connect(func(): print("[servidor] terminó la partida; vuelve al lobby"))
	server.player_joined.connect(func(n): print("[servidor] entró %s (%d en la sala)" % [n, server.humans_count()]))
	server.player_left.connect(func(n): print("[servidor] salió %s (%d en la sala)" % [n, server.humans_count()]))
	print("Imba Arena Tournament — servidor dedicado %dv%d (%s) escuchando en el puerto %d" % [cfg.mode, cfg.mode, cfg.map, port])


# ---------------------------------------------------------------- flows

func _teardown_session() -> void:
	if steam_lobbies != null:
		steam_lobbies.leave()
	if _match != null:
		_match.stop()
		_match.queue_free()
		_match = null
	if client != null:
		client.close()
		client = null
	if server != null:
		server.shutdown()
		server = null
	_auto_start = false
	_via_steam = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _new_client(cfg: Dictionary) -> GameClient:
	var c := GameClient.new()
	c.welcomed.connect(_on_welcomed)
	c.lobby_updated.connect(_on_lobby)
	c.match_started.connect(_on_match_started)
	c.closed.connect(_on_closed)
	c.server_error.connect(_on_server_error)
	if _chat != null:
		_chat.lines.clear()
		_chat.log_label.text = "Enter: chat de la sala"
		c.chat_received.connect(_chat.receive)
	if args.has("log"):
		_log_client(c)
	return c


func _on_server_error(text: String) -> void:
	_last_error = text
	if _state == "menu":
		_menu.set_status(text)
	elif _state == "lobby":
		_lobby.flash(text)


## Console trace of what the client sees (headless smoke tests: --log).
func _log_client(c: GameClient) -> void:
	var n := [0]
	c.welcomed.connect(func(): print("[cliente] bienvenido, peer=%d anfitrión=%s" % [c.peer_id, c.is_host]))
	c.lobby_updated.connect(func(m): print("[cliente] lobby: %d humanos, %s %dv%d" % [m.members.size(), m.map, m.mode, m.mode]))
	c.match_started.connect(func(m): print("[cliente] partida: yo=%d roster=%s" % [m.you, str(m.roster.map(func(r): return "%s:%s:%s" % [r.name, r.cls, r.team]))]))
	c.state_received.connect(func(s):
		n[0] += 1
		if n[0] % 90 == 1:
			print("[cliente] snapshot #%d fase=%s ronda=%d unidades visibles=%d marcador=%s" % [n[0], s.phase, s.round, s.units.size(), str(s.score)]))
	c.match_ended.connect(func(m): print("[cliente] fin de partida: ganó %s %s" % [m.winner, str(m.score)]))
	c.closed.connect(func(r): print("[cliente] cerrado: ", r))


func _start_offline(cfg: Dictionary) -> void:
	_teardown_session()
	last_cfg = cfg
	offline = true
	_auto_start = true
	var scfg := {"mode": cfg.mode, "diff": cfg.diff, "map": cfg.map, "dedicated": false, "autopilot": args.has("autopilot"), "god": args.has("god")}
	server = GameServer.new(scfg)
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	client = _new_client(cfg)
	client.attach(link[1], {"name": cfg.name, "cls": cfg.cls, "spec": cfg.get("spec", ""), "pref": cfg.pref})
	_show("none")


## "Arena de práctica" (training yard) or, with `tutorial`, the same yard with the guided tutorial on top. Offline only.
func _start_practice(cfg: Dictionary, tutorial := false) -> void:
	_teardown_session()
	last_cfg = cfg
	offline = true
	_auto_start = true
	_tutorial_next = tutorial
	var scfg := {"mode": 2, "diff": "normal", "map": GameMap.PRACTICE_ID, "dedicated": false, "autopilot": false, "practice": true}
	server = GameServer.new(scfg)
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	client = _new_client(cfg)
	client.attach(link[1], {"name": cfg.name, "cls": cfg.cls, "spec": cfg.get("spec", ""), "pref": "red"})
	_show("none")


func _on_practice_switch(cls: String, spec: String) -> void:
	var st: SettingsStore = _menu.st
	st.set_value("cls", cls)
	if spec != "":
		st.set_value("spec", spec)
	st.save()
	var cfg := _menu._cfg()
	_start_practice.call_deferred(cfg)


func _on_tutorial_finished(action: String) -> void:
	match action:
		"arena": _start_practice.call_deferred(last_cfg)
		"bots": _start_offline.call_deferred(last_cfg)
		_: _to_menu.call_deferred()


func _start_host(cfg: Dictionary, port: int) -> void:
	_teardown_session()
	last_cfg = cfg
	offline = false
	var scfg := {"mode": cfg.mode, "diff": cfg.diff, "map": cfg.map, "dedicated": false, "autopilot": args.has("autopilot")}
	server = GameServer.new(scfg)
	var net := PeerTransport.host(port, 8)
	if net == null:
		server = null
		_menu.set_status("No se pudo abrir el puerto %d (¿ya hay otra partida abierta?)." % port)
		_show("menu")
		return
	server.attach(net)
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	client = _new_client(cfg)
	client.attach(link[1], {"name": cfg.name, "cls": cfg.cls, "spec": cfg.get("spec", ""), "pref": cfg.pref})
	_lobby_port = port
	_show("none")


func _start_join(cfg: Dictionary, address: String, port: int) -> void:
	_teardown_session()
	last_cfg = cfg
	offline = false
	if address == "":
		_menu.set_status("Escribí la IP del anfitrión.")
		return
	var net := PeerTransport.join(address, port)
	if net == null:
		_menu.set_status("No se pudo conectar a %s:%d" % [address, port])
		return
	client = _new_client(cfg)
	client.attach(net, {"name": cfg.name, "cls": cfg.cls, "spec": cfg.get("spec", ""), "pref": cfg.pref})
	_menu.set_status("Conectando a %s:%d…" % [address, port])


func _local_ip_list() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out


func _local_ips() -> String:
	var out: Array = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return ", ".join(out) if not out.is_empty() else "(sin red)"


func _on_welcomed() -> void:
	pass


func _on_lobby(msg: Dictionary) -> void:
	if offline and _auto_start and client.is_host:
		_auto_start = false
		client.send_start()
		return
	if _state == "menu" or _state == "none" or _state == "lobby":
		var first := _state != "lobby"
		_show("lobby")
		_lobby.show_lobby(msg, client.is_host)
		if first and client.is_host and not offline and _lobby_port > 0 and not _via_steam:
			_lobby.show_connect_info(_local_ip_list(), _lobby_port)
		elif client.is_host and _via_steam:
			_lobby.show_steam_info()
			if steam_lobbies != null:
				steam_lobbies.update_settings({"mode": msg.mode, "map": msg.map, "name": _steam_name(last_cfg)})
		_set_preview(msg.map)


func _on_match_started(msg: Dictionary) -> void:
	_show("match")
	_clear_preview()
	_match = (load("res://scenes/match.tscn") as PackedScene).instantiate()
	_match.capture_mouse = not args.has("no-capture") and not args.has("shot-times") and not _headless and not args.has("drive")
	_match.drive_bot = args.has("drive")
	_match.demo_target = args.has("target")
	_match.gfx_choice = gfx_choice
	_match.tutorial = _tutorial_next
	_match.chat = _chat
	add_child(_match)
	_match.start(client, msg)
	_match.finished.connect(_on_match_finished)
	if _match.practice:
		_match.practice_switch.connect(_on_practice_switch)
		_match.leave_requested.connect(func(): _to_menu.call_deferred())
		if _tutorial_next:
			var tut := TutorialOverlay.new()
			tut.attach(_match, TutorialFlow.new(str(last_cfg.cls), str(last_cfg.get("spec", ""))))
			tut.finished.connect(_on_tutorial_finished)
	_tutorial_next = false


func _on_match_finished(end: Dictionary, rows: Array) -> void:
	if _match != null:
		_match.stop()
		_match.queue_free()
		_match = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var mine := ""
	if client != null:
		for r in client.roster:
			if r.id == client.unit_id:
				mine = r.team
	_show("end")
	_set_preview(last_cfg.get("map", "random"))
	_end.show_result(end.winner == mine, end.score, rows, "JUGAR OTRA" if offline else "VOLVER A LA SALA")


func _again() -> void:
	if offline:
		_start_offline(last_cfg)
	elif client != null and not client.lobby.is_empty():
		_show("lobby")
		_lobby.show_lobby(client.lobby, client.is_host)
	else:
		_to_menu()


func _on_closed(reason: String) -> void:
	call_deferred("_closed_deferred", reason)  # we are inside the transport's poll()


func _closed_deferred(reason: String) -> void:
	var msg := _last_error if _last_error != "" else reason
	_last_error = ""
	_to_menu()
	_menu.set_status(msg)


func _to_menu() -> void:
	_teardown_session()
	_show("menu")
	_set_preview(_menu.selected_map())


func _show(state: String) -> void:
	_state = state
	if _chat != null:
		_chat.activate(state in ["lobby", "match", "end"])
	_menu.visible = state == "menu"
	_lobby.visible = state == "lobby"
	_end.visible = state == "end"
	if state == "menu":
		_menu.set_status("" if _menu.status.text.begins_with("Conectando") else _menu.status.text)


# ---------------------------------------------------------------- preview behind the menus

func _on_gfx(choice: String) -> void:
	gfx_choice = "baja" if Quality.compatibility_renderer() else str(args.get("gfx", choice))
	if _preview != null:
		_preview.get_meta("world").apply_quality(Quality.effective(_menu_level(), Vector2i(get_window().size)))


## Level used behind the menus: the real one for a fixed choice, the device default for "auto".
func _menu_level() -> String:
	return Quality.resolve(gfx_choice, Quality.initial_level(RenderingServer.get_video_adapter_type(), Quality.compatibility_renderer()))


func _clear_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null
		_preview_cam = null
		_preview_map = ""
		_cut_fade.modulate.a = 0.0


## The menu asks for a backdrop: the title screen always flies over a new random arena.
func _on_backdrop(kind: String) -> void:
	if kind == "splash":
		_set_preview(_random_map(_preview_map), true)


func _random_map(avoid := "") -> String:
	var id := GameMap.pick_id(randi())
	for i in 6:
		if id != avoid:
			break
		id = GameMap.pick_id(randi())
	return id


func _set_preview(map_id: String, force := false) -> void:
	if map_id == "random":
		map_id = _preview_map if (_preview_map != "" and not force) else _random_map(_preview_map)
	if _headless or _preview_map == map_id:
		return
	_clear_preview()
	_preview = Node3D.new()
	add_child(_preview)
	var w := ArenaWorld.new()
	_preview.add_child(w)
	w.setup(GameMap.create(map_id))
	_preview_cam = CameraRig.new()
	_preview.add_child(_preview_cam)
	_preview_cam.current = true
	_preview.set_meta("world", w)
	var pq := Quality.effective(_menu_level(), Vector2i(get_window().size))
	w.apply_quality(pq)
	_preview_dof = bool(pq.dof) and not Quality.compatibility_renderer()
	_preview_map = map_id
	_preview_t = 0.0
	_preview_first = randi() % MenuShots.SHOTS


# ---------------------------------------------------------------- frame

func _input(event: InputEvent) -> void:
	if _chat != null and _chat.typing():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3 and perf != null:
		perf.toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _match != null and perf != null:
		perf.extra = "calidad %s" % _match.gfx_level
	if _perf_left >= 0.0 and _state == "match" and _match != null and _match.last_state.get("phase", "") == "fight":
		_perf_left -= AutoQuality.real_delta(delta, Engine.time_scale)
		_perf_log += AutoQuality.real_delta(delta, Engine.time_scale)
		if _perf_log >= 1.0:
			_perf_log = 0.0
			var i: Dictionary = perf.info
			print("PERF fps=%d frame=%.1f cpu=%.1f gpu=%.1f script=%.1f draws=%d objs=%d prims=%d scale=%.2f %s" % [i.get("fps", 0), i.get("avg_ms", 0), i.get("cpu_ms", 0), i.get("gpu_ms", 0), i.get("process_ms", 0), i.get("draws", 0), i.get("objects", 0), i.get("prims", 0), i.get("scale", 1), perf.extra])
		if _perf_left <= 0.0:
			get_tree().quit()
	var ms := delta * 1000.0
	if steam != null:
		steam.run_callbacks()
	if server != null:
		server.process(ms)
	if client != null:
		client.poll(ms)
	if _preview_cam != null and _preview != null:
		_preview_t += delta
		var sh := MenuShots.at(_preview_t, _preview_first)
		_preview_cam.cinematic(MenuShots.sample(_preview_map, sh.shot, sh.t), _preview_dof)
		(_preview.get_meta("world") as ArenaWorld).follow(0.0, 0.0)
		_cut_fade.modulate.a = sh.dark
	while not _menu_script.is_empty() and (Time.get_ticks_msec() - _started_at) / 1000.0 >= _menu_script[0][0]:
		var act: Array = _menu_script.pop_front()
		match act[1]:
			"key":
				var ev := InputEventKey.new()
				ev.keycode = KEY_SPACE
				ev.pressed = true
				_menu._input(ev)
			"press":  # an input action as if typed/pressed on a gamepad (ui_down, ui_accept, ui_cancel...)
				for down in [true, false]:
					var ae := InputEventAction.new()
					ae.action = act[2]
					ae.pressed = down
					Input.parse_input_event(ae)
			"go": _menu.go(act[2])
			"back": _menu.back()
			"flow": _menu.start_flow(act[2])
			"next": _menu.next_step()
	if _shot_n < _shot_times.size() and (Time.get_ticks_msec() - _started_at) / 1000.0 >= _shot_times[_shot_n]:
		_shot_n += 1
		await _save_shot(_shot_n)
		if _shot_n >= _shot_times.size():
			get_tree().quit()


func _save_shot(n: int) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s_%d.png" % [args.get("shot", "user://shot"), n]
	get_viewport().get_texture().get_image().save_png(path)
	print("captura: ", path)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_teardown_session()


func _exit_tree() -> void:
	_teardown_session()
	# Static caches keep Resources alive past shutdown ("resources still in use" warnings).
	Textures.clear_cache()
	MeshBuilder.clear_cache()
	UiKit.clear_cache()
	CursorKit._tex.clear()
