extends TestBase
## Client side of the server teams (S14): validation that mirrors the server, RPC argument shapes, parsing, and what
## happens when Supabase is unavailable. The rules themselves are tested in supabase/tests (pgTAP); FakeOnline only
## replaces the transport, so these run the real OnlineApi.

const ANA := "76561199000000001"
const BETO := "76561199000000002"


func _svc(clock := 1000.0) -> TeamService:
	var api := FakeOnline.new()
	api.base_url = "http://127.0.0.1:54321"
	api.anon_key = "anon"
	api.enabled = true
	api.clock = clock
	api.token = "jwt"
	api.token_expires = 99999.0
	api.steam_id = ANA
	return TeamService.new(api)


func _team(id := "t1", mode := 2, captain := ANA) -> Dictionary:
	return {"id": id, "mode": float(mode), "name": "Los Lobos", "captain": captain,
		"members": [{"steam_id": ANA, "name": "Ana", "captain": captain == ANA}, {"steam_id": BETO, "name": "Beto", "captain": captain == BETO}],
		"invites": []}


func _run(svc: TeamService, f: Callable) -> Dictionary:
	var out := {}
	f.call(func(r: Dictionary): out.merge(r))
	return out


func _args(svc: TeamService, i: int) -> Dictionary:
	return JSON.parse_string((svc.api as FakeOnline).calls[i].body)


func _path(svc: TeamService, i: int) -> String:
	return (svc.api as FakeOnline).calls[i].url.get_slice("/rpc/", 1)


func test_clean_name_mirrors_the_server() -> void:
	eq(TeamService.clean_name("Los\u202e   Lobos "), "Los Lobos", "bidi fuera, espacios colapsados")
	eq(TeamService.clean_name("\u202e \u2066"), "", "solo controles: invalido")
	eq(TeamService.clean_name("ab"), "", "corto")
	eq(TeamService.clean_name("abc"), "abc", "minimo")
	eq(TeamService.clean_name("x".repeat(20)), "x".repeat(20), "maximo")
	eq(TeamService.clean_name("x".repeat(21)), "", "largo")
	eq(TeamService.clean_name("Tab\tNew\nLine"), "Tab New Line", "controles como espacio")
	eq(TeamService.clean_name("a\u200bb\u200fc"), "a b c", "ancho cero y marcas de direccion")
	eq(TeamService.clean_name("Ñandú ⚔"), "Ñandú ⚔", "unicode normal se conserva")
	check(TeamService.valid_mode(2) and TeamService.valid_mode(3), "2v2 y 3v3")
	check(not TeamService.valid_mode(1) and not TeamService.valid_mode(4), "1v1 y 4v4 no tienen equipos")
	eq(TeamService.capacity(2), 4, "2v2 admite 4")
	eq(TeamService.capacity(3), 6, "3v3 admite 6")


func test_refresh_parses_teams_and_invites() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	api.queue_ok([_team()])
	api.queue_ok([{"id": "i1", "team_id": "t9", "team_name": "Cuervos", "mode": 3.0, "from": BETO, "from_name": "Beto", "expires_at": "2026-12-01T00:00:00+00:00"}])
	var fired := [0]
	svc.changed.connect(func(): fired[0] += 1)
	var r := _run(svc, svc.refresh)
	check(r.ok, "ok")
	eq(_path(svc, 0), "my_teams", "primero equipos")
	eq(_path(svc, 1), "my_invites", "despues invitaciones")
	eq(svc.teams.size(), 1, "un equipo")
	eq(svc.teams[0].mode, 2, "modalidad como entero")
	eq(svc.teams[0].captain, ANA, "ids como texto")
	eq(svc.invites[0].mode, 3, "modalidad de la invitacion como entero")
	eq(svc.team_for_mode(2).id, "t1", "equipo por modalidad")
	check(svc.team_for_mode(3).is_empty(), "sin equipo 3v3")
	check(svc.is_captain(svc.teams[0]), "capitana")
	eq(fired[0], 1, "avisa una vez")
	api.free()


func test_mutations_validate_send_text_ids_and_refresh() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	var r := _run(svc, func(cb): svc.create_team(1, "Lobos", cb))
	eq(r.error, "invalid_mode", "modo invalido sin red")
	r = _run(svc, func(cb): svc.create_team(2, "ab", cb))
	eq(r.error, "invalid_name", "nombre invalido sin red")
	r = _run(svc, func(cb): svc.invite("t1", "12x", cb))
	eq(r.error, "invalid_target", "id invalido sin red")
	eq(api.calls.size(), 0, "nada salio")

	api.queue_ok("t-new")
	api.queue_ok([_team("t-new")])
	api.queue_ok([])
	r = _run(svc, func(cb): svc.create_team(2, "  Los\u202e Lobos ", cb))
	check(r.ok, "crea")
	eq(r.data, "t-new", "devuelve el id")
	eq(_path(svc, 0), "create_team", "RPC")
	eq(_args(svc, 0), {"p_mode": 2.0, "p_name": "Los Lobos"}, "nombre ya limpio")
	eq(_path(svc, 1), "my_teams", "luego refresca")
	eq(svc.teams.size(), 1, "y queda reflejado")

	api.queue_ok("i-new")
	api.queue_ok([_team()])
	api.queue_ok([])
	r = _run(svc, func(cb): svc.invite("t1", BETO, cb))
	check(r.ok, "invita")
	eq(_args(svc, 3), {"p_team": "t1", "p_steam_id": BETO}, "el id de Steam viaja como texto")
	eq(typeof(_args(svc, 3).p_steam_id), TYPE_STRING, "texto, no numero (un double lo corromperia)")
	api.free()


func test_every_action_maps_to_its_rpc() -> void:
	var cases := [
		["accept", func(s, cb): s.accept_invite("i1", cb), "accept_invite", {"p_invite": "i1"}],
		["decline", func(s, cb): s.decline_invite("i1", cb), "decline_invite", {"p_invite": "i1"}],
		["cancel", func(s, cb): s.cancel_invite("i1", cb), "cancel_invite", {"p_invite": "i1"}],
		["leave", func(s, cb): s.leave_team("t1", cb), "leave_team", {"p_team": "t1"}],
		["kick", func(s, cb): s.kick_member("t1", BETO, cb), "kick_member", {"p_team": "t1", "p_steam_id": BETO}],
		["transfer", func(s, cb): s.transfer_captain("t1", BETO, cb), "transfer_captain", {"p_team": "t1", "p_steam_id": BETO}],
		["disband", func(s, cb): s.disband_team("t1", cb), "disband_team", {"p_team": "t1"}],
	]
	for c in cases:
		var svc := _svc()
		var api := svc.api as FakeOnline
		api.queue_ok(null)
		api.queue_ok([])
		api.queue_ok([])
		var r := _run(svc, func(cb): c[1].call(svc, cb))
		check(r.ok, "%s ok" % c[0])
		eq(_path(svc, 0), c[2], "%s: RPC" % c[0])
		eq(_args(svc, 0), c[3], "%s: argumentos" % c[0])
		eq(api.calls.size(), 3, "%s: accion y refresco" % c[0])
		api.free()


func test_server_errors_do_not_refresh_and_have_spanish_text() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	api.queue_reply(400, '{"code":"P0001","message":"team_full"}')
	var r := _run(svc, func(cb): svc.invite("t1", BETO, cb))
	eq(r.error, "team_full", "codigo")
	eq(api.calls.size(), 1, "sin refresco tras un error")
	eq(TeamService.error_text("team_full"), "El equipo está completo.", "texto del jugador")
	for code in ["invalid_mode", "invalid_name", "name_taken", "already_in_team", "already_invited", "not_captain", "not_member", "team_not_found", "invite_not_found", "invalid_target", "invitee_inbox_full", "captain_must_transfer_or_disband", "not_signed_in", "session_expired", "unavailable", "disabled"]:
		check(TeamService.error_text(code) != "" and TeamService.error_text(code) != TeamService.error_text("zzz"), "%s tiene texto propio" % code)
	check(TeamService.error_text("zzz").contains("inesperado"), "los desconocidos no muestran el codigo crudo")
	api.free()


func test_unavailable_backend_keeps_state_and_never_throws() -> void:
	var svc := _svc()
	var api := svc.api as FakeOnline
	api.queue_ok([_team()])
	api.queue_ok([])
	_run(svc, svc.refresh)
	eq(svc.teams.size(), 1, "estado previo")
	api.down = true
	var r := _run(svc, svc.refresh)
	check(r.unavailable and not r.ok, "no disponible")
	eq(svc.teams.size(), 1, "conserva el ultimo estado conocido")
	check(not svc.online(), "online() lo refleja")
	r = _run(svc, func(cb): svc.create_team(3, "Dragones", cb))
	check(r.unavailable, "crear tambien")
	eq(TeamService.error_text(r.error), "No se pudo conectar con el servidor de equipos. Probá más tarde.", "mensaje claro")
	api.free()


func test_disabled_api_is_quiet() -> void:
	var api := FakeOnline.new()  # enabled follows Online.ENABLED (false)
	api.enabled = Online.ENABLED
	var svc := TeamService.new(api)
	var r := _run(svc, svc.refresh)
	eq(r.error, "disabled", "apagado")
	eq(api.calls.size(), 0, "sin trafico")
	check(not svc.online(), "no esta online")
	api.free()
