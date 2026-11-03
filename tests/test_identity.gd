extends TestBase
## Online identity (S13): the Steam web-API ticket on every backend, a stable mock id derived from the name, and the
## client side of auth-steam. The Steam signal and ticket shape are the ones GodotSteam 4.23.1 exposes
## (get_ticket_for_web_api(auth_ticket, result, ticket_size, ticket_buffer)); the real round trip needs a Steam client.

const BASE := 47710


func _ticket_of(b: SteamBackend) -> Dictionary:
	var got := {}
	b.web_auth_ticket.connect(func(ok: bool, ticket: String):
		got["ok"] = ok
		got["ticket"] = ticket)
	b.request_web_auth_ticket(OnlineApi.IDENTITY)
	b.run_callbacks()
	return got


func test_mock_id_is_stable_and_derived_from_the_name() -> void:
	var a := SteamBackendMock.new("Ana", BASE, 8)
	var a2 := SteamBackendMock.new("Ana", BASE, 8)
	var b := SteamBackendMock.new("Beto", BASE, 8)
	eq(a.my_id(), SteamBackendMock.id_for_name("Ana"), "el id sale del nombre")
	eq(a.my_id(), a2.my_id(), "dos copias con el mismo nombre dan el mismo id")
	check(a.my_id() != b.my_id(), "nombres distintos, ids distintos")
	check(a.my_id() > 76561199000000000 and a.my_id() < 76561200000000000, "dentro del rango de ids de cuentas")
	var fixed := SteamBackendMock.new("Ana", BASE, 8, 4242)
	eq(fixed.my_id(), 4242, "un id explicito sigue mandando")
	var anon := SteamBackendMock.new("", BASE, 8)
	check(anon.my_id() != 0, "sin nombre se inventa uno")
	for m in [a, a2, b, fixed, anon]:
		m.shutdown()


func test_mock_issues_a_dev_ticket_through_run_callbacks() -> void:
	var m := SteamBackendMock.new("Ana", BASE, 8)
	var got := {}
	m.web_auth_ticket.connect(func(ok: bool, ticket: String):
		got["ok"] = ok
		got["ticket"] = ticket)
	m.request_web_auth_ticket(OnlineApi.IDENTITY)
	check(got.is_empty(), "como el Steam real, la respuesta llega en run_callbacks")
	m.run_callbacks()
	check(got.get("ok", false), "el mock siempre puede")
	eq(got.get("ticket"), "dev:%d" % m.my_id(), "ticket de desarrollo con el id")
	m.shutdown()


func test_fake_steam_ticket_and_offline() -> void:
	var net := FakeSteam.new()
	var u := net.user(7001, "Ana")
	var got := _ticket_of(u)
	check(got.ok, "con Steam conectado")
	check(String(got.ticket) != "", "hay ticket")
	u.online = false
	got = _ticket_of(u)
	check(not got.ok, "sin Steam no hay ticket")
	eq(got.ticket, "", "vacio")


func test_base_backend_has_no_ticket() -> void:
	var b := SteamBackend.new()
	var got := _ticket_of(b)
	check(not got.ok and got.ticket == "", "sin Steam, falla")


func test_real_ticket_parsing_matches_godotsteam_shape() -> void:
	# get_ticket_for_web_api(auth_ticket: int, result: int, ticket_size: int, ticket_buffer: PackedByteArray)
	var buf := PackedByteArray([0x14, 0x00, 0x00, 0x00, 0xab, 0xcd, 0xef, 0x99, 0x99])
	eq(SteamBackendReal.parse_web_ticket(55, 55, 1, 7, buf), "140000" + "00abcdef", "hex del buffer hasta ticket_size")
	eq(SteamBackendReal.parse_web_ticket(55, 55, 1, 0, buf), "", "tamaño cero")
	eq(SteamBackendReal.parse_web_ticket(55, 55, 2, 7, buf), "", "resultado distinto de OK")
	eq(SteamBackendReal.parse_web_ticket(55, 56, 1, 7, buf), "", "ticket de otra solicitud")
	eq(SteamBackendReal.parse_web_ticket(55, 55, 1, 99, buf), "", "tamaño mayor que el buffer")
	eq(SteamBackendReal.parse_web_ticket(0, 0, 1, 7, buf), "", "handle invalido (0)")


func _signed(api: FakeOnline, steam_id := "7001") -> void:
	api.queue_ok({"token": "jwt-xyz", "expires_in": 3600, "steam_id": steam_id})


func test_sign_in_stores_the_session() -> void:
	var api := FakeOnline.new()
	api.base_url = "http://127.0.0.1:54321"
	api.anon_key = "anon"
	api.enabled = true
	api.clock = 1000.0
	_signed(api)
	var out := {}
	api.sign_in("abcd", func(r: Dictionary): out.merge(r))
	check(out.ok, "ok")
	check(api.signed_in(), "con sesion")
	eq(api.token, "jwt-xyz", "token")
	eq(api.token_expires, 1000.0 + 3600.0 - OnlineApi.EXPIRY_MARGIN, "vence antes que el token, con margen")
	eq(api.steam_id, "7001", "id como texto")
	var c: Dictionary = api.calls[0]
	eq(c.url, "http://127.0.0.1:54321/functions/v1/auth-steam", "ruta de la funcion")
	eq(JSON.parse_string(c.body), {"ticket": "abcd"}, "manda el ticket")
	check(c.headers.has("Authorization: Bearer anon"), "el login va con la clave anonima, no con un token")
	api.sign_out()
	check(not api.signed_in() and api.steam_id == "", "sign_out limpia")
	api.free()


func test_sign_in_failures_leave_no_session() -> void:
	var api := FakeOnline.new()
	api.base_url = "http://127.0.0.1:54321"
	api.anon_key = "anon"
	api.enabled = true
	api.clock = 1000.0
	api.queue_reply(403, '{"error":"dev_login_disabled"}')
	var out := {}
	api.sign_in("dev:7001", func(r: Dictionary): out.merge(r))
	check(not out.ok, "falla")
	eq(out.error, "dev_login_disabled", "el servidor lo explica")
	check(not api.signed_in(), "sin sesion")
	api.queue_reply(200, '{"nothing":true}')
	out = {}
	api.sign_in("abcd", func(r: Dictionary): out.merge(r))
	check(not out.ok and out.error == "bad_response", "una respuesta sin token no es sesion")
	check(not api.signed_in(), "sin sesion")
	api.down = true
	out = {}
	api.sign_in("abcd", func(r: Dictionary): out.merge(r))
	check(out.unavailable, "Supabase caido: no disponible")
	api.free()


func test_sign_in_with_empty_ticket_does_not_call() -> void:
	var api := FakeOnline.new()
	api.base_url = "http://127.0.0.1:54321"
	api.anon_key = "anon"
	api.enabled = true
	var out := {}
	api.sign_in("", func(r: Dictionary): out.merge(r))
	eq(out.get("error"), "no_ticket", "sin ticket")
	eq(api.calls.size(), 0, "no se envia nada")
	api.free()
