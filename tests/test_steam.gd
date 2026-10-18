extends TestBase
## Steam layer against a fake Steam (real Steam cannot be tested here): backend selection/fallback, lobby state,
## the transport (peer ids, lobby-member filtering, disconnects) and a whole lobby -> match flow over Steam messages.


func _pump(backends: Array, server: GameServer, clients: Array, ms: float) -> void:
	var t := 0.0
	while t < ms:
		for b in backends:
			b.run_callbacks()
		if server != null:
			server.process(16.0)
		for c in clients:
			c.poll(16.0)
		t += 16.0


# ---------------------------------------------------------------- selection / fallback

func test_net_choice_falls_back_to_enet_when_steam_is_missing() -> void:
	eq(NetChoice.resolve("enet", true).use, "enet", "pidió ENet")
	eq(NetChoice.resolve("steam", true).use, "steam", "Steam disponible")
	var r := NetChoice.resolve("steam", false, "Abrí el cliente de Steam")
	eq(r.use, "enet", "sin Steam: ENet")
	check(r.note.contains("Steam no está disponible") and r.note.contains("Abrí el cliente"), "explica por qué (%s)" % r.note)
	eq(NetChoice.resolve("steam", false).note.is_empty(), false, "siempre hay aviso")


func test_player_name_prefers_persona_name_on_steam() -> void:
	eq(NetChoice.player_name("Ana", "PersonaSteam", true), "PersonaSteam", "nombre de Steam")
	eq(NetChoice.player_name("Ana", "PersonaSteam", false), "Ana", "sin Steam: el escrito")
	eq(NetChoice.player_name("Ana", "", true), "Ana", "sin persona: el escrito")
	eq(NetChoice.player_name("", "x".repeat(40), true).length(), 16, "se recorta a 16")


func test_unavailable_backend_is_inert() -> void:
	var b := SteamBackend.new()
	check(not b.available(), "la base no está disponible")
	eq(b.poll_messages(), [], "sin mensajes")
	check(not SteamBackendReal.new().available(), "sin cliente de Steam (este entorno): no disponible, sin errores")


# ---------------------------------------------------------------- lobbies

func test_host_creates_lobby_and_publishes_settings() -> void:
	var net := FakeSteam.new()
	var host := net.user(76561198000000001, "Anfitrión")
	var lobbies := SteamLobbies.new(host)
	var got := [0]
	lobbies.hosted.connect(func(id): got[0] = id)
	lobbies.host(true, {"mode": 3, "map": "tomb", "name": "Anfitrión"})
	eq(lobbies.state, "hosting", "creando")
	host.run_callbacks()
	check(got[0] != 0, "recibe el id del lobby")
	eq(lobbies.state, "in_lobby", "en la sala")
	var d: Dictionary = net.lobbies[got[0]].data
	eq([d.version, d.mode, d.map, d.name], [GameServer.game_version(), "3", "tomb", "Anfitrión"], "datos publicados")


func test_list_shows_only_same_version_and_not_full_lobbies() -> void:
	var net := FakeSteam.new()
	var a := net.user(1001, "A")
	var b := net.user(1002, "B")
	var seeker := net.user(1003, "C")
	var la := SteamLobbies.new(a)
	la.host(false, {"name": "A"})
	a.run_callbacks()
	var lb := SteamLobbies.new(b)
	lb.host(false, {"name": "B"})
	b.run_callbacks()
	net.lobbies[lb.lobby_id].data.version = "0.0.1"  # a friend with an old build
	var lobbies := SteamLobbies.new(seeker)
	var shown := [[]]
	lobbies.list_changed.connect(func(e): shown[0] = e)
	lobbies.refresh()
	seeker.run_callbacks()
	eq(shown[0].size(), 1, "una sala de la misma versión")
	eq(shown[0][0].owner, 1001, "es la de A")
	net.lobbies[la.lobby_id].max = 1  # now full
	lobbies.refresh()
	seeker.run_callbacks()
	eq(shown[0].size(), 0, "llena: no se muestra")


func test_join_from_list_and_overlay_invite() -> void:
	var net := FakeSteam.new()
	var host := net.user(2001, "H")
	var guest := net.user(2002, "G")
	var friend := net.user(2003, "F")
	var lh := SteamLobbies.new(host)
	lh.host(true, {"name": "H"})
	host.run_callbacks()
	var lg := SteamLobbies.new(guest)
	var joined := [[0, 0]]
	lg.joined.connect(func(id, owner): joined[0] = [id, owner])
	lg.join(lh.lobby_id)
	guest.run_callbacks()
	eq(joined[0], [lh.lobby_id, 2001], "entra y conoce al dueño")
	eq(lg.state, "in_lobby", "estado")
	# Overlay invite: accepting it joins automatically.
	var lf := SteamLobbies.new(friend)
	var f_joined := [false]
	lf.joined.connect(func(_i, _o): f_joined[0] = true)
	net.invite(lh.lobby_id, 2003)
	friend.run_callbacks()  # join_requested fires
	friend.run_callbacks()  # lobby_joined fires
	check(f_joined[0], "la invitación de la superposición entra sola")
	# Busy players do not hop rooms.
	var failed := [""]
	lg.failed.connect(func(t): failed[0] = t)
	net.invite(lh.lobby_id, 2002)
	guest.run_callbacks()
	check(failed[0] != "", "ocupado: avisa en vez de cambiar de sala")


func test_join_full_lobby_fails_with_message() -> void:
	var net := FakeSteam.new()
	var host := net.user(3001, "H")
	var guest := net.user(3002, "G")
	var lh := SteamLobbies.new(host)
	lh.host(false, {})
	host.run_callbacks()
	net.lobbies[lh.lobby_id].max = 1
	var lg := SteamLobbies.new(guest)
	var msg := [""]
	lg.failed.connect(func(t): msg[0] = t)
	lg.join(lh.lobby_id)
	guest.run_callbacks()
	check(msg[0].contains("llena"), "avisa (%s)" % msg[0])
	eq(lg.state, "idle", "vuelve a idle")


# ---------------------------------------------------------------- transport

func test_transport_maps_steam_ids_to_peer_ids_and_ignores_strangers() -> void:
	var net := FakeSteam.new()
	var host := net.user(4001, "H")
	var guest := net.user(4002, "G")
	var stranger := net.user(4003, "X")
	var lh := SteamLobbies.new(host)
	lh.host(false, {})
	host.run_callbacks()
	var lg := SteamLobbies.new(guest)
	lg.join(lh.lobby_id)
	guest.run_callbacks()
	var st := SteamTransport.host(host, lh.lobby_id)
	var connected := []
	var msgs := []
	st.peer_connected.connect(func(id): connected.append(id))
	st.message.connect(func(from, m): msgs.append([from, m.t]))
	var ct := SteamTransport.join(guest, lh.lobby_id, 4001)
	ct.poll()
	ct.send(1, {"t": "hola"})
	stranger.send(4001, Wire.encode({"t": "intruso"}), true)
	st.poll()
	eq(connected, [2], "el invitado es el peer 2 (el servidor es 1)")
	eq(msgs, [[2, "hola"]], "el extraño que no está en el lobby se ignora")
	check(st.peer_for(4002) == 2 and st.steam_id_of(2) == 4002, "mapeo en los dos sentidos")
	st.send(2, {"t": "respuesta"})
	var got := []
	ct.message.connect(func(from, m): got.append([from, m.t]))
	ct.poll()
	eq(got, [[1, "respuesta"]], "el cliente ve al servidor como peer 1")
	check(host.accepted.has(4002), "se aceptó la sesión")


func test_transport_reports_disconnects_from_both_sides() -> void:
	var net := FakeSteam.new()
	var host := net.user(5001, "H")
	var guest := net.user(5002, "G")
	var lh := SteamLobbies.new(host)
	lh.host(false, {})
	host.run_callbacks()
	SteamLobbies.new(guest).join(lh.lobby_id)
	guest.run_callbacks()
	var st := SteamTransport.host(host, lh.lobby_id)
	var ct := SteamTransport.join(guest, lh.lobby_id, 5001)
	var events := []
	st.peer_disconnected.connect(func(id): events.append("server vio salir %d" % id))
	ct.peer_disconnected.connect(func(id): events.append("cliente perdió %d" % id))
	ct.poll()
	ct.send(1, {"t": "hola"})
	st.poll()
	net.backends[5002].leave_lobby(lh.lobby_id)  # the guest quits
	host.run_callbacks()
	eq(events, ["server vio salir 2"], "el servidor se entera cuando el invitado sale del lobby")
	events.clear()
	var net2 := FakeSteam.new()
	var h2 := net2.user(6001, "H")
	var g2 := net2.user(6002, "G")
	var l2 := SteamLobbies.new(h2)
	l2.host(false, {})
	h2.run_callbacks()
	SteamLobbies.new(g2).join(l2.lobby_id)
	g2.run_callbacks()
	var c2 := SteamTransport.join(g2, l2.lobby_id, 6001)
	c2.peer_disconnected.connect(func(id): events.append("cliente perdió %d" % id))
	net2.backends[6001].leave_lobby(l2.lobby_id)  # the host quits
	g2.run_callbacks()
	eq(events, ["cliente perdió 1"], "el cliente se entera cuando el anfitrión se va")


# ---------------------------------------------------------------- whole flow

func test_full_match_flow_over_steam() -> void:
	var net := FakeSteam.new()
	var host_b := net.user(7001, "Anfi")
	var guest_b := net.user(7002, "Amigo")
	var lh := SteamLobbies.new(host_b)
	lh.host(true, {"mode": 2, "map": "tomb", "name": "Anfi"})
	host_b.run_callbacks()
	var server := GameServer.new({"map": "tomb"})
	server.attach(SteamTransport.host(host_b, lh.lobby_id))
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var host_c := GameClient.new()
	host_c.attach(link[1], {"name": NetChoice.player_name("x", host_b.persona_name(), true), "cls": "mage", "pref": "red"})
	var lg := SteamLobbies.new(guest_b)
	lg.join(lh.lobby_id)
	guest_b.run_callbacks()
	var guest_c := GameClient.new()
	guest_c.attach(SteamTransport.join(guest_b, lh.lobby_id, host_b.lobby_owner(lh.lobby_id)), {"name": NetChoice.player_name("x", guest_b.persona_name(), true), "cls": "warrior", "pref": "blue"})
	_pump([host_b, guest_b], server, [host_c, guest_c], 400.0)
	eq(server.players.size(), 2, "los dos están en el lobby")
	eq(guest_c.lobby.members.map(func(m): return m.name).has("Amigo"), true, "con su nombre de Steam")
	check(host_c.is_host and not guest_c.is_host, "sólo el dueño de la sala es anfitrión")
	host_c.send_start()
	_pump([host_b, guest_b], server, [host_c, guest_c], 200.0)
	check(host_c.in_match and guest_c.in_match, "los dos reciben la partida")
	eq(guest_c.map_id, "tomb", "mapa de la sala")
	var states := [0]
	guest_c.state_received.connect(func(_s): states[0] += 1)
	_pump([host_b, guest_b], server, [host_c, guest_c], 1000.0)
	check(states[0] > 20, "el invitado recibe snapshots por Steam (%d)" % states[0])
	guest_c.send_input(0.0, -1.0, 0.0, -30.0)
	_pump([host_b, guest_b], server, [host_c, guest_c], 100.0)
	server.shutdown()


func test_steam_client_with_other_game_version_gets_the_clear_error() -> void:
	var net := FakeSteam.new()
	var host_b := net.user(8001, "H")
	var guest_b := net.user(8002, "G")
	var lh := SteamLobbies.new(host_b)
	lh.host(false, {})
	host_b.run_callbacks()
	var server := GameServer.new({})
	server.attach(SteamTransport.host(host_b, lh.lobby_id))
	SteamLobbies.new(guest_b).join(lh.lobby_id)
	guest_b.run_callbacks()
	var gc := GameClient.new()
	gc.hello_version = "0.0.1"
	var errs := []
	gc.server_error.connect(func(t): errs.append(t))
	gc.attach(SteamTransport.join(guest_b, lh.lobby_id, 8001), {"name": "G", "cls": "mage", "pref": "any"})
	_pump([host_b, guest_b], server, [gc], 300.0)
	check(errs.size() == 1 and errs[0].contains("Versión distinta"), "mismo mensaje claro que en ENet (%s)" % str(errs))
	server.shutdown()
