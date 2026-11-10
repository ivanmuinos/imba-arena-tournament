extends TestBase
## An Academia lesson from end to end over the local link: the journal reaches the client, turns into events, and the steps
## tell the server when to set up the next part. The pilot lesson can be played to the end without any view.


func _pump(server: GameServer, client: GameClient, ms := 100.0) -> void:
	var left := ms
	while left > 0.0:
		server.process(16.0)
		client.poll(16.0)
		left -= 16.0


func _local(lesson := "move_1") -> Dictionary:
	var server := GameServer.new({"lesson": lesson})
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var client := GameClient.new()
	client.attach(link[1], {"name": "Yo", "cls": "mage", "spec": "fire", "pref": "red"})
	_pump(server, client)
	server.start_match(true)
	_pump(server, client)
	return {"server": server, "client": client}


# ---------------------------------------------------------------- events

func test_events_become_the_keys_that_steps_wait_for() -> void:
	var me := 1
	var keys := func(ev: Dictionary) -> Array: return LessonEvents.keys(ev, me)
	eq(keys.call({"e": "plate", "i": 3}), ["plate", "plate:3"], "placa")
	eq(keys.call({"e": "cast", "u": 1, "ability": "fireball"}), ["cast", "cast:fireball"], "mi lanzamiento")
	eq(keys.call({"e": "cast", "u": 2, "ability": "fireball"}), [], "el de otro no")
	eq(keys.call({"e": "cc", "t": 2, "cat": "incap", "kind": "poly", "ms": 1.0, "dr": 1.0}), ["cc", "cc:incap", "cc:incap:poly"], "control a otro")
	eq(keys.call({"e": "cc", "t": 1, "cat": "stun", "kind": "", "ms": 1.0, "dr": 1.0}), ["cc_me", "cc_me:stun"], "control a mí")
	eq(keys.call({"e": "cc_immune", "t": 2, "cat": "stun", "why": "dr"}), ["cc_immune", "cc_immune:dr"], "inmune")
	eq(keys.call({"e": "interrupt", "t": 2, "ability": "pyro"}), ["interrupt"], "corté a otro")
	eq(keys.call({"e": "interrupt", "t": 1, "ability": "pyro"}), ["interrupted"], "me cortaron")
	eq(keys.call({"e": "cc_break", "t": 2, "cat": "incap", "by": 1}), ["self_break"], "rompí mi propio control")
	eq(keys.call({"e": "cc_break", "t": 2, "cat": "incap", "by": 3}), [], "lo rompió otro")
	eq(keys.call({"e": "cast_cancel", "u": 1, "ability": "pyro", "why": "moved"}), ["cast_cancel", "cast_cancel:moved"], "cancelé moviéndome")
	eq(keys.call({"e": "trinket", "u": 1}), ["trinket"], "abalorio")
	eq(keys.call({"e": "gem", "u": 1, "kind": "crit"}), ["gem", "gem:crit"], "gema")
	eq(keys.call({"e": "down", "t": 1}), ["down"], "caí")
	eq(keys.call({"e": "death", "t": 2}), ["death"], "algo se rompió o cayó")
	eq(keys.call({"e": "dmg", "t": 2, "by": 1, "amt": 5.0, "ability": "x", "dot": false, "crit": false}), ["dmg"], "pegué")
	eq(keys.call({"e": "door", "i": 0, "open": true}), ["door:0"], "puerta")
	eq(keys.call({"e": "no_existe"}), [], "desconocido")
	eq(keys.call({}), [], "vacío")


# ---------------------------------------------------------------- the journal on the wire

func test_the_journal_reaches_the_player_and_empties() -> void:
	var h := _local()
	var got: Array = []
	h.client.lesson_events.connect(func(ev): got.append_array(ev))
	var me: ArenaUnit = h.server.game.unit_for_peer(h.client.peer_id)
	h.server.game._ev("trinket", 0.0, {"u": me.id})
	_pump(h.server, h.client)
	eq(got.size(), 1, "llegó")
	eq(got[0].e, "trinket", "el evento")
	eq(h.server.game.journal, [], "no se manda dos veces")


func test_a_malformed_lesson_message_is_ignored() -> void:
	var client := GameClient.new()
	var got: Array = []
	client.lesson_events.connect(func(ev): got.append(ev))
	client._on_message(1, {"t": "lesson", "ev": "x"})
	client._on_message(1, {"t": "lesson"})
	client._on_message(1, {"t": "lesson", "ev": [1, "x", {"e": 3}]})
	eq(got.filter(func(ev): return not ev.is_empty()).size(), 0, "nada válido, nada para el juego")
	client._on_message(1, {"t": "lesson", "ev": [{"e": "plate", "i": 1}, 3]})
	eq(got.back().size(), 1, "se queda solo con lo válido")


func test_a_normal_match_sends_no_lesson_messages() -> void:
	var server := GameServer.new({"mode": 2})
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var client := GameClient.new()
	var got: Array = []
	client.lesson_events.connect(func(ev): got.append(ev))
	client.attach(link[1], {"name": "Yo", "cls": "mage", "spec": "fire", "pref": "red"})
	_pump(server, client)
	server.start_match(true)
	_pump(server, client, 500.0)
	eq(got.size(), 0, "partida normal: nada")


# ---------------------------------------------------------------- cues

func test_cue_is_validated_and_only_works_in_a_lesson() -> void:
	eq(Wire.clean_practice({"cmd": "cue", "n": 3}).n, 3, "aviso válido")
	check(Wire.clean_practice({"cmd": "cue", "n": "x"}).is_empty(), "número inválido")
	check(Wire.clean_practice({"cmd": "cue"}).is_empty(), "sin número")
	check(Wire.clean_practice({"cmd": "cue", "n": 64}).is_empty(), "fuera de rango")
	check(Wire.clean_practice({"cmd": "cue", "n": -1}).is_empty(), "negativo")
	check(Wire.clean_practice({"cmd": "cue", "n": INF}).is_empty(), "no finito")
	var h := _local()
	var stage: LessonStage = h.server.game.stage
	eq(stage.active, 1, "solo la primera placa")
	h.client.send_cue(1)
	_pump(h.server, h.client)
	eq(stage.active, 3, "el aviso activa la siguiente")
	var yard := GameServer.new({"practice": true})
	var link := LoopbackTransport.pair()
	yard.attach(link[0], true)
	var c := GameClient.new()
	c.attach(link[1], {"name": "Yo", "cls": "mage", "spec": "fire", "pref": "red"})
	_pump(yard, c)
	yard.start_match(true)
	_pump(yard, c)
	c.send_cue(1)
	_pump(yard, c)
	eq(yard.game.stage, null, "en el patio el aviso no hace nada")


# ---------------------------------------------------------------- the pilot lesson

func test_the_time_only_runs_while_the_player_has_something_to_do() -> void:
	var f := AcademyCatalog.lesson("moverse", "mage", "fire")
	check(f.current().manual, "empieza con una presentación")
	f.tick(5000.0)
	eq(f.active_ms, 0.0, "leer no cuesta tiempo")
	f.next()
	f.tick(1000.0)
	eq(f.active_ms, 1000.0, "con un objetivo, el reloj corre")
	eq(f.skipped, 0, "nada salteado")
	f.next()
	eq(f.skipped, 1, "saltar un paso con objetivos se anota")


func test_the_pilot_lesson_exists_for_every_kit_and_unknown_ones_do_not() -> void:
	eq(AcademyCatalog.lesson("no_existe", "mage", "fire"), null, "lección desconocida")
	for cls in GameData.playable_ids():
		for spec in (GameData.spec_ids(cls) if not GameData.spec_ids(cls).is_empty() else [""]):
			var f: LessonFlow = AcademyCatalog.lesson("moverse", cls, spec)
			eq(f.id, "moverse", "id")
			check(not LessonScenarios.scenario(f.scenario).is_empty(), "su escenario existe")
			check(f.steps.size() >= 3, "tiene pasos")
			check(f.steps.back().get("final", false), "termina en una tarjeta final")


func test_the_pilot_lesson_can_be_played_to_the_end() -> void:
	var h := _local()
	var server: GameServer = h.server
	var client: GameClient = h.client
	var f := AcademyCatalog.lesson("moverse", "mage", "fire")
	client.lesson_events.connect(func(list):
		for ev in list:
			for key in LessonEvents.keys(ev, client.unit_id):
				f.push(key))
	var me: ArenaUnit = server.game.unit_for_peer(client.peer_id)
	var entered := -1
	var guard := 0
	while not f.current().get("final", false) and guard < 40:
		guard += 1
		if f.index != entered:
			entered = f.index
			if int(f.current().get("cue", -1)) >= 0:
				client.send_cue(int(f.current().cue))
				_pump(server, client)
		if f.current().manual:
			f.next()
			continue
		for o in f.current().objectives:
			if o.done:
				continue
			if str(o.event).begins_with("plate:"):
				var p: Dictionary = server.game.map.plates[int(str(o.event).substr(6))]
				me.x = p.x
				me.z = p.z
				_pump(server, client, 50.0)
			else:
				f.push(str(o.event))  # camera and jump come from the view, not from the journal
	check(f.current().get("final", false), "se llega al final")
	eq(f.skipped, 0, "sin saltear nada")
	check(server.game.map.door_open(0), "la puerta quedó abierta")


func test_skipping_a_step_never_leaves_the_lesson_stuck() -> void:
	var h := _local()
	var server: GameServer = h.server
	var client: GameClient = h.client
	var f := AcademyCatalog.lesson("moverse", "mage", "fire")
	var entered := -1
	while not f.current().get("final", false):
		if f.index != entered:
			entered = f.index
			if int(f.current().get("cue", -1)) >= 0:
				client.send_cue(int(f.current().cue))
				_pump(server, client)
		f.next()
	check(server.game.map.door_open(0), "saltear igual abre la puerta")


func test_the_arrow_never_sits_on_the_card() -> void:
	var card := Rect2(20, 150, 340, 300)
	var inside := TutorialOverlay.clear_of(Vector2(60, 300), card)
	check(inside.x > card.end.x, "una flecha sobre la tarjeta se corre al costado (%s)" % str(inside))
	eq(inside.y, 300.0, "a la misma altura")
	var tip := TutorialOverlay.clear_of(Vector2(100, 460), card)
	check(tip.x > card.end.x, "la punta abajo de la tarjeta también: el cuerpo de la flecha la pisaría")
	eq(TutorialOverlay.clear_of(Vector2(800, 300), card), Vector2(800, 300), "lejos de la tarjeta no se mueve")
	eq(TutorialOverlay.clear_of(Vector2(100, 600), card), Vector2(100, 600), "debajo, lejos, tampoco")

