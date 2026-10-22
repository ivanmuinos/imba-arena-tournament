extends TestBase
## Server/client over the in-process transport, plus a real ENet loopback.

var _snaps := 0

func test_chat_is_bounded_rate_limited_and_sender_owned() -> void:
	var h := _hosted()
	var guest := _remote(h.server, 2)
	_pump(h.server, [h.client, guest], 100.0)
	var got := []
	h.client.chat_received.connect(func(m): got.append(m))
	guest._send({"t": "chat", "text": " hola\n mundo ", "name": "Ana", "peer": h.client.peer_id})
	guest._send({"t": "chat", "text": "spam"})
	_pump(h.server, [h.client, guest], 50.0)
	eq(got.size(), 1, "spam suppressed")
	eq(got[0].name, "Beto", "server owns sender name")
	eq(got[0].peer, 2, "server owns sender peer")
	eq(got[0].text, "hola mundo", "control characters normalized")
	eq(Wire.clean_chat({"text": "x".repeat(241)}), "", "oversize rejected")
	eq(Wire.clean_chat({"text": 42}), "", "invalid type rejected")
	var remote_got := []
	guest.chat_received.connect(func(m): remote_got.append(m))
	for c in [h.client, guest]: c.send_ready(true)
	_pump(h.server, [h.client, guest], 50.0)
	check(h.server.start_match(), "chat remains available in match")
	h.client.send_chat("en partida")
	_pump(h.server, [h.client, guest], 50.0)
	eq(remote_got.size(), 1, "match chat reaches remote client")
	eq(remote_got[0].text, "en partida", "message delivered")


func test_ready_resets_after_join_leave_and_match_end() -> void:
	var h := _hosted()
	var guest := _remote(h.server, 2)
	_pump(h.server, [h.client, guest], 50.0)
	for c in [h.client, guest]: c.send_ready(true)
	_pump(h.server, [h.client, guest], 50.0)
	var third := _remote(h.server, 3, "C")
	_pump(h.server, [h.client, guest, third], 50.0)
	check(not h.server.all_ready(), "joining resets all confirmations")
	for c in [h.client, guest, third]: c.send_ready(true)
	_pump(h.server, [h.client, guest, third], 50.0)
	third.close()
	_pump(h.server, [h.client, guest], 50.0)
	check(not h.server.all_ready(), "leaving resets remaining confirmations")
	guest._send({"t": "ready", "on": "true"})
	_pump(h.server, [h.client, guest], 50.0)
	check(not h.server.players[2].ready, "ready requires boolean")
	for c in [h.client, guest]: c.send_ready(true)
	_pump(h.server, [h.client, guest], 50.0)
	check(h.server.start_match(), "confirmed match starts")
	h.server._finish_match()
	check(not h.server.all_ready(), "rematch needs new consent")

func test_humans_must_ready_and_roster_changes_clear_consent() -> void:
	var h := _hosted()
	var guest := _remote(h.server, 2)
	_pump(h.server, [h.client, guest], 100.0)
	check(not h.server.start_match(), "cannot bypass readiness on server")
	h.client._send({"t": "ready", "on": true, "peer": 2})
	_pump(h.server, [h.client, guest], 50.0)
	check(not h.server.start_match(), "sender cannot ready another player")
	guest._send({"t": "ready", "on": true})
	_pump(h.server, [h.client, guest], 50.0)
	guest.send_set({"pref": "red"})
	_pump(h.server, [h.client, guest], 50.0)
	check(not h.server.start_match(), "team change clears consent")
	for c in [h.client, guest]: c._send({"t": "ready", "on": true})
	_pump(h.server, [h.client, guest], 50.0)
	check(h.server.start_match(), "ready humans start despite bot slots")


func _pump(server: GameServer, clients: Array, ms: float) -> void:
	var t := 0.0
	while t < ms:
		server.process(16.0)
		for c in clients:
			c.poll(16.0)
		t += 16.0


## Pumps through the start room until the fight begins, plus 200 ms.
func _to_fight(server: GameServer, clients: Array) -> void:
	var t := 0.0
	while (server.game == null or server.game.phase != "fight") and t < 25000.0:
		_pump(server, clients, 16.0)
		t += 16.0
	_pump(server, clients, 200.0)


## Returns {server, client} with one local host player already in the lobby.
func _hosted(cfg := {}, cls := "mage", pref := "red") -> Dictionary:
	var server := GameServer.new(cfg)
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var client := GameClient.new()
	client.attach(link[1], {"name": "Ana", "cls": cls, "pref": pref})
	_pump(server, [client], 50.0)
	return {"server": server, "client": client}


func _remote(server: GameServer, id: int, name := "Beto", cls := "rogue", pref := "blue") -> GameClient:
	var link := LoopbackTransport.pair(id)
	server.attach(link[0], false)
	var c := GameClient.new()
	c.attach(link[1], {"name": name, "cls": cls, "pref": pref})
	return c


# ---------------------------------------------------------------- transport

func test_loopback_delivers_both_ways_and_signals_disconnect() -> void:
	var link := LoopbackTransport.pair(7)
	var got := []
	var events := []
	link[0].peer_connected.connect(func(id): events.append("conn%d" % id))
	link[0].peer_disconnected.connect(func(id): events.append("disc%d" % id))
	link[0].message.connect(func(from, m): got.append([from, m]))
	link[1].message.connect(func(from, m): got.append([from, m]))
	link[0].poll()
	link[1].poll()
	link[1].send(1, {"t": "hola", "n": 3})
	link[0].send(7, {"t": "chau"})
	link[0].poll()
	link[1].poll()
	eq(got.size(), 2, "dos mensajes")
	eq(got[0], [7, {"t": "hola", "n": 3}], "llega al servidor con el id del cliente")
	link[1].close()
	link[0].poll()
	eq(events, ["conn7", "disc7"], "conexión y desconexión")


# ---------------------------------------------------------------- lobby

func test_hello_welcome_and_lobby() -> void:
	var h := _hosted()
	var c: GameClient = h.client
	var s: GameServer = h.server
	check(c.is_host, "el local es el anfitrión")
	eq(s.players.size(), 1, "un jugador")
	eq(c.lobby.members.size(), 1, "el lobby lo lista")
	eq(c.lobby.teams.red.size(), 2, "equipo rojo completo (humano + bot)")
	eq(c.lobby.teams.blue.size(), 2, "azul completo con bots")
	eq(c.lobby.teams.red[0].name, "Ana", "el humano primero")


func test_lobby_rejects_other_game_version_with_a_clear_message() -> void:
	var h := _hosted()
	var s: GameServer = h.server
	var errors := []
	var bad := _remote(s, 2)
	bad.hello_version = "0.0.1"
	bad.server_error.connect(func(t): errors.append(t))
	_pump(s, [h.client, bad], 100.0)
	eq(s.players.size(), 1, "el de otra versión no entra")
	check(errors.size() == 1 and errors[0].contains("Versión distinta") and errors[0].contains("0.0.1") and errors[0].contains(GameServer.game_version()), "mensaje claro en español con las dos versiones (%s)" % str(errors))


func test_lobby_rejects_full_room() -> void:
	var h := _hosted()
	var s: GameServer = h.server
	var errors := []
	# Fill the room (2v2 = 4 humans).
	var more := []
	for i in 4:
		var c := _remote(s, 10 + i, "J%d" % i)
		c.server_error.connect(func(t): errors.append(t))
		more.append(c)
	_pump(s, [h.client] + more, 200.0)
	eq(s.players.size(), 4, "tope de 4 jugadores en 2v2")
	check(errors.any(func(t): return t.contains("llena")), "el que sobra recibe 'sala llena' (%s)" % str(errors))


func test_only_host_changes_settings_and_starts() -> void:
	var h := _hosted()
	var s: GameServer = h.server
	var guest := _remote(s, 2)
	_pump(s, [h.client, guest], 100.0)
	guest.send_set({"map": "tomb", "mode": 3, "cls": "priest"})
	_pump(s, [h.client, guest], 50.0)
	eq(s.cfg.map, "random", "un invitado no cambia el mapa")
	eq(s.cfg.mode, 2, "ni el modo")
	eq(s.players[2].cls, "priest", "pero sí su clase")
	guest.send_start()
	_pump(s, [h.client, guest], 50.0)
	eq(s.state, "lobby", "un invitado no inicia")
	h.client.send_set({"map": "tomb", "mode": 3, "diff": "hard"})
	_pump(s, [h.client, guest], 50.0)
	eq([s.cfg.map, s.cfg.mode, s.cfg.diff], ["tomb", 3, "hard"], "el anfitrión sí")


# ---------------------------------------------------------------- match

func _started(cfg := {}, cls := "mage") -> Dictionary:
	var h := _hosted(cfg, cls)
	var c: GameClient = h.client
	c.send_start()
	_pump(h.server, [c], 50.0)
	return h


func test_match_start_sends_roster_and_your_unit() -> void:
	var h := _started()
	var c: GameClient = h.client
	check(c.in_match, "en partida")
	eq(c.roster.size(), 4, "4 en el roster")
	var mine: Dictionary = c.roster.filter(func(r): return r.id == c.unit_id)[0]
	eq(mine.name, "Ana", "tu unidad es la tuya")
	eq(mine.cls, "mage", "tu clase")
	check(c.map_id in GameMap.IDS, "mapa resuelto")


func test_snapshots_flow_at_30hz_with_server_timestamps() -> void:
	var h := _started()
	var c: GameClient = h.client
	var n := [0]
	c.state_received.connect(func(_s): n[0] += 1)
	_pump(h.server, [c], 1000.0)
	check(n[0] >= 25 and n[0] <= 40, "~30 snapshots por segundo (%d)" % n[0])
	var snap := c.buffer.latest()
	check(snap.has("ts") and snap.has("units") and snap.has("you"), "contenido")
	eq(snap.phase, "prep", "arranca en preparación")


func test_input_moves_your_unit_and_bad_input_is_ignored() -> void:
	var h := _started()
	var s: GameServer = h.server
	var c: GameClient = h.client
	_to_fight(s, [c])  # prep -> just into the fight (bots have not had time to CC you yet)
	eq(s.game.phase, "fight", "pelea")
	var u := s.game.unit_for_peer(c.peer_id)
	var z0 := u.z
	c.send_input(0.0, -1.0, 0.0, -20.0)
	_pump(s, [c], 500.0)
	check(u.z < z0 - 1.0, "se movió hacia -z (%s -> %s)" % [z0, u.z])
	# A hand-made hostile message must not corrupt the simulation.
	c.transport.send(1, {"t": "input", "dx": NAN, "dz": 0.0, "ax": 0.0, "az": 0.0}, false)
	c.transport.send(1, {"t": "cast", "slot": 99, "ax": 0.0, "az": 0.0})
	c.transport.send(1, {"t": "input", "dx": "x"})
	_pump(s, [c], 100.0)
	check(is_finite(u.x) and is_finite(u.z), "posición finita")


func test_cast_goes_through_and_sets_cooldown() -> void:
	var h := _started()
	var s: GameServer = h.server
	var c: GameClient = h.client
	_to_fight(s, [c])
	var u := s.game.unit_for_peer(c.peer_id)
	c.send_cast({"slot": 4, "ax": u.x, "az": u.z - 10.0, "target": -1})  # blink
	_pump(s, [c], 100.0)
	check(u.cds[4] > s.sim_now, "Traslación en enfriamiento")
	check(c.buffer.latest().you.cds[4] > 0, "el cliente ve el cooldown en 'you.cds'")


func test_enemy_in_bush_is_never_sent_to_the_other_team() -> void:
	var h := _started({"map": "test"})
	var s: GameServer = h.server
	var c: GameClient = h.client
	_to_fight(s, [c])
	var me := s.game.unit_for_peer(c.peer_id)
	var enemy: ArenaUnit = null
	for u in s.game.units:
		if u.team != me.team:
			enemy = u
			break
	for u in s.game.units:
		u.brain = null  # deterministic: nobody acts on their own
		u.input = Vector2.ZERO
		u.auto_on = false  # nor keeps swinging, casting or burning from the opening seconds
		u.cast = {}
		u.burn_until = 0.0
		u.storm_until = 0.0
		u.curses = {}
	s.game.projs.clear()
	s.game.aoes.clear()
	s.game.traps.clear()
	var b: Dictionary = s.game.map.bushes[0]
	enemy.x = b.x
	enemy.z = b.z
	enemy.revealed_until = 0.0
	me.x = b.x - 14.0 if b.x > 0 else b.x + 14.0
	me.z = b.z
	for u in s.game.units:
		if u != me and u != enemy:
			u.x = 300.0 if u.team != me.team else me.x
			u.z = 300.0
	var seen := []
	var fx_ids := []
	c.state_received.connect(func(snap): seen.append_array(snap.units.map(func(x): return x.id)))
	c.fx_received.connect(func(list): for f in list: if f.has("id"): fx_ids.append(f.id))
	# The hidden enemy casts something: nobody on our team may hear about it.
	enemy.stealth_until = 0.0
	s.game.fx.append({"k": "cast", "id": enemy.id, "ability": "fireball"})
	s.game.fx.append({"k": "boom", "x": enemy.x, "z": enemy.z, "r": 1.0, "kind": "fireball"})
	_pump(s, [c], 200.0)
	check(not seen.has(enemy.id), "su posición no viaja en los snapshots")
	check(not fx_ids.has(enemy.id), "ni sus eventos")


func test_fx_filter_keeps_visible_and_drops_hidden() -> void:
	var m := ArenaMatch.new(2, [
		{"name": "A", "cls": "mage", "team": "red", "peer": 1}, {"name": "B", "cls": "mage", "team": "blue", "peer": 2}], 1_000_000.0)
	var a := m.units[0]
	var b := m.units[1]
	a.x = 0.0
	a.z = 0.0
	b.x = 5.0
	b.z = 0.0
	m.fx = [{"k": "cast", "id": b.id, "ability": "fireball"}, {"k": "hit", "id": a.id, "amt": 5, "x": 0.0, "z": 0.0, "crit": false, "by": b.id}, {"k": "death", "id": b.id}]
	eq(FxFilter.for_team(m, "red", 1_000_000.0).size(), 3, "todo visible: pasa todo")
	b.stealth_until = 1_000_000.0 + 5000.0
	var hidden := FxFilter.for_team(m, "red", 1_000_000.0).map(func(f): return f.k)
	eq(hidden, ["hit", "death"], "sigiloso: se omite su 'cast'")
	m.fx = [{"k": "boom", "x": 5.0, "z": 0.5, "r": 1.0, "kind": "fireball"}, {"k": "boom", "x": -20.0, "z": 0.0, "r": 1.0, "kind": "fireball"}]
	eq(FxFilter.for_team(m, "red", 1_000_000.0).size(), 1, "explosión sobre un oculto se omite, la lejana pasa")


func test_disconnect_mid_match_hands_unit_to_a_bot() -> void:
	var h := _started()
	var s: GameServer = h.server
	var c: GameClient = h.client
	_pump(s, [c], 100.0)
	var u := s.game.unit_for_peer(c.peer_id)
	c.close()
	_pump(s, [], 100.0)
	check(u.brain != null and u.peer == 0, "un bot toma el control")


func test_match_end_returns_to_lobby() -> void:
	var h := _started()
	var s: GameServer = h.server
	var c: GameClient = h.client
	var ended := [false]
	var lobbies := [0]
	c.match_ended.connect(func(_m): ended[0] = true)
	c.lobby_updated.connect(func(_m): lobbies[0] += 1)
	_pump(s, [c], 20200.0)
	# Red wins two rounds quickly: wait for each fight phase, then wipe the blue team.
	for round in 2:
		var guard := 0
		while s.game != null and s.game.phase != "fight" and guard < 2000:
			_pump(s, [c], 16.0)
			guard += 1
		for u in s.game.units:
			if u.team == "blue":
				s.game._damage(u, 99999.0, null, s.sim_now)
		_pump(s, [c], 100.0)
	_pump(s, [c], 8000.0)
	check(ended[0], "recibe el mensaje 'end'")
	eq(s.state, "lobby", "vuelve al lobby")
	check(lobbies[0] >= 1, "y recibe el lobby")


func test_dedicated_server_auto_starts_after_wait() -> void:
	var s := GameServer.new({"dedicated": true, "auto_start_ms": 1000.0})
	var cs := []
	for i in 2:
		var c := _remote(s, 2 + i, "P%d" % i, "mage", "any")
		cs.append(c)
	_pump(s, cs, 500.0)
	eq(s.state, "lobby", "todavía espera")
	_pump(s, cs, 1200.0)
	eq(s.state, "lobby", "dedicated cannot bypass ready")
	for c in cs: c.send_ready(true)
	_pump(s, cs, 50.0)
	eq(s.state, "match", "arranca solo")
	eq(s.game.units.filter(func(u): return u.peer != 0).size(), 2, "dos humanos")
	eq(s.game.units.size(), 4, "completado con bots")


# ---------------------------------------------------------------- real ENet

func test_enet_loopback_full_flow() -> void:
	var port := 20000 + randi() % 20000
	var host := PeerTransport.host(port)
	if host == null:
		check(false, "no se pudo abrir el puerto %d" % port)
		return
	var s := GameServer.new({"dedicated": true, "auto_start_ms": 0.0})
	s.attach(host)
	var tc := PeerTransport.join("127.0.0.1", port)
	check(tc != null, "cliente creado")
	if tc == null:
		return
	var c := GameClient.new()
	c.attach(tc, {"name": "Red", "cls": "hunter", "pref": "red"})
	var deadline := Time.get_ticks_msec() + 5000
	while c.lobby.is_empty() and Time.get_ticks_msec() < deadline:
		s.process(10.0)
		c.poll(10.0)
		OS.delay_msec(10)
	check(not c.lobby.is_empty(), "el cliente recibió el lobby por ENet")
	eq(c.lobby.members[0].name, "Red", "con su nombre")
	check(s.start_match(), "inicia")
	var states := [0]
	c.state_received.connect(func(_x): states[0] += 1)
	deadline = Time.get_ticks_msec() + 3000
	while states[0] < 10 and Time.get_ticks_msec() < deadline:
		s.process(10.0)
		c.poll(10.0)
		OS.delay_msec(10)
	check(c.in_match, "recibió 'match'")
	check(states[0] >= 10, "recibió snapshots por ENet (%d)" % states[0])
	c.send_input(1.0, 0.0, 5.0, 0.0)
	for i in 20:
		s.process(10.0)
		c.poll(10.0)
		OS.delay_msec(5)
	c.close()
	for i in 10:
		s.process(10.0)
		OS.delay_msec(5)
	s.shutdown()


# ---------------------------------------------------------------- snapshot codec

func test_snapshot_codec_roundtrip_and_size() -> void:
	var m := ArenaMatch.new(3, [
		{"name": "A", "cls": "mage", "team": "red", "peer": 1}, {"name": "B", "cls": "hunter", "team": "red", "peer": 0},
		{"name": "C", "cls": "priest", "team": "red", "peer": 0}, {"name": "D", "cls": "warrior", "team": "blue", "peer": 0},
		{"name": "E", "cls": "rogue", "team": "blue", "peer": 0}, {"name": "F", "cls": "mage", "team": "blue", "peer": 0}], 1_000_000.0)
	var now := 1_006_000.0
	for i in 400:
		now += 1000.0 / 60.0
		m.tick(now)
	var viewer := m.units[0]
	viewer.stun_until = now + 1500.0
	viewer.haste_until = now + 3000.0
	m.cast_ability(viewer, 1, viewer.x, viewer.z - 10.0, now)
	m.spawn_power("crit", 3.0, 4.0)
	var snap := m.snapshot_for(viewer, now)
	snap["ts"] = now
	var packed := SnapshotCodec.pack(snap)
	check(SnapshotCodec.is_valid(packed), "forma válida")
	var back := SnapshotCodec.unpack(Wire.decode(Wire.encode(packed)))
	eq(back.phase, snap.phase, "fase")
	eq(back.units.size(), snap.units.size(), "cantidad de unidades")
	for i in snap.units.size():
		var a: Dictionary = snap.units[i]
		var b: Dictionary = back.units[i]
		eq(b.id, a.id, "id")
		near(b.x, a.x, 0.01, "x")
		near(b.z, a.z, 0.01, "z")
		eq(b.hp, a.hp, "hp")
		eq(b.alive, a.alive, "vivo")
		eq(b.cc, a.cc, "cc")
		eq(b.buffs, a.buffs, "buffs")
		eq(b.cast == null, a.cast == null, "cast")
	eq(back.powers[0].kind, "crit", "power-up")
	eq(back.you.ult, snap.you.ult, "you")
	eq(back.ts, now, "ts exacto (doble)")
	check(Wire.encode(packed).size() < 1000, "un 3v3 cabe holgado en un paquete (%d bytes)" % Wire.encode(packed).size())


func test_snapshot_codec_rejects_malformed() -> void:
	eq(SnapshotCodec.is_valid({"t": "state"}), false, "faltan campos")
	var m := ArenaMatch.new(2, [{"name": "A", "cls": "mage", "team": "red", "peer": 1}, {"name": "B", "cls": "mage", "team": "blue", "peer": 0}], 1_000_000.0)
	var p := SnapshotCodec.pack(m.snapshot_for(m.units[0], 1_000_000.0))
	p["u"] = PackedFloat32Array([1.0, 2.0])
	eq(SnapshotCodec.is_valid(p), false, "largo que no es múltiplo del stride")


func test_host_with_remote_player_over_enet() -> void:
	# The hosting player (loopback) and a friend (ENet) end up in the same match, on opposite teams.
	var port := 20000 + randi() % 20000
	var net := PeerTransport.host(port)
	if net == null:
		check(false, "no se pudo abrir el puerto %d" % port)
		return
	var s := GameServer.new({})
	s.attach(net)
	var link := LoopbackTransport.pair()
	s.attach(link[0], true)
	var host_c := GameClient.new()
	host_c.attach(link[1], {"name": "Anfitrión", "cls": "mage", "pref": "red"})
	var tc := PeerTransport.join("127.0.0.1", port)
	var friend := GameClient.new()
	friend.attach(tc, {"name": "Amigo", "cls": "warrior", "pref": "blue"})
	var deadline := Time.get_ticks_msec() + 5000
	while friend.lobby.members.size() < 2 if not friend.lobby.is_empty() else true:
		s.process(10.0)
		host_c.poll(10.0)
		friend.poll(10.0)
		OS.delay_msec(5)
		if Time.get_ticks_msec() > deadline:
			break
	check(host_c.is_host and not friend.is_host, "sólo uno es anfitrión")
	check(not friend.lobby.is_empty() and friend.lobby.members.size() == 2, "los dos se ven en el lobby")
	friend.send_start()
	friend.send_ready(true)
	host_c.send_ready(true)
	for i in 30:
		s.process(10.0)
		host_c.poll(10.0)
		friend.poll(10.0)
		OS.delay_msec(5)
	host_c.send_start()
	deadline = Time.get_ticks_msec() + 3000
	while not (host_c.in_match and friend.in_match) and Time.get_ticks_msec() < deadline:
		s.process(10.0)
		host_c.poll(10.0)
		friend.poll(10.0)
		OS.delay_msec(5)
	check(host_c.in_match and friend.in_match, "los dos reciben la partida")
	if host_c.in_match and friend.in_match:
		var me_h: Dictionary = host_c.roster.filter(func(r): return r.id == host_c.unit_id)[0]
		var me_f: Dictionary = friend.roster.filter(func(r): return r.id == friend.unit_id)[0]
		check(me_h.team != me_f.team, "equipos opuestos")
		eq(me_f.cls, "warrior", "clase del amigo")
	var got := [0]
	friend.state_received.connect(func(_x): got[0] += 1)
	for i in 120:
		s.process(10.0)
		host_c.poll(10.0)
		friend.poll(10.0)
		OS.delay_msec(4)
	check(got[0] > 5, "el amigo recibe snapshots por ENet (%d)" % got[0])
	friend.close()
	host_c.close()
	s.shutdown()


func test_auto_attack_message_works_for_hunters_and_is_ignored_for_casters() -> void:
	for pair in [["hunter", true], ["mage", false]]:
		var h := _hosted({"map": "test"}, pair[0])
		var s: GameServer = h.server
		var c: GameClient = h.client
		# Fill every slot with fixed, idle players: random bots can stealth or move out of sight.
		var clients := [c, _remote(s, 2, "Aliado", "mage", "red"),
			_remote(s, 3, "Rival", "mage", "blue"), _remote(s, 4, "Rival2", "mage", "blue")]
		_pump(s, clients, 50.0)
		for client in clients:
			client.send_set({"spec": "fire"})
		_pump(s, clients, 50.0)
		for player in clients: player.send_ready(true)
		_pump(s, clients, 50.0)
		c.send_start()
		_to_fight(s, clients)
		var me := s.game.unit_for_peer(c.peer_id)
		var enemy := s.game.unit_for_peer(clients[2].peer_id)
		for u in s.game.units:
			check(u.brain == null, "sin IA en el fixture de red")
			u.input = Vector2.ZERO
			if u.cls == "mage":
				eq(u.spec_id, "fire", "especialización fija")
		me.x = 0.0
		me.z = 0.0
		me.rot = 0.0
		enemy.x = 0.0
		enemy.z = 6.0  # outside the bushes at z = +/-12
		check(me.alive and enemy.alive and s.game.phase == "fight", "fixture listo para atacar")
		check(s.game.team_can_see(me.team, enemy, s.sim_now), "objetivo visible antes del mensaje")
		c.send_auto(true, enemy.id)
		_pump(s, clients, 35.0)
		eq(me.auto_on, pair[1], "%s: auto_on [yo vivo=%s enemigo vivo=%s ve=%s dist=%.1f fase=%s]" % [pair[0], str(me.alive), str(enemy.alive), str(s.game.team_can_see(me.team, enemy, s.sim_now)), Vector2(me.x - enemy.x, me.z - enemy.z).length(), s.game.phase])
		eq(me.auto_target, enemy.id if pair[1] else -1, "%s: objetivo automático" % pair[0])
		c.send_auto(false)
		_pump(s, clients, 100.0)
		check(not me.auto_on, "%s: se apaga" % pair[0])
		for client in clients:
			client.close()
		s.shutdown()
