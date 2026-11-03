extends TestBase
## A lobby made by the queue: the server (supabase) picked host and sides, so the game server places every player by
## Steam id, ignores team preferences and settings changes, only lets the matched players in, and starts by itself.

const SIDES := {"7001": "red", "7002": "red", "7003": "blue", "7004": "blue"}


## A loopback link whose remote peer is a known Steam user (what SteamTransport reports for real players).
class SidLink:
	extends LoopbackTransport
	var sid := 0

	func steam_id_of(_peer: int) -> int:
		return sid


static func _pair_with_sid(sid: int, client_id: int) -> Array:
	var s := SidLink.new()
	var c := LoopbackTransport.new()
	s._server_side = true
	s._remote_id = client_id
	s._id = Transport.SERVER_ID
	s.sid = sid
	c._remote_id = Transport.SERVER_ID
	c._id = client_id
	s._remote = c
	c._remote = s
	return [s, c]


func _pump(server: GameServer, clients: Array, ms: float) -> void:
	var t := 0.0
	while t < ms:
		server.process(16.0)
		for c in clients:
			c.poll(16.0)
		t += 16.0


func _server(mode: int, sides: Dictionary, host_sid: String) -> GameServer:
	return GameServer.new({"mode": mode, "map": "random", "queue_sides": sides, "queue_host": host_sid})


func _fake_player(server: GameServer, peer: int, sid: String, pref := "any") -> void:
	server.players[peer] = {"name": "P%d" % peer, "cls": "mage", "spec": "", "pref": pref, "sid": sid, "mmr": 1500, "ready": false}


func _team_of(entries: Array, peer: int) -> String:
	for e in entries:
		if e.peer == peer:
			return e.team
	return ""


func test_entries_follow_the_sides_the_server_chose() -> void:
	var s := _server(2, SIDES, "7001")
	# preferences say the opposite on purpose: they must not matter
	_fake_player(s, 1, "7001", "blue")
	_fake_player(s, 2, "7002", "blue")
	_fake_player(s, 3, "7003", "red")
	_fake_player(s, 4, "7004", "red")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var entries := s.lobby_entries(rng)
	eq(entries.size(), 4, "cuatro lugares")
	eq(_team_of(entries, 1), "red", "el equipo queda junto (1)")
	eq(_team_of(entries, 2), "red", "el equipo queda junto (2)")
	eq(_team_of(entries, 3), "blue", "los rivales del otro lado (3)")
	eq(_team_of(entries, 4), "blue", "los rivales del otro lado (4)")
	check(entries.all(func(e): return e.peer != 0), "sin bots cuando estan todos")


func test_a_missing_player_is_replaced_by_a_bot_on_their_side() -> void:
	var s := _server(2, SIDES, "7001")
	_fake_player(s, 1, "7001")
	_fake_player(s, 2, "7002")
	_fake_player(s, 3, "7003")
	var entries := s.lobby_entries()
	eq(entries.size(), 4, "cuatro lugares igual")
	var blue_bots := entries.filter(func(e): return e.team == "blue" and e.peer == 0)
	eq(blue_bots.size(), 1, "el bot cubre el lugar del que no llego")
	eq(entries.filter(func(e): return e.team == "red").size(), 2, "rojo completo")


func test_1v1_sides() -> void:
	var s := _server(1, {"7001": "blue", "7003": "red"}, "7003")
	_fake_player(s, 1, "7003")
	_fake_player(s, 2, "7001")
	var entries := s.lobby_entries()
	eq(_team_of(entries, 1), "red", "uno de cada lado")
	eq(_team_of(entries, 2), "blue", "el otro del lado contrario")


func test_hello_identifies_players_and_rejects_strangers() -> void:
	var s := _server(1, {"7001": "red", "7003": "blue"}, "7001")
	var host_link := LoopbackTransport.pair()
	s.attach(host_link[0], true)
	var host := GameClient.new()
	host.attach(host_link[1], {"name": "Ana", "cls": "mage", "pref": "blue"})
	var guest_link := _pair_with_sid(7003, 2)
	s.attach(guest_link[0], false)
	var guest := GameClient.new()
	guest.attach(guest_link[1], {"name": "Caro", "cls": "rogue", "pref": "red"})
	var stranger_link := _pair_with_sid(9999, 3)
	s.attach(stranger_link[0], false)
	var stranger := GameClient.new()
	var closed: Array = []
	stranger.closed.connect(func(r): closed.append(r))
	stranger.attach(stranger_link[1], {"name": "Intruso", "cls": "mage", "pref": "any"})
	var plain_link := LoopbackTransport.pair(4)  # no Steam id at all
	s.attach(plain_link[0], false)
	var plain := GameClient.new()
	plain.attach(plain_link[1], {"name": "Anonimo", "cls": "mage", "pref": "any"})
	_pump(s, [host, guest, stranger, plain], 200.0)
	eq(s.players.size(), 2, "solo entran los dos emparejados")
	eq(str(s.players[1].sid), "7001", "el anfitrion se identifica por la cola (sin Steam en el loopback)")
	eq(str(s.players[2].sid), "7003", "el invitado, por su Steam id")
	check(not closed.is_empty(), "el intruso es expulsado")
	var entries := s.lobby_entries()
	eq(_team_of(entries, 1), "red", "preferencia ignorada (anfitrion)")
	eq(_team_of(entries, 2), "blue", "preferencia ignorada (invitado)")
	guest.send_set({"pref": "red", "mode": 3, "map": "tomb", "cls": "priest"})
	host.send_set({"mode": 3, "map": "tomb", "diff": "hard"})
	_pump(s, [host, guest], 100.0)
	eq(_team_of(s.lobby_entries(), 2), "blue", "no se cambia de lado desde el lobby")
	eq(int(s.cfg.mode), 1, "el anfitrion no cambia la modalidad de una partida de cola")
	eq(s.cfg.map, "random", "ni la arena")
	eq(s.players[2].cls, "priest", "la clase si se puede elegir")


func test_starts_by_itself_when_everyone_is_in() -> void:
	var s := _server(1, {"7001": "red", "7003": "blue"}, "7001")
	var host_link := LoopbackTransport.pair()
	s.attach(host_link[0], true)
	var host := GameClient.new()
	host.attach(host_link[1], {"name": "Ana", "cls": "mage", "pref": "any"})
	var gl := _pair_with_sid(7003, 2)
	s.attach(gl[0], false)
	var guest := GameClient.new()
	guest.attach(gl[1], {"name": "Caro", "cls": "rogue", "pref": "any"})
	_pump(s, [host, guest], 1000.0)
	eq(s.state, "lobby", "hay cuenta atras antes de empezar")
	_pump(s, [host, guest], GameServer.QUEUE_START_MS + 500.0)
	eq(s.state, "match", "arranca sin pedir Listo")
	eq(s.game.units.size(), 2, "1v1")


func test_starts_with_bots_if_someone_never_shows_up() -> void:
	var s := _server(1, {"7001": "red", "7003": "blue"}, "7001")
	var host_link := LoopbackTransport.pair()
	s.attach(host_link[0], true)
	var host := GameClient.new()
	host.attach(host_link[1], {"name": "Ana", "cls": "mage", "pref": "any"})
	_pump(s, [host], 5000.0)
	eq(s.state, "lobby", "esperando al otro")
	_pump(s, [host], GameServer.QUEUE_WAIT_MS)
	eq(s.state, "match", "pasada la espera arranca")
	eq(s.game.units.filter(func(u): return u.peer == 0).size(), 1, "con un bot en el lugar del ausente")


func test_normal_lobbies_are_untouched() -> void:
	var s := GameServer.new({"mode": 1})
	eq((s.cfg.queue_sides as Dictionary).size(), 0, "sin cola por defecto")
	var host_link := LoopbackTransport.pair()
	s.attach(host_link[0], true)
	var host := GameClient.new()
	host.attach(host_link[1], {"name": "Ana", "cls": "mage", "pref": "red"})
	_pump(s, [host], 10000.0)
	eq(s.state, "lobby", "una sala normal no arranca sola")
