extends TestBase
## The Steam stand-in for development (`--steam-mock`): game copies on this machine or the LAN find each other over UDP
## and behave like Steam friends with lobbies and peer-to-peer messages. Two instances in one process, real sockets.

const BASE := 47700  # away from the game's default range, so a running copy does not interfere


func _pair() -> Array:
	var a := SteamBackendMock.new("Ana", BASE, 4, 7001)
	var b := SteamBackendMock.new("Beto", BASE, 4, 7002)
	return [a, b]


## Pumps both until `cond` holds (or ~1.5 s): announcements, packets and queued callbacks.
func _until(list: Array, cond: Callable) -> bool:
	for i in 150:
		for m in list:
			m.announce()
			m.run_callbacks()
		if cond.call():
			return true
		OS.delay_msec(10)
	return false


func _close(list: Array) -> void:
	for m in list:
		m.shutdown()


func test_mock_is_available_and_explains_itself() -> void:
	var a := SteamBackendMock.new("Ana", BASE, 4, 7001)
	check(a.available(), "siempre disponible")
	eq(a.persona_name(), "Ana", "nombre")
	eq(a.my_id(), 7001, "id fijo para pruebas")
	eq(a.app_id(), 480, "se hace pasar por el app id de prueba")
	check(a.status_text().contains("simulado"), "dice que es simulado (%s)" % a.status_text())
	var c := SteamBackendMock.new("", BASE, 4)
	check(c.persona_name() != "" and c.my_id() != 0, "sin nombre ni id: inventa unos")
	_close([a, c])


func test_instances_find_each_other_as_friends_with_presence() -> void:
	var p := _pair()
	var a: SteamBackendMock = p[0]
	var b: SteamBackendMock = p[1]
	check(_until(p, func(): return a.friends().size() == 1 and b.friends().size() == 1), "se encuentran")
	var f: Dictionary = a.friends()[0]
	eq([f.id, f.name, f.state, f.app], [7002, "Beto", 1, 480], "Beto, en línea, en el juego")
	eq(a.persona_of(7002), "Beto", "nombre de otro jugador")
	var changed := [0]
	a.friends_changed.connect(func(): changed[0] += 1)
	b.set_presence({"status": "En el menú", "connect": ""})
	check(_until(p, func(): return str(a.friends()[0].status) == "En el menú"), "ve su estado")
	check(changed[0] > 0, "avisa que cambió")
	var got := []
	a.avatar_ready.connect(func(id, tex): got.append([id, tex != null]))
	a.request_avatar(7002)
	a.run_callbacks()
	eq(got, [[7002, true]], "un avatar generado")
	b.shutdown()
	check(_until([a], func(): return int(a.friends()[0].state) == 0), "al cerrarse queda desconectado")
	a.shutdown()


func test_lobby_create_list_join_and_messages() -> void:
	var p := _pair()
	var a: SteamBackendMock = p[0]
	var b: SteamBackendMock = p[1]
	_until(p, func(): return a.friends().size() == 1 and b.friends().size() == 1)
	var created := [0]
	a.lobby_created.connect(func(id, ok): if ok: created[0] = id)
	a.create_lobby(false, 4)
	a.run_callbacks()
	var lobby: int = created[0]
	check(lobby != 0, "crea la sala")
	a.set_lobby_data(lobby, "version", "9.9")
	a.set_lobby_data(lobby, "name", "Sala de Ana")
	eq(a.lobby_owner(lobby), 7001, "dueña")
	var listed := []
	b.lobby_list.connect(func(e): listed.assign(e))
	check(_until(p, func():
		b.request_lobby_list("9.9")
		return listed.size() == 1), "Beto la ve en la lista")
	eq([listed[0].id, listed[0].name, listed[0].members, listed[0].max, listed[0].version], [lobby, "Sala de Ana", 1, 4, "9.9"], "datos")
	check(int(b.friends()[0].lobby) == lobby, "y en el panel de amigos (Ana está en una sala)")
	var joined := []
	var member := []
	b.lobby_joined.connect(func(id, ok, owner): joined.append([id, ok, owner]))
	a.member_changed.connect(func(id, sid, on): member.append([id, sid, on]))
	b.join_lobby(lobby)
	check(_until(p, func(): return not joined.is_empty() and not member.is_empty()), "entra")
	eq(joined[0], [lobby, true, 7001], "Beto adentro, dueña Ana")
	eq(member[0], [lobby, 7002, true], "Ana se entera")
	eq(a.lobby_member_ids(lobby), [7001, 7002], "miembros para la dueña")
	check(_until(p, func(): return b.lobby_member_ids(lobby) == [7001, 7002]), "y para Beto")
	b.send(7001, PackedByteArray([1, 2, 3]), true)
	var inbox := []
	check(_until(p, func():
		inbox.append_array(a.poll_messages())
		return not inbox.is_empty()), "llega el mensaje")
	eq([inbox[0].from, inbox[0].data], [7002, PackedByteArray([1, 2, 3])], "de Beto, intacto")
	b.leave_lobby(lobby)
	check(_until(p, func(): return member.size() == 2), "sale")
	eq(member[1], [lobby, 7002, false], "Ana se entera de que salió")
	eq(a.lobby_member_ids(lobby), [7001], "queda sola")
	_close(p)


func test_join_before_discovery_waits_for_the_owner() -> void:
	var a := SteamBackendMock.new("Ana", BASE, 4, 7001)
	var created := [0]
	a.lobby_created.connect(func(id, _ok): created[0] = id)
	a.create_lobby(true, 4)
	a.run_callbacks()
	var b := SteamBackendMock.new("Beto", BASE, 4, 7002)  # just started: has not heard of Ana yet (like a --steam-join launch)
	var joined := []
	b.lobby_joined.connect(func(id, ok, owner): joined.append([id, ok, owner]))
	b.join_lobby(created[0])
	b.run_callbacks()
	eq(joined, [], "no falla enseguida: espera encontrar a la dueña")
	check(_until([a, b], func(): return not joined.is_empty()), "cuando la encuentra, entra")
	eq(joined[0], [created[0], true, 7001], "adentro")
	var c := SteamBackendMock.new("Caro", BASE, 4, 7003)
	var failed := []
	c.lobby_joined.connect(func(_id, ok, _o): failed.append(ok))
	c.join_lobby(123)
	c.join_wait = 0.05
	OS.delay_msec(80)
	c.run_callbacks()
	eq(failed, [false], "una sala que no aparece falla al rato")
	_close([a, b, c])


func test_full_lobby_rejects_and_friends_only_is_not_listed() -> void:
	var p := _pair()
	var a: SteamBackendMock = p[0]
	var b: SteamBackendMock = p[1]
	_until(p, func(): return a.friends().size() == 1)
	var created := [0]
	a.lobby_created.connect(func(id, _ok): created[0] = id)
	a.create_lobby(true, 1)
	a.run_callbacks()
	var listed := [-1]
	b.lobby_list.connect(func(e): listed[0] = e.size())
	_until(p, func():
		b.request_lobby_list("")
		return listed[0] >= 0)
	eq(listed[0], 0, "sólo amigos: no aparece en la lista pública (como en Steam)")
	var joined := []
	b.lobby_joined.connect(func(id, ok, _o): joined.append(ok))
	b.join_lobby(created[0])
	check(_until(p, func(): return not joined.is_empty()), "responde")
	eq(joined, [false], "llena: rechazada")
	_close(p)


func test_lobby_flow_through_steam_lobbies() -> void:
	var p := _pair()
	var a: SteamBackendMock = p[0]
	var b: SteamBackendMock = p[1]
	_until(p, func(): return a.friends().size() == 1)
	var host := SteamLobbies.new(a)
	var guest := SteamLobbies.new(b)
	var hosted := [0]
	host.hosted.connect(func(id): hosted[0] = id)
	host.host(true, {"mode": 2, "map": "tomb", "name": "Ana"})
	check(_until(p, func(): return hosted[0] != 0), "SteamLobbies crea la sala con el simulado")
	var joined := [0]
	guest.joined.connect(func(id, _owner): joined[0] = id)
	guest.join(hosted[0])
	check(_until(p, func(): return joined[0] == hosted[0]), "y el invitado entra")
	_close(p)


func _pump(backends: Array, server: GameServer, clients: Array, ms: float) -> void:
	var t := 0.0
	while t < ms:
		for b in backends:
			b.run_callbacks()
		server.process(16.0)
		for c in clients:
			c.poll(16.0)
		OS.delay_msec(2)
		t += 16.0


func test_full_match_flow_over_the_mock() -> void:
	var p := _pair()
	var host_b: SteamBackendMock = p[0]
	var guest_b: SteamBackendMock = p[1]
	_until(p, func(): return host_b.friends().size() == 1 and guest_b.friends().size() == 1)
	var lh := SteamLobbies.new(host_b)
	lh.host(true, {"mode": 2, "map": "tomb", "name": "Ana"})
	host_b.run_callbacks()
	var server := GameServer.new({"map": "tomb"})
	server.attach(SteamTransport.host(host_b, lh.lobby_id))
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var host_c := GameClient.new()
	host_c.attach(link[1], {"name": "Ana", "cls": "mage", "pref": "red"})
	var lg := SteamLobbies.new(guest_b)
	var owner := [0]
	lg.joined.connect(func(_id, o): owner[0] = o)
	lg.join(lh.lobby_id)
	check(_until(p, func(): return owner[0] != 0), "entra a la sala")
	var guest_c := GameClient.new()
	guest_c.attach(SteamTransport.join(guest_b, lh.lobby_id, owner[0]), {"name": "Beto", "cls": "warrior", "pref": "blue"})
	_pump(p, server, [host_c, guest_c], 800.0)
	eq(server.players.size(), 2, "los dos están en el lobby")
	host_c.send_ready(true)
	guest_c.send_ready(true)
	_pump(p, server, [host_c, guest_c], 200.0)
	host_c.send_start()
	_pump(p, server, [host_c, guest_c], 400.0)
	check(host_c.in_match and guest_c.in_match, "los dos reciben la partida")
	var states := [0]
	guest_c.state_received.connect(func(_s): states[0] += 1)
	_pump(p, server, [host_c, guest_c], 1000.0)
	check(states[0] > 20, "el invitado recibe snapshots por el simulado (%d)" % states[0])
	server.shutdown()
	_close(p)
