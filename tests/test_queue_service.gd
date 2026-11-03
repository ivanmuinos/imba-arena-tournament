extends TestBase
## Client side of the normal queue and groups (S17) and of the sign-in driver: request shapes, the poll state machine
## (announce a match once, lobby id for guests), pacing, abandoning, reporting, and the dev switch for Online.
## The pairing and the rules are tested on the server (supabase/tests); FakeOnline only replaces the transport.

const ANA := "76561199000000001"
const BETO := "76561199000000002"
const MATCH := "0f0f0f0f-0000-4000-8000-000000000001"


func _api(clock := 1000.0) -> FakeOnline:
	var api := FakeOnline.new()
	api.base_url = "http://127.0.0.1:54321"
	api.anon_key = "anon"
	api.enabled = true
	api.clock = clock
	api.token = "jwt"
	api.token_expires = 99999.0
	api.steam_id = ANA
	return api


func _svc(api: FakeOnline = null) -> QueueService:
	return QueueService.new(api if api != null else _api())


func _args(svc: QueueService, i: int) -> Dictionary:
	return JSON.parse_string((svc.api as FakeOnline).calls[i].body)


func _path(svc: QueueService, i: int) -> String:
	return (svc.api as FakeOnline).calls[i].url.get_slice("/rpc/", 1)


func _matched(host := ANA, lobby = null, side := "red") -> Dictionary:
	return {"state": "matched", "mode": 2.0, "wait": 4.0, "match": {"id": MATCH, "host": host, "is_host": host == ANA,
		"lobby_id": lobby, "side": side, "sides": {"red": [{"steam_id": ANA, "name": "Ana"}], "blue": [{"steam_id": BETO, "name": "Beto"}]}}}


func test_online_dev_switch() -> void:
	check(not Online.dev_flag(PackedStringArray([]), {}), "sin bandera: apagado")
	check(Online.dev_flag(PackedStringArray(["--online"]), {}), "--online lo prende (solo desarrollo)")
	check(Online.dev_flag(PackedStringArray([]), {"IMBA_ONLINE": "1"}), "IMBA_ONLINE=1 lo prende")
	check(not Online.dev_flag(PackedStringArray([]), {"IMBA_ONLINE": "0"}), "IMBA_ONLINE=0 no")
	check(not Online.dev_flag(PackedStringArray(["--offline"]), {}), "otros argumentos no")
	eq(Online.ENABLED, false, "el valor que se publica sigue apagado")


func test_poll_pacing() -> void:
	eq(QueueService.poll_interval("idle", false), 0.0, "ocioso y sin grupo: no consulta")
	eq(QueueService.poll_interval("idle", true), 8.0, "con grupo mira cada 8 s")
	eq(QueueService.poll_interval("searching", false), 6.0, "buscando: cada 6 s")
	eq(QueueService.poll_interval("matched", false), 3.0, "con partida esperando la sala: cada 3 s")
	var svc := _svc()
	svc.state = "searching"
	svc.tick(5.9)
	eq((svc.api as FakeOnline).calls.size(), 0, "todavia no")
	svc.tick(0.2)
	eq((svc.api as FakeOnline).calls.size(), 1, "al cumplirse el intervalo consulta")
	eq(_path(svc, 0), "queue_status", "consulta el estado")
	svc.tick(1.0)
	eq((svc.api as FakeOnline).calls.size(), 1, "y no repite enseguida")
	var idle := _svc()
	idle.tick(100.0)
	eq((idle.api as FakeOnline).calls.size(), 0, "ocioso: ninguna consulta")


func test_join_solo_and_group_request_shapes() -> void:
	var svc := _svc()
	svc.join(2, false)
	eq(_path(svc, 0), "join_queue", "RPC")
	var a := _args(svc, 0)
	eq(int(a.p_mode), 2, "modo")
	eq(a.p_version, GameServer.game_version(), "la version exacta del juego")
	check(not a.has("p_group"), "solo: sin grupo")
	var g := _svc()
	g.group = {"id": "g1", "mode": 2, "leader": ANA, "members": []}
	g.join(2, true)
	eq(_args(g, 0).p_group, "g1", "con grupo manda el id")
	var bad := _svc()
	var out := {}
	bad.join(4, false, func(r): out.merge(r))
	eq(out.get("error"), "invalid_mode", "modo invalido: ni sale a la red")
	eq((bad.api as FakeOnline).calls.size(), 0, "sin pedido")
	var nog := _svc()
	out = {}
	nog.join(2, true, func(r): out.merge(r))
	eq(out.get("error"), "group_not_found", "sin grupo no hay cola de grupo")


func test_search_then_match_announces_once() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	var found: Array = []
	svc.match_found.connect(func(info): found.append(info))
	api.queue_ok(null)  # join_queue
	api.queue_ok({"state": "searching", "mode": 2.0, "searching": 3.0, "wait": 12.0})
	svc.join(2, false)
	svc.poll()
	eq(svc.state, "searching", "buscando")
	eq(svc.searching, 3, "cuantos buscan")
	eq(svc.wait, 12, "espera")
	eq(found.size(), 0, "todavia sin partida")
	api.queue_ok(_matched())
	svc.poll()
	eq(svc.state, "matched", "partida")
	eq(found.size(), 1, "se anuncia")
	eq(found[0].id, MATCH, "con su id")
	eq(found[0].side, "red", "lado")
	check(found[0].is_host, "anfitrion")
	api.queue_ok(_matched())
	svc.poll()
	eq(found.size(), 1, "una sola vez por partida")
	eq(QueueService.side_map(found[0]), {ANA: "red", BETO: "blue"}, "mapa id -> lado")


func test_guest_waits_for_the_lobby_id() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	var lobbies: Array = []
	svc.lobby_published.connect(func(info): lobbies.append(info))
	api.queue_ok(_matched(BETO, null, "blue"))
	svc.poll()
	eq(lobbies.size(), 0, "invitado sin sala todavia")
	api.queue_ok(_matched(BETO, "109775241000000001", "blue"))
	svc.poll()
	eq(lobbies.size(), 1, "con sala publicada se avisa")
	eq(lobbies[0].lobby_id, "109775241000000001", "id exacto como texto")
	api.queue_ok(_matched(BETO, "109775241000000001", "blue"))
	svc.poll()
	eq(lobbies.size(), 1, "y una sola vez")


func test_publish_lobby_sends_the_id_as_text() -> void:
	var svc := _svc()
	(svc.api as FakeOnline).queue_ok(_matched())
	svc.poll()
	svc.publish_lobby(109775241000000001)
	eq(_path(svc, 1), "publish_lobby", "RPC")
	var a := _args(svc, 1)
	eq(a.p_match, MATCH, "partida")
	eq(a.p_lobby, "109775241000000001", "id de sala como texto: un double lo estropearia")


func test_report_once_and_free_the_slot() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	api.queue_ok(_matched())
	svc.poll()
	var out := {}
	svc.report_result("red", func(r): out.merge(r))
	eq(_path(svc, 1), "report_result", "RPC")
	eq(_args(svc, 1).p_winner, "red", "lado ganador")
	svc.report_result("red", func(r): out.merge(r))
	eq(api.calls.size(), 2, "no se informa dos veces")
	svc.finish()
	eq(_path(svc, 2), "leave_queue", "al terminar libera el lugar")
	eq(svc.state, "idle", "ocioso")
	check(svc.current.is_empty(), "sin partida")
	var none := _svc()
	out = {}
	none.report_result("red", func(r): out.merge(r))
	eq(out.get("error"), "not_in_match", "sin partida no hay reporte")


func test_abandon_leaves_the_queue_without_reporting() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	api.queue_ok(_matched())
	svc.poll()
	svc.abandon()
	eq(_path(svc, 1), "leave_queue", "libera el lugar")
	eq(svc.state, "idle", "ocioso")
	check(not api.calls.any(func(c): return str(c.url).ends_with("report_result")), "abandonar no informa nada")
	var s2 := _svc()
	s2.state = "searching"
	s2.cancel()
	eq(s2.state, "idle", "cancelar la busqueda")


func test_unavailable_keeps_the_state() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	api.queue_ok({"state": "searching", "mode": 1.0, "searching": 1.0, "wait": 1.0})
	svc.poll()
	api.down = true
	var out := {}
	svc.poll(func(r): out.merge(r))
	check(out.get("unavailable", false), "avisa que no hay servidor")
	eq(svc.state, "searching", "no se cae el estado por un corte")
	api.down = false
	api.clock += 100.0
	api.queue_ok({"state": "idle"})
	svc.poll()
	eq(svc.state, "idle", "si el servidor dice ocioso, ocioso")


func test_group_calls() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	svc.create_group(2)
	eq(_path(svc, 0), "create_group", "RPC")
	eq(int(_args(svc, 0).p_mode), 2, "modo")
	check(not _args(svc, 0).has("p_team"), "sin equipo")
	svc.create_group(3, "team-1")
	eq(_args(svc, 3).p_team, "team-1", "grupo de equipo")
	api.calls.clear()
	svc.group = {"id": "g1", "mode": 2, "leader": ANA, "members": []}
	svc.group_add(BETO)
	eq(_path(svc, 0), "group_add", "RPC")
	eq(_args(svc, 0).p_steam_id, BETO, "id como texto")
	var out := {}
	svc.group_add("abc", func(r): out.merge(r))
	eq(out.get("error"), "invalid_target", "id invalido: ni sale")
	eq(api.calls.size(), 3, "sin pedido extra (solo el alta y la recarga del grupo)")
	svc.group_confirm("g2")
	eq(_path(svc, 3), "group_confirm", "confirmar")
	svc.group_decline("g2")
	eq(_path(svc, 6), "group_decline", "rechazar")


func test_refresh_group_parses_group_and_invites() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	api.queue_ok({"id": "g1", "mode": 2.0, "team_id": null, "leader": ANA, "queued": false,
		"members": [{"steam_id": ANA, "name": "Ana", "confirmed": true}, {"steam_id": BETO, "name": "Beto", "confirmed": false}]})
	api.queue_ok([{"id": "g9", "mode": 3.0, "from": BETO, "from_name": "Beto", "team_name": null}])
	var n := [0]
	svc.changed.connect(func(): n[0] += 1)
	svc.refresh_group()
	eq(svc.group.id, "g1", "grupo")
	eq(svc.group.mode, 2, "modo entero")
	eq(svc.group_invites.size(), 1, "invitaciones")
	eq(svc.group_invites[0].mode, 3, "modo entero en las invitaciones")
	check(n[0] >= 1, "avisa el cambio")
	check(svc.in_group(), "en grupo")
	check(svc.is_leader(), "lider")
	api.queue_ok(null)
	api.queue_ok([])
	svc.refresh_group()
	check(not svc.in_group(), "sin grupo cuando el servidor devuelve null")
	check(svc.group.is_empty(), "grupo vacio")


func test_error_texts_never_show_raw_codes() -> void:
	for code in ["invalid_mode", "invalid_version", "already_in_group", "not_leader", "group_not_found", "group_full", "not_confirmed", "group_locked", "already_queued", "already_in_match", "not_in_match", "not_host", "invalid_lobby", "invalid_winner", "already_reported", "match_closed", "rate_limited", "not_member", "invalid_target", "invitee_inbox_full", "unavailable"]:
		var t := QueueService.error_text(code)
		check(t != "" and t != "Ocurrió un error inesperado." and not t.contains("_"), "texto para %s" % code)
	eq(QueueService.error_text("lo_que_sea"), "Ocurrió un error inesperado.", "desconocido: generico")


# ---------------------------------------------------------------- sign-in driver

func _session(api: FakeOnline) -> Array:
	var net := FakeSteam.new()
	var steam := net.user(7001, "Ana")
	var s := OnlineSession.new(api, steam)
	return [s, steam]


func _unsigned() -> FakeOnline:
	var api := _api()
	api.token = ""
	api.token_expires = 0.0
	api.steam_id = ""
	return api


func test_session_signs_in_then_names_the_player() -> void:
	var api := _unsigned()
	var pair := _session(api)
	var s: OnlineSession = pair[0]
	api.queue_ok({"token": "jwt-xyz", "expires_in": 3600, "steam_id": "7001"})
	api.queue_reply(204, "")
	s.start()
	eq(s.state, "signing_in", "pidiendo el ticket")
	(pair[1] as SteamBackend).run_callbacks()
	eq(s.state, "ready", "listo")
	eq(api.calls.size(), 2, "login y touch_player")
	check(api.calls[0].url.ends_with("/functions/v1/auth-steam"), "primero el login")
	check(api.calls[1].url.ends_with("/rpc/touch_player"), "despues el nombre")
	eq(JSON.parse_string(api.calls[1].body).p_name, "Ana", "con el nombre de Steam")
	check(s.is_ready(), "lista")


func test_session_refreshes_before_the_token_expires() -> void:
	var api := _unsigned()
	var pair := _session(api)
	var s: OnlineSession = pair[0]
	api.queue_ok({"token": "t1", "expires_in": 3600, "steam_id": "7001"})
	api.queue_reply(204, "")
	s.start()
	(pair[1] as SteamBackend).run_callbacks()
	var n := api.calls.size()
	s.tick()
	eq(api.calls.size(), n, "con token fresco no hace nada")
	api.clock += 3600.0 - OnlineApi.EXPIRY_MARGIN - OnlineSession.REFRESH_BEFORE + 1.0
	api.queue_ok({"token": "t2", "expires_in": 3600, "steam_id": "7001"})
	api.queue_reply(204, "")
	s.tick()
	eq(s.state, "signing_in", "5 minutos antes de vencer vuelve a iniciar sesion")
	(pair[1] as SteamBackend).run_callbacks()
	eq(api.token, "t2", "token nuevo")
	check(s.is_ready(), "lista de nuevo")


func test_session_failures_are_quiet_and_retried_later() -> void:
	var api := _unsigned()
	var pair := _session(api)
	var s: OnlineSession = pair[0]
	api.queue_reply(403, '{"error":"ticket_rejected"}')
	s.start()
	(pair[1] as SteamBackend).run_callbacks()
	eq(s.state, "failed", "fallo")
	check(s.note != "" and not s.note.contains("_"), "avisa con un texto claro")
	var n := api.calls.size()
	s.tick()
	eq(api.calls.size(), n, "no reintenta enseguida")
	api.clock += OnlineSession.RETRY_AFTER + 1.0
	api.queue_ok({"token": "t", "expires_in": 3600, "steam_id": "7001"})
	api.queue_reply(204, "")
	s.tick()
	(pair[1] as SteamBackend).run_callbacks()
	check(s.is_ready(), "reintenta pasado el plazo")
	# Steam down: no ticket, nothing sent
	var api2 := _unsigned()
	var pair2 := _session(api2)
	(pair2[1] as FakeSteam.FakeSteamBackend).online = false
	var s2: OnlineSession = pair2[0]
	s2.start()
	eq(s2.state, "off", "sin Steam queda apagado")
	eq(api2.calls.size(), 0, "y no sale a la red")


func test_session_is_off_when_online_is_disabled() -> void:
	var api := _unsigned()
	api.enabled = false
	var pair := _session(api)
	var s: OnlineSession = pair[0]
	s.start()
	eq(s.state, "off", "apagado")
	check(s.note != "", "con una nota")
	check(not s.usable(), "no usable")
