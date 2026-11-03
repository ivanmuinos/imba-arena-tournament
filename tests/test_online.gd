extends TestBase
## Online client (S12): shipped disabled, config parsing, and the unavailable state: a down or paused Supabase fails
## fast and quietly instead of breaking the game. FakeOnline replaces only the transport, so response handling is real.


func _api(clock := 1000.0) -> FakeOnline:
	var a := FakeOnline.new()
	a.base_url = "http://127.0.0.1:54321"
	a.anon_key = "anon-test-key"
	a.enabled = true
	a.clock = clock
	return a


func _result(api: FakeOnline, fn: String, args := {}) -> Dictionary:
	var out := {}
	api.call_rpc(fn, args, func(r: Dictionary): out.merge(r))
	return out


func test_online_ships_disabled() -> void:
	eq(Online.ENABLED, false, "Online.ENABLED apagado hasta S17")
	check(not Online.enabled(), "enabled() es falso con la bandera apagada")
	var api := OnlineApi.new()
	eq(api.enabled, false, "un cliente nuevo hereda la bandera")
	var out := {}
	api.call_rpc("anything", {}, func(r: Dictionary): out.merge(r))
	eq(out.get("error"), "disabled", "apagado: no sale a la red")
	check(out.get("unavailable", false), "y se presenta como no disponible")
	api.free()


func test_config_requires_url_and_key() -> void:
	check(not Online.config_valid({}), "vacio")
	check(not Online.config_valid({"url": "http://x", "anon_key": ""}), "sin clave")
	check(not Online.config_valid({"url": "", "anon_key": "k"}), "sin url")
	check(not Online.config_valid({"url": "ftp://x", "anon_key": "k"}), "esquema raro")
	check(Online.config_valid({"url": "https://abc.supabase.co", "anon_key": "k"}), "https ok")
	check(Online.config_valid({"url": "http://127.0.0.1:54321", "anon_key": "k"}), "local ok")
	check(not Online.config_valid({"url": "http://example.com", "anon_key": "k"}), "http solo para esta maquina")
	check(not Online.config_valid({"url": "http://127.0.0.1.evil.com", "anon_key": "k"}), "prefijo engañoso")
	eq(Online.merge_env({"url": "u", "anon_key": "k"}, {"IMBA_ONLINE_URL": "http://e", "IMBA_ONLINE_ANON_KEY": "ek"}), {"url": "http://e", "anon_key": "ek"}, "el entorno pisa el archivo")
	eq(Online.merge_env({"url": "u", "anon_key": "k"}, {}), {"url": "u", "anon_key": "k"}, "sin entorno queda el archivo")
	var bundled := Online.config()
	check(bundled.has("url") and bundled.has("anon_key"), "data/online.json tiene url y anon_key")


func test_rpc_builds_request_and_parses_json() -> void:
	var api := _api()
	api.token = "jwt-abc"
	api.token_expires = 5000.0
	api.queue_reply(200, '{"id":"t1"}')
	var r := _result(api, "create_team", {"p_mode": 2, "p_name": "Lobos"})
	check(r.ok, "ok")
	eq(r.data, {"id": "t1"}, "cuerpo JSON")
	var c: Dictionary = api.calls[0]
	eq(c.url, "http://127.0.0.1:54321/rest/v1/rpc/create_team", "ruta de la RPC")
	eq(c.method, HTTPClient.METHOD_POST, "POST")
	eq(JSON.parse_string(c.body), {"p_mode": 2.0, "p_name": "Lobos"}, "argumentos en el cuerpo")
	check(c.headers.has("apikey: anon-test-key"), "clave anonima")
	check(c.headers.has("Authorization: Bearer jwt-abc"), "token del jugador")
	check(c.headers.has("Content-Type: application/json"), "tipo de contenido")
	api.free()


func test_rpc_needs_a_session_and_does_not_hit_the_network_without_one() -> void:
	var api := _api()
	var r := _result(api, "create_team")
	eq(r.error, "not_signed_in", "sin sesion")
	eq(api.calls.size(), 0, "no se envio nada")
	api.token = "jwt"
	api.token_expires = 999.0  # already expired at clock 1000
	r = _result(api, "create_team")
	eq(r.error, "session_expired", "token vencido")
	eq(api.calls.size(), 0, "tampoco se envio")
	check(not api.signed_in(), "signed_in() lo refleja")
	api.free()


func test_business_errors_are_not_outages() -> void:
	var api := _api()
	api.token = "t"
	api.token_expires = 5000.0
	api.queue_reply(400, '{"code":"P0001","message":"team_full","details":null,"hint":null}')
	var r := _result(api, "invite_to_team")
	check(not r.ok, "falla")
	eq(r.error, "team_full", "codigo del servidor")
	check(not r.get("unavailable", false), "no es una caida")
	check(api.available(), "el servicio sigue disponible")
	api.free()


func test_outage_marks_unavailable_then_fails_fast_then_recovers() -> void:
	var api := _api()
	api.token = "t"
	api.token_expires = 99999.0
	var changes: Array = []
	api.availability_changed.connect(func(a: bool): changes.append(a))
	api.down = true
	var r := _result(api, "my_teams")
	eq(r.error, "unavailable", "sin red")
	check(r.unavailable, "marcado")
	check(not api.available(), "no disponible")
	eq(changes, [false], "avisa una vez")
	var sent := api.calls.size()
	r = _result(api, "my_teams")
	eq(r.error, "unavailable", "en enfriamiento sigue fallando")
	eq(api.calls.size(), sent, "sin tocar la red")
	api.clock += OnlineApi.COOLDOWN + 1.0
	check(api.available(), "pasado el enfriamiento vuelve a intentar")
	api.down = false
	api.queue_reply(200, "[]")
	r = _result(api, "my_teams")
	check(r.ok, "se recupero")
	eq(changes, [false, true], "avisa la recuperacion")
	api.free()


func test_classify_covers_outages_and_paused_projects() -> void:
	var down := OnlineApi.classify(HTTPRequest.RESULT_TIMEOUT, 0, "")
	check(down.unavailable and not down.ok, "timeout")
	down = OnlineApi.classify(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	check(down.unavailable, "sin conexion")
	down = OnlineApi.classify(HTTPRequest.RESULT_SUCCESS, 503, "upstream down")
	check(down.unavailable, "503")
	down = OnlineApi.classify(HTTPRequest.RESULT_SUCCESS, 540, "<html>paused</html>")
	check(down.unavailable, "540 de proyecto pausado")
	var junk := OnlineApi.classify(HTTPRequest.RESULT_SUCCESS, 200, "<html>no json</html>")
	check(junk.unavailable, "200 que no es JSON: algo intermedio contesta (portal, proxy)")
	var empty := OnlineApi.classify(HTTPRequest.RESULT_SUCCESS, 204, "")
	check(empty.ok and empty.data == null, "204 sin cuerpo")
	var jwt := OnlineApi.classify(HTTPRequest.RESULT_SUCCESS, 401, '{"code":"PGRST301","message":"JWT expired"}')
	eq(jwt.error, "session_expired", "401 pide volver a entrar")
	check(not jwt.get("unavailable", false), "no es caida")
	var denied := OnlineApi.classify(HTTPRequest.RESULT_SUCCESS, 403, '{"code":"42501","message":"permission denied for table teams"}')
	eq(denied.error, "forbidden", "403")
	var coded := OnlineApi.classify(HTTPRequest.RESULT_SUCCESS, 403, '{"error":"ticket_rejected"}')
	eq(coded.error, "ticket_rejected", "un 403 con codigo del servidor lo conserva")
	var weird := OnlineApi.classify(HTTPRequest.RESULT_SUCCESS, 400, '{"message":"x y z <b>"}')
	eq(weird.error, "error", "un mensaje que no es un codigo no se muestra tal cual")


func test_ids_travel_as_text() -> void:
	# A Steam id does not fit in a JSON double: Godot parses numbers as floats and would corrupt it.
	var big := 76561199000000123
	eq(int(str(big)), big, "el texto conserva el id")
	check(int(float(big)) != big, "un float lo corromperia (por eso el servidor devuelve ids como texto)")
