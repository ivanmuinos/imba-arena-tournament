extends TestBase
## The scenario under a lesson: crates that break, units that wait their turn, plates that fire triggers, and the wall
## that keeps all of it away from online play.

const NOW := 1000000.0
const STEP := 1000.0 / 60.0
const SCENARIO := {
	"id": "t",
	"start": [0.0, 48.0],
	"doors": 0,
	"active": [0],
	"units": [
		{"key": "c1", "kind": "crate", "x": -6.0, "z": 45.0, "hp": 30.0},
		{"key": "c2", "kind": "crate", "x": 6.0, "z": 45.0, "hp": 30.0},
		{"key": "t1", "kind": "target", "cls": "warrior", "name": "Muñeco", "x": 0.0, "z": 40.0},
		{"key": "e1", "kind": "actor", "cls": "warrior", "name": "Rival", "x": 0.0, "z": 30.0, "dormant": true},
	],
	"triggers": [
		{"on": "plate:0", "do": [["open", 0], ["activate", 1], ["spawn", "e1"]]},
		{"on": "dead:c*", "do": [["activate", 2]]},
		{"on": "cue:3", "do": [["stun", 6000.0], ["ult"]]},
		{"on": "cue:4", "do": [["gem", "crit", 2.0, 48.0]]},
		{"on": "cue:5", "do": [["close", 0]]},
	],
}


func _lesson(scenario := SCENARIO) -> ArenaMatch:
	var m := ArenaMatch.new(2, LessonScenarios.entries(scenario, "Yo", "mage", "fire", 1), NOW, "normal", GameMap.ACADEMY_ID)
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.journal = []
	m.stage = LessonStage.new(scenario)
	m.stage.setup(m, NOW)
	return m


func _key(m: ArenaMatch, key: String) -> ArenaUnit:
	for u in m.units:
		if u.lesson_key == key:
			return u
	return null


func _me(m: ArenaMatch) -> ArenaUnit:
	return m.unit_for_peer(1)


func _of(m: ArenaMatch, kind: String) -> Array:
	return m.journal.filter(func(e): return e.e == kind)


func _snap_ids(m: ArenaMatch) -> Array:
	return m.snapshot_for(_me(m), NOW).units.map(func(u): return int(u.id))


func _step_on(m: ArenaMatch, plate: int, now := NOW + 16.0) -> void:
	var p: Dictionary = m.map.plates[plate]
	_me(m).x = p.x
	_me(m).z = p.z
	m.tick(now)


func test_the_player_starts_where_the_scenario_says() -> void:
	var m := _lesson()
	near(_me(m).x, 0.0, 0.001, "x")
	near(_me(m).z, 48.0, 0.001, "z")
	eq(m.phase, "fight", "sin cuenta regresiva")
	check(m.practice, "corre como práctica: sin rondas")


func test_a_crate_breaks_and_disappears() -> void:
	var m := _lesson()
	var c := _key(m, "c1")
	eq(c.dummy, "crate", "es una caja")
	near(c.max_hp, 30.0, 0.001, "con su vida")
	check(_snap_ids(m).has(c.id), "se ve")
	m._damage(c, 50.0, _me(m), NOW, "fireball")
	check(not c.alive, "se rompió")
	check(not _snap_ids(m).has(c.id), "desaparece del estado")
	eq(_of(m, "death")[0].t, c.id, "queda en el diario")
	var breaks := m.fx.filter(func(f): return f.k == "crate_break")
	eq(breaks.size(), 1, "se ve romperse")
	near(float(breaks[0].x), c.x, 0.001, "donde estaba")
	eq(int(breaks[0].id), c.id, "dice cuál, para soltarla como objetivo")
	check(not m.fx.any(func(f): return f.k == "death"), "no parece la muerte de un luchador")
	check(FxFilter.for_team(m, "red", NOW).any(func(f): return f.k == "crate_break"), "el filtro de eventos lo deja pasar")


func test_breaking_things_never_ends_a_round_or_feeds_the_killfeed() -> void:
	var m := _lesson()
	for key in ["c1", "c2"]:
		m._damage(_key(m, key), 50.0, _me(m), NOW, "fireball")
	var dead := _key(m, "t1")
	dead.mortal = true
	m._damage(dead, 999999.0, _me(m), NOW, "fireball")
	eq(m.broadcasts.size(), 0, "ni rondas ni muertes anunciadas")
	eq(m.phase, "fight", "sigue la lección")
	eq(int(m.score.red), 0, "sin puntos")


func test_crates_ignore_crowd_control() -> void:
	var m := _lesson()
	var c := _key(m, "c1")
	m._cc(c, "stun", 1000.0, NOW)
	eq(c.stun_until, 0.0, "una caja no se aturde")
	eq(_of(m, "cc").size(), 0, "no cuenta como control")


func test_a_target_does_not_break() -> void:
	var m := _lesson()
	var t := _key(m, "t1")
	m._damage(t, 999999.0, _me(m), NOW, "fireball")
	check(t.alive, "un muñeco no se rompe")


func test_a_dormant_unit_is_not_there_until_it_is_summoned() -> void:
	var m := _lesson()
	var e := _key(m, "e1")
	check(e.dormant and not e.alive, "espera su turno")
	check(not _snap_ids(m).has(e.id), "no se ve")
	check(m.roster().any(func(r): return r.id == e.id), "pero ya está en el reparto: la lista no cambia en plena lección")
	check(not m._enemies_within(_me(m), e.x, e.z, 50.0).has(e), "no se le puede pegar")
	e.hp = 1.0
	_step_on(m, 0)
	check(e.alive and not e.dormant, "aparece")
	near(e.hp, e.max_hp, 0.001, "entera")
	near(e.x, 0.0, 0.5, "en su lugar")
	near(e.z, 30.0, 0.5, "en su lugar")
	check(_snap_ids(m).has(e.id), "ahora sí se ve")
	eq(_of(m, "spawn")[0].key, "e1", "queda en el diario")


func test_a_plate_fires_once_and_only_while_active() -> void:
	var m := _lesson()
	_step_on(m, 1)
	eq(_of(m, "plate").size(), 0, "una placa inactiva no hace nada")
	check(not m.map.door_open(0), "la puerta sigue cerrada")
	_step_on(m, 0)
	eq(_of(m, "plate")[0].i, 0, "la activa se pisa")
	check(m.map.door_open(0), "abre la puerta")
	eq(_of(m, "door")[0].i, 0, "la puerta queda en el diario")
	_step_on(m, 0, NOW + 40.0)
	eq(_of(m, "plate").size(), 1, "pisarla de nuevo no repite")
	eq(_of(m, "spawn").size(), 1, "ni vuelve a llamar enemigos")
	_step_on(m, 1, NOW + 60.0)
	eq(_of(m, "plate").size(), 2, "activar otra placa la vuelve pisable")


func test_only_the_player_presses_plates() -> void:
	var m := _lesson()
	_me(m).x = 0.0
	_me(m).z = 48.0
	var t := _key(m, "t1")
	var p: Dictionary = m.map.plates[0]
	t.x = p.x
	t.z = p.z
	t.home = Vector2(p.x, p.z)
	m.tick(NOW + 16.0)
	eq(_of(m, "plate").size(), 0, "un muñeco no pisa placas")


func test_the_client_learns_doors_and_plates_from_the_snapshot() -> void:
	var m := _lesson()
	eq(m.snapshot_for(_me(m), NOW).you.lesson, {"d": 0, "p": 0, "a": 1}, "al empezar")
	_step_on(m, 0)
	eq(m.snapshot_for(_me(m), NOW).you.lesson, {"d": 1, "p": 1, "a": 3}, "después de pisar")
	var packed := SnapshotCodec.pack(m.snapshot_for(_me(m), NOW))
	eq(SnapshotCodec.unpack(packed).you.lesson, {"d": 1, "p": 1, "a": 3}, "viaja por la red de la partida")


func test_a_normal_snapshot_says_nothing_about_lessons() -> void:
	var m := ArenaMatch.new(1, [{"name": "A", "cls": "mage", "spec": "fire", "team": "red", "peer": 1}, {"name": "B", "cls": "warrior", "spec": "", "team": "blue", "peer": 0}], NOW, "normal", "bridge")
	check(not m.snapshot_for(m.units[0], NOW).you.has("lesson"), "partida normal")
	var y := ArenaMatch.new(2, PracticeYard.entries("T", "mage", "fire"), NOW, "normal", GameMap.PRACTICE_ID)
	check(not y.snapshot_for(y.unit_for_peer(1), NOW).you.has("lesson"), "arena de práctica")


func test_a_wildcard_waits_for_every_crate() -> void:
	var m := _lesson()
	m._damage(_key(m, "c1"), 50.0, _me(m), NOW, "fireball")
	m.tick(NOW + 16.0)
	check(m.stage.active & (1 << 2) == 0, "falta una caja")
	m._damage(_key(m, "c2"), 50.0, _me(m), NOW, "fireball")
	m.tick(NOW + 32.0)
	check(m.stage.active & (1 << 2) != 0, "rotas todas, se dispara")


func test_cues_run_their_actions_once() -> void:
	var m := _lesson()
	var me := _me(m)
	me.ult = 0.0
	me.trinket_ready = NOW + 90000.0
	m.stage.cue(m, 3, NOW)
	check(me.stun_until > NOW, "aturde")
	near(me.ult, 100.0, 0.001, "definitiva lista")
	near(me.trinket_ready, 0.0, 0.001, "con el abalorio disponible para liberarse")
	me.stun_until = 0.0
	m.stage.cue(m, 3, NOW + 10.0)
	eq(me.stun_until, 0.0, "repetir el aviso no hace nada")
	m.stage.cue(m, 99, NOW)
	check(true, "un aviso desconocido se ignora")
	m.stage.cue(m, 4, NOW)
	eq(m.powers.size(), 1, "pone una gema")
	m.stage.cue(m, 5, NOW)
	check(not m.map.door_open(0), "cerrar funciona")


func test_the_player_gets_back_up_where_the_lesson_started() -> void:
	var m := _lesson()
	var me := _me(m)
	me.x = 5.0
	me.hp = 1.0
	m._damage(me, 50.0, null, NOW)
	check(me.alive, "no se muere")
	near(me.z, 48.0, 0.001, "vuelve al inicio de la lección")
	eq(_of(m, "down").size(), 1, "pero queda registrado")


func test_a_mortal_rival_stays_down() -> void:
	var m := _lesson()
	_step_on(m, 0)
	var e := _key(m, "e1")
	m._damage(e, 999999.0, _me(m), NOW, "fireball")
	check(not e.alive, "cae")
	near(e.hp, 0.0, 0.001, "sin levantarse")


func test_dampening_only_when_the_lesson_asks_for_it() -> void:
	var m := _lesson()
	m.fight_start = NOW
	eq(m._damp(NOW + 100000.0), 0.0, "por defecto no hay")
	m.stage.damp = true
	check(m._damp(NOW + 100000.0) > 0.0, "la lección de amortiguación la activa")


func test_a_lesson_keeps_running_with_nobody_scoring() -> void:
	var m := _lesson()
	var now := NOW
	for i in 70 * 60:
		now += STEP
		m.tick(now)
	eq(m.phase, "fight", "pasado el límite de ronda sigue")
	check(not m.done, "no termina")
	eq(m.broadcasts.size(), 0, "ningún fin de partida")


# ---------------------------------------------------------------- the wall around lessons

class FakeNet extends Transport:
	func poll() -> void:
		pass


func _pump(server: GameServer, client: GameClient, ms := 100.0) -> void:
	var left := ms
	while left > 0.0:
		server.process(16.0)
		client.poll(16.0)
		left -= 16.0


func _local(cfg: Dictionary) -> Dictionary:
	var server := GameServer.new(cfg)
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var client := GameClient.new()
	client.attach(link[1], {"name": "Yo", "cls": "mage", "spec": "fire", "pref": "red"})
	_pump(server, client)
	return {"server": server, "client": client}


func test_a_local_server_runs_a_lesson() -> void:
	var h := _local({"lesson": "move_1"})
	var server: GameServer = h.server
	check(server.start_match(true), "arranca")
	eq(server.resolved_map, GameMap.ACADEMY_ID, "en el mapa de la Academia")
	check(server.game.stage != null, "con su escenario")
	eq(server.game.journal, [], "con su diario")
	_pump(server, h.client)
	eq(h.client.map_id, GameMap.ACADEMY_ID, "el cliente sabe el mapa")
	near(float(server.game.unit_for_peer(h.client.peer_id).z), 48.0, 1.0, "el jugador está donde dice la lección")


func test_an_unknown_lesson_does_not_start() -> void:
	var h := _local({"lesson": "no_existe"})
	check(not h.server.start_match(true), "no hay escenario")
	eq(h.server.state, "lobby", "sigue en la sala")


func test_a_lesson_refuses_any_network_transport() -> void:
	var h := _local({"lesson": "move_1"})
	h.server.attach(FakeNet.new())
	check(not h.server.start_match(true), "con red adjunta no arranca")
	eq(h.server.game, null, "ni crea la partida")


func test_a_lesson_is_for_one_player() -> void:
	var server := GameServer.new({"lesson": "move_1", "mode": 2})
	var a := LoopbackTransport.pair()
	var b := LoopbackTransport.pair(2)
	server.attach(a[0], true)
	server.attach(b[0])
	var ca := GameClient.new()
	var cb := GameClient.new()
	ca.attach(a[1], {"name": "A", "cls": "mage", "spec": "fire", "pref": "red"})
	cb.attach(b[1], {"name": "B", "cls": "mage", "spec": "fire", "pref": "red"})
	for i in 10:
		server.process(16.0)
		ca.poll(16.0)
		cb.poll(16.0)
	check(not server.start_match(true), "dos jugadores: no arranca")


func test_a_peer_cannot_ask_for_a_lesson_or_the_academy() -> void:
	var h := _local({"mode": 2})
	var server: GameServer = h.server
	h.client._send({"t": "set", "lesson": "move_1", "map": GameMap.ACADEMY_ID, "practice": true})
	_pump(server, h.client)
	eq(str(server.cfg.get("lesson", "")), "", "ningún mensaje de sala pide una lección")
	check(server.cfg.map != GameMap.ACADEMY_ID, "ni el mapa de la Academia")
	check(server.start_match(true), "la sala sigue siendo normal")
	eq(server.game.stage, null, "sin escenario")
	eq(server.game.journal, null, "sin diario")
	check(server.resolved_map != GameMap.ACADEMY_ID, "en un mapa normal")


func test_practice_controls_do_nothing_in_a_lesson_but_still_work_in_the_yard() -> void:
	var m := _lesson()
	var me := _me(m)
	me.ult = 0.0
	m.practice_command(me, "ult", true, NOW)
	eq(me.ult, 0.0, "pedir la definitiva no anda en una lección")
	m.practice_command(me, "nocd", true, NOW)
	check(not m.nocd, "ni quitar los cooldowns")
	var y := ArenaMatch.new(2, PracticeYard.entries("T", "mage", "fire"), NOW, "normal", GameMap.PRACTICE_ID)
	var u := y.unit_for_peer(1)
	u.ult = 0.0
	y.practice_command(u, "ult", true, NOW)
	near(u.ult, 100.0, 0.001, "en el patio sigue andando")


func test_a_broken_crate_stops_being_your_target() -> void:
	var view := MatchView.new()
	TestBase.tree.root.add_child(view)
	view.controller.target = 7
	view._target_gone(9)
	eq(view.controller.target, 7, "otra caja no cambia nada")
	view._target_gone(7)
	eq(view.controller.target, -1, "la que tenías elegida se suelta")
	view.free()


func test_a_rival_off_stage_has_no_frame_until_it_appears() -> void:
	var hud := Hud.new()
	TestBase.tree.root.add_child(hud)
	var roster := [{"id": 1, "team": "red", "cls": "mage", "spec": "fire", "name": "Yo", "bot": false}, {"id": 3, "team": "blue", "cls": "warrior", "spec": "", "name": "Rival", "bot": true}]
	hud.setup(roster, 1, "mage", "red", "fire")
	hud.hide_absent_frames = true
	var unit := func(id: int) -> Dictionary: return {"id": id, "x": 0.0, "z": 0.0, "rot": 0.0, "hp": 100, "alive": true, "cast": null, "cc": {}, "buffs": {}, "dashing": false, "y": 0.0, "air": false}
	var state := func(units: Array) -> Dictionary: return {"phase": "fight", "phaseLeft": 0.0, "round": 1, "score": {"red": 0, "blue": 0}, "damp": 0.0, "gates": true, "ft": 0.0, "units": units, "projs": [], "aoes": [], "traps": [], "powers": [], "you": {"cds": [0, 0, 0, 0, 0], "trinket": 0, "ult": 0, "auto": false, "inBush": false, "practice": true, "nocd": false, "meter": {}}}
	hud.on_state(state.call([unit.call(1)]), unit.call(1), 0.0)
	check(not hud._frames[3].root.visible, "fuera de escena no se ve su marco")
	hud.on_state(state.call([unit.call(1), unit.call(3)]), unit.call(1), 16.0)
	check(hud._frames[3].root.visible, "aparece con él")
	hud.free()


func test_a_crate_on_the_target_panel_has_no_champion_portrait() -> void:
	var hud := Hud.new()
	TestBase.tree.root.add_child(hud)
	hud.setup([{"id": 1, "team": "red", "cls": "mage", "spec": "fire", "name": "Yo", "bot": false}], 1, "mage", "red", "fire")
	var info := {"friend": false, "name": "Caja", "cls": "mage", "no_portrait": true, "hp": 20.0, "max_hp": 20.0, "dist": "6 m", "cast": null, "effects": [], "status": "", "status_kind": "", "lost": false}
	hud.show_target(info)
	eq(hud._tf.enemy.icon.texture, null, "una caja no es un mago")
	info.no_portrait = false
	hud.show_target(info)
	check(hud._tf.enemy.icon.texture != null, "un rival sí muestra el suyo")
	hud.free()

