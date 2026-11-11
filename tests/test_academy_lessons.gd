extends TestBase
## Every lesson of the Academia, played to the end by a scripted player with every kit, over the local link. The player really
## casts, controls, hides and fights on the server: what only a view can do (camera, clicks) is pushed as the event it gives.

const VIEW_EVENTS := ["cam_rmb", "cam_lmb", "zoom", "jumped", "click_target", "tab_target", "focus_set", "focus_cast", "cast_cancel", "moved", "tooltip"]
const MOODS := ["neutral", "contenta", "burlona", "seria", "orgullosa"]

var server: GameServer
var client: GameClient
var flow: LessonFlow
var me: ArenaUnit
var got: Array = []


func _kits() -> Array:
	var out: Array = []
	for cls in GameData.playable_ids():
		for spec in (GameData.spec_ids(cls) if not GameData.spec_ids(cls).is_empty() else [""]):
			out.append([cls, spec])
	return out


func _pump(ms := 100.0) -> void:
	var left := ms
	while left > 0.0:
		server.process(16.0)
		client.poll(16.0)
		left -= 16.0


func _start(id: String, cls: String, spec: String) -> void:
	flow = AcademyCatalog.lesson(id, cls, spec)
	server = GameServer.new({"lesson": flow.scenario})
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	client = GameClient.new()
	client.attach(link[1], {"name": "Yo", "cls": cls, "spec": spec, "pref": "red"})
	_pump()
	server.start_match(true)
	_pump()
	got = []
	client.lesson_events.connect(func(list):
		for ev in list:
			flow.note_event(ev, client.unit_id)
			for key in LessonEvents.keys(ev, client.unit_id):
				got.append(key)
				flow.push(key))
	me = server.game.unit_for_peer(client.peer_id)
	server.game.C = server.game.C.duplicate()
	server.game.C.CRIT_CHANCE = 0.0


func _enemy() -> ArenaUnit:
	for u in server.game.units:
		if u.peer == 0 and u.team != me.team and u.alive and not u.dormant:
			return u
	return null


func _friend() -> ArenaUnit:
	for u in server.game.units:
		if u.peer == 0 and u.team == me.team and u.alive:
			return u
	return me


func _stand_by(t: ArenaUnit, dist := 2.4) -> void:
	me.x = t.x
	me.z = t.z + dist
	server.game.input(me, 0.0, 0.0, t.x, t.z)
	_pump(60.0)


## Really casts the ability with that id and waits for it to come out.
func _cast(ability: String) -> bool:
	var m: ArenaMatch = server.game
	var slot := LessonActor.slot_of(me, ability)
	if slot < 0:
		return false
	var friendly := SpellKinds.kind(me.ability(slot)) == "friendly"
	var t: ArenaUnit = _friend() if friendly else _enemy()
	if t == null:
		return false
	if t != me:
		_stand_by(t)
	me.cds.fill(0.0)
	me.charges.clear()
	me.ult = 100.0
	var before := got.size()
	if not m.cast_ability(me, slot, t.x, t.z, server.sim_now, t.id):
		return false
	var left := float(me.ability(slot).get("cast", 0)) + 2500.0  # hits push a cast back
	while left > 0.0 and not got.slice(before).has("cast:%s" % ability):
		_pump(100.0)
		left -= 100.0
	_pump(400.0)
	return got.slice(before).has("cast:%s" % ability)


func _solve(event: String) -> void:
	var m: ArenaMatch = server.game
	if VIEW_EVENTS.has(event):
		flow.push(event)
	elif event.begins_with("plate:"):
		var p: Dictionary = m.map.plates[int(event.substr(6))]
		me.x = p.x
		me.z = p.z
		_pump(80.0)
	elif event.begins_with("cast:"):
		_cast(event.substr(5))
	elif event == "death":
		for u in m.units:
			if u.dummy == "crate" and u.alive:
				m._damage(u, 999.0, me, server.sim_now, "x")
				_pump(50.0)
				return
	elif event == "dmg":
		m._damage(_enemy(), 5.0, me, server.sim_now, "x")
		_pump(50.0)
	elif event == "cc" or event == "cc_immune:dr":
		_cast(str(me.ability(AcademyKit.new(me.cls, me.spec_id).control_slot()).id))
		_pump(300.0)
	elif event == "interrupt":
		var e := _enemy()
		var stopper := str(me.ability(AcademyKit.new(me.cls, me.spec_id).stopper_slot()).id)
		for attempt in 6:
			var guard := 0
			while (e.cast.is_empty() or server.sim_now - float(e.cast.start_at) > 120.0) and guard < 400:
				guard += 1
				_stand_by(e)
			_cast(stopper)
			if got.has("interrupt"):
				return
			_pump(4500.0)  # let the control wear off before the next try
	elif event == "trinket":
		m.use_trinket(me, server.sim_now)
		_pump(50.0)
	elif event == "note:hidden":
		var e := _enemy()
		var pillar := Vector2(7.0, m.map.room_z(GameMap.PILLAR_ROOM))
		var behind := pillar + (pillar - Vector2(e.x, e.z)).normalized() * 3.6
		me.x = behind.x
		me.z = behind.y
		_pump(1600.0)
	elif event == "note:won":
		var e := _enemy()
		m._damage(e, e.max_hp * 5.0, me, server.sim_now, "x")
		_pump(200.0)
	elif event == "gem":
		if not m.powers.is_empty():
			me.x = m.powers[0].x
			me.z = m.powers[0].z
		_pump(100.0)


## Plays the lesson. Returns "" when it reached the final card, or what it got stuck on.
func _play(id: String, cls: String, spec: String) -> String:
	_start(id, cls, spec)
	var entered := -1
	var guard := 0
	while not flow.current().get("final", false) and guard < 60:
		guard += 1
		if flow.index != entered:
			entered = flow.index
			if int(flow.current().get("cue", -1)) >= 0:
				client.send_cue(int(flow.current().cue))
				_pump()
		if flow.current().manual:
			flow.next()
			continue
		if flow.current().id == "peek":  # come back into the caster's sight before hiding again
			me.x = 0.0
			me.z = -4.0
			_pump(200.0)
		var pending: Array = flow.current().objectives.filter(func(o): return not o.done)
		var step := flow.index
		_solve(str(pending[0].event))
		if flow.index == step and not pending[0].done and int(pending[0].get("n", 0)) == 0 and guard > 50:
			return "%s: «%s» no se cumple con %s" % [flow.current().id, pending[0].event, cls]
	return "" if flow.current().get("final", false) else "%s: quedó en el paso %s" % [id, flow.current().id]


func test_every_lesson_can_be_finished_with_every_kit() -> void:
	for id in AcademyCatalog.lesson_ids():
		for k in _kits():
			var problem := _play(str(id), k[0], k[1])
			eq(problem, "", "%s con %s %s" % [id, k[0], k[1]])
			eq(flow.skipped, 0, "%s con %s %s: sin saltear nada" % [id, k[0], k[1]])


func test_every_lesson_survives_skipping_everything() -> void:
	for id in AcademyCatalog.lesson_ids():
		_start(str(id), "mage", "fire")
		var entered := -1
		while not flow.current().get("final", false):
			if flow.index != entered:
				entered = flow.index
				if int(flow.current().get("cue", -1)) >= 0:
					client.send_cue(int(flow.current().cue))
					_pump()
			flow.next()
		_pump(500.0)
		eq(AcademyMedals.grade(flow.medal_rule, flow.stats(1.0)) if flow.skipped > 0 else AcademyMedals.NONE, AcademyMedals.NONE, "%s: saltear todo no da medalla" % id)


func test_lessons_are_well_formed_for_every_kit() -> void:
	for id in AcademyCatalog.lesson_ids():
		var info := AcademyCatalog.info(str(id))
		check(str(info.get("blurb", "")) != "", "%s tiene descripción" % id)
		check(int(info.get("mins", 0)) > 0, "%s dice cuánto dura" % id)
		for k in _kits():
			var f := AcademyCatalog.lesson(str(id), k[0], k[1])
			var who := "%s con %s %s" % [id, k[0], k[1]]
			eq(f.id, str(id), who)
			eq(str(AcademyCatalog.chapter_of(str(id)).get("id", "")), f.chapter, "%s: está en su capítulo" % who)
			check(not LessonScenarios.scenario(f.scenario).is_empty(), "%s: su escenario existe (%s)" % [who, f.scenario])
			check(f.steps[0].manual, "%s: empieza con una presentación" % who)
			check(f.steps.back().get("final", false), "%s: termina en una tarjeta final" % who)
			check(not f.medal_rule.is_empty(), "%s: tiene regla de medallas" % who)
			eq(AcademyMedals.grade(f.medal_rule, f.stats(1.0)), AcademyMedals.GOLD, "%s: una corrida perfecta llega al oro" % who)
			var ids := {}
			for s in f.steps:
				check(not ids.has(s.id), "%s: paso repetido %s" % [who, s.id])
				ids[s.id] = true
				check(str(s.text).length() <= 330, "%s: el texto de %s entra en la tarjeta (%d)" % [who, s.id, str(s.text).length()])
				check(MOODS.has(str(s.get("mood", "neutral"))), "%s: ánimo conocido en %s" % [who, s.id])
				check(not str(s.text).contains("%s") and not str(s.text).contains("%d"), "%s: texto sin armar en %s" % [who, s.id])
				for o in s.objectives:
					var ev := str(o.event)
					if ev.begins_with("cast:"):
						check(not GameData.find_ability(k[0], ev.substr(5), k[1]).is_empty(), "%s: %s es de su kit" % [who, ev])


func test_scenarios_only_use_what_exists() -> void:
	for id in LessonScenarios.SCENARIOS:
		var sc: Dictionary = LessonScenarios.SCENARIOS[id]
		eq(str(sc.id), str(id), "id")
		var keys := {}
		for u in sc.units:
			check(not keys.has(u.key), "%s: clave repetida %s" % [id, u.key])
			keys[u.key] = true
			var ground := GameMap.create(LessonScenarios.map_of(sc))
			check(absf(float(u.x)) < ground.half_x - 1.0 and absf(float(u.z)) < ground.half_z - 1.0, "%s: %s está dentro de la arena" % [id, u.key])
			if str(u.kind) == "actor":
				eq(LessonActor.problems(u), [], "%s: guion de %s" % [id, u.key])
		for t in sc.triggers:
			for a in t.do:
				check(["open", "close", "activate", "spawn", "stun", "ult", "gem", "nocd", "cast", "note", "hurt"].has(str(a[0])), "%s: acción conocida %s" % [id, a[0]])
				if str(a[0]) in ["spawn", "hurt"]:
					check(keys.has(str(a[1])), "%s: %s nombra una unidad que existe" % [id, a[1]])
		for w in sc.get("watch", []):
			check(keys.has(str(w.hidden_from)), "%s: vigila a una unidad que existe" % id)


func test_the_kit_tables_cover_every_playable_kit() -> void:
	for k in _kits():
		var kit := AcademyKit.new(k[0], k[1])
		check(AcademyKit.CONTROL.has(kit.kit_key()), "%s tiene su control" % kit.kit_key())
		check(AcademyKit.STOPPER.has(kit.kit_key()), "%s tiene con qué cortar" % kit.kit_key())
		check(kit.slot_of(str(AcademyKit.CONTROL[kit.kit_key()])) >= 0, "%s: su control está en su barra" % kit.kit_key())
		check(kit.slot_of(str(AcademyKit.STOPPER[kit.kit_key()])) >= 0, "%s: su corte está en su barra" % kit.kit_key())
		check(AcademyKit.CC_WORDS.has(str(kit.ability(kit.control_slot()).id)), "%s: sabe decir qué hace su control" % kit.kit_key())
		check(kit.key(0) != "", "%s: su primera tecla tiene nombre" % kit.kit_key())


func test_new_journal_keys() -> void:
	eq(LessonEvents.keys({"e": "note", "k": "won"}, 1), ["note:won"], "aviso del escenario")
	eq(LessonEvents.keys({"e": "dmg", "t": 1, "by": 2, "amt": 5.0}, 1), ["hurt"], "me pegaron")
	eq(LessonEvents.keys({"e": "dmg", "t": 1, "by": -1, "amt": 5.0}, 1), ["hurt", "burned"], "me quemó el piso")
	eq(LessonEvents.keys({"e": "heal", "t": 3, "by": 1, "amt": 5.0}, 1), ["heal"], "curé")
	eq(LessonEvents.keys({"e": "heal", "t": 3, "by": 2, "amt": 5.0}, 1), [], "curó otro")


func test_the_rank_follows_what_you_earned() -> void:
	eq(AcademyCatalog.rank(0, 0, 13), "Recién llegado", "sin jugar")
	eq(AcademyCatalog.rank(1, 0, 13), "Aprendiz", "una")
	eq(AcademyCatalog.rank(7, 2, 13), "Gladiador en formación", "la mitad")
	eq(AcademyCatalog.rank(13, 5, 13), "Graduado", "todas")
	eq(AcademyCatalog.rank(13, 13, 13), "Maestro de la arena", "todas de oro")
