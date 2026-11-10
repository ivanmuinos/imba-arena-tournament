extends TestBase
## Scripted enemies of the Academia: real fighters (real casts, line of sight, crowd control) that follow a small script.

const NOW := 1000000.0
const STEP := 1000.0 / 60.0
var now := NOW


func _lesson(cls: String, script: Array, x := 0.0, z := 40.0, triggers: Array = []) -> ArenaMatch:
	now = NOW
	var sc := {"id": "t", "start": [0.0, 48.0], "units": [{"key": "e", "kind": "actor", "cls": cls, "name": "Rival", "x": x, "z": z, "script": script}], "triggers": triggers}
	var m := ArenaMatch.new(2, LessonScenarios.entries(sc, "Yo", "warrior", "", 1), NOW, "normal", GameMap.ACADEMY_ID)
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.journal = []
	m.stage = LessonStage.new(sc)
	m.stage.setup(m, NOW)
	return m


func _adv(m: ArenaMatch, ms: float) -> void:
	var left := ms
	while left > 0.0:
		now += STEP
		left -= STEP
		m.tick(now)


func _of(m: ArenaMatch, kind: String) -> Array:
	return m.journal.filter(func(e): return e.e == kind)


func _casts(m: ArenaMatch, ability: String) -> int:
	return _of(m, "cast").filter(func(e): return e.ability == ability).size()


func test_cast_loop_really_casts_at_the_player() -> void:
	var m := _lesson("warlock", [{"do": "cast_loop", "ability": "shadowbolt", "every": 3000.0}])
	var e: ArenaUnit = m.stage.unit("e")
	check(e.brain == null, "sin inteligencia artificial")
	_adv(m, 200.0)
	check(not e.cast.is_empty(), "se ve la barra de lanzamiento")
	_adv(m, 9000.0)
	var n := _casts(m, "shadowbolt")
	check(n >= 2 and n <= 4, "repite con su pausa (%d)" % n)
	check(_of(m, "dmg").any(func(d): return d.by == e.id and d.t == m.unit_for_peer(1).id), "el hechizo es de verdad: pega")


func test_cast_loop_respects_line_of_sight() -> void:
	var m := _lesson("warlock", [{"do": "cast_loop", "ability": "shadowbolt", "every": 500.0}], 0.0, 40.0)
	m.unit_for_peer(1).x = 0.0
	m.unit_for_peer(1).z = 30.0
	m.map.set_doors(0)
	_adv(m, 2500.0)
	eq(_casts(m, "shadowbolt"), 0, "con la puerta cerrada en el medio no lanza")


func test_hold_position_returns_home() -> void:
	var m := _lesson("warrior", [{"do": "hold_position"}], 6.0, 40.0)
	var e: ArenaUnit = m.stage.unit("e")
	e.x = 12.0
	_adv(m, 3000.0)
	near(e.x, 6.0, 0.8, "vuelve a su lugar")


func test_chase_melee_closes_in_and_hits() -> void:
	var m := _lesson("warrior", [{"do": "chase_melee"}])
	var e: ArenaUnit = m.stage.unit("e")
	var me := m.unit_for_peer(1)
	var hp := me.hp
	_adv(m, 5000.0)
	check(Vector2(e.x - me.x, e.z - me.z).length() < 3.5, "llega hasta vos")
	check(me.hp < hp or _of(m, "block").size() > 0, "y te pega")


func test_heal_self_only_when_hurt() -> void:
	var m := _lesson("priest", [{"do": "heal_self", "ability": "heal", "below": 0.7}])
	var e: ArenaUnit = m.stage.unit("e")
	_adv(m, 800.0)
	eq(_casts(m, "heal"), 0, "entero no se cura")
	e.hp = e.max_hp * 0.3
	var low := e.hp
	_adv(m, 2500.0)
	check(_casts(m, "heal") >= 1, "herido se cura")
	check(e.hp > low, "y sube la vida")


func test_stun_on_cast_punishes_a_cast() -> void:
	var m := _lesson("warrior", [{"do": "stun_on_cast", "ms": 1500.0}])
	var me := m.unit_for_peer(1)
	_adv(m, 200.0)
	eq(_of(m, "cc").size(), 0, "sin lanzamiento, nada")
	me.cast = {"slot": 1, "start_at": now, "ends_at": now + 2000.0, "ax": 0.0, "az": 0.0, "target_id": -1, "lock": -1, "pushes": 0}
	_adv(m, 100.0)
	eq(_of(m, "cc").size(), 1, "aturde al ver el lanzamiento")
	eq(_of(m, "interrupt").size(), 1, "y lo corta")
	check(me.cast.is_empty(), "la barra se fue")


func test_trinket_when_controlled() -> void:
	var m := _lesson("warrior", [{"do": "trinket_when_cc"}])
	var e: ArenaUnit = m.stage.unit("e")
	m._cc(e, "stun", 5000.0, now)
	_adv(m, 100.0)
	eq(_of(m, "trinket").size(), 1, "usa el abalorio")
	check(e.stun_until <= now, "y se libera")
	m._cc(e, "stun", 5000.0, now)
	_adv(m, 100.0)
	eq(_of(m, "trinket").size(), 1, "tarda dos minutos en volver")


func test_a_trigger_can_order_a_cast() -> void:
	var m := _lesson("warlock", [{"do": "hold_position"}], 0.0, 42.0, [{"on": "cue:1", "do": [["cast", "e", "fear"]]}])
	_adv(m, 500.0)
	eq(_casts(m, "fear"), 0, "espera el aviso")
	m.stage.cue(m, 1, now)
	_adv(m, 3000.0)
	eq(_casts(m, "fear"), 1, "lanza cuando se lo piden")
	check(_of(m, "cc").any(func(c): return c.cat == "fear"), "y el miedo te alcanza")


func test_a_rival_off_stage_or_down_does_nothing() -> void:
	var sc := {"id": "t", "start": [0.0, 48.0], "units": [{"key": "e", "kind": "actor", "cls": "warlock", "name": "R", "x": 0.0, "z": 42.0, "dormant": true, "script": [{"do": "cast_loop", "ability": "shadowbolt", "every": 500.0}]}], "triggers": []}
	var m := ArenaMatch.new(2, LessonScenarios.entries(sc, "Yo", "warrior", "", 1), NOW, "normal", GameMap.ACADEMY_ID)
	m.journal = []
	m.stage = LessonStage.new(sc)
	m.stage.setup(m, NOW)
	now = NOW
	_adv(m, 2500.0)
	eq(_casts(m, "shadowbolt"), 0, "fuera de escena no actúa")


func test_a_halted_stage_stops_the_script() -> void:
	var m := _lesson("warlock", [{"do": "cast_loop", "ability": "shadowbolt", "every": 500.0}])
	m.stage.halted = true
	_adv(m, 2500.0)
	eq(_casts(m, "shadowbolt"), 0, "lección detenida")


func test_a_mistyped_ability_fails_loudly_in_a_test_not_in_play() -> void:
	var a := LessonActor.new(ArenaUnit.new(), [{"do": "no_existe"}])
	check(a != null, "un paso desconocido no rompe nada")
	var problems := LessonActor.problems({"cls": "warlock", "script": [{"do": "cast_loop", "ability": "no_existe"}, {"do": "bailar"}]})
	eq(problems.size(), 2, "la validación los encuentra")
	eq(LessonActor.problems({"cls": "warlock", "script": [{"do": "cast_loop", "ability": "shadowbolt"}]}), [], "uno correcto no")
