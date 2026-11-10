extends TestBase
## The structured event log of a lesson: every funnel of the simulation reports what happened, and a normal match pays nothing.

const NOW := 1000000.0


func _duel(a_cls := "mage", b_cls := "warrior", journal := true) -> ArenaMatch:
	var m := ArenaMatch.new(1, [{"name": "A", "cls": a_cls, "spec": "fire" if a_cls == "mage" else "", "team": "red", "peer": 1},
		{"name": "B", "cls": b_cls, "spec": "", "team": "blue", "peer": 0}], NOW, "normal", "test")
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.phase = "fight"
	m.fight_start = NOW
	m.units[1].brain = null
	m.units[0].x = 0.0
	m.units[0].z = 0.0
	m.units[1].x = 0.0
	m.units[1].z = 5.0
	if journal:
		m.journal = []
	return m


func _of(m: ArenaMatch, kind: String) -> Array:
	return m.journal.filter(func(e): return e.e == kind)


func test_a_normal_match_has_no_journal_or_stage() -> void:
	var m := ArenaMatch.new(1, [{"name": "A", "cls": "mage", "spec": "fire", "team": "red", "peer": 1}, {"name": "B", "cls": "warrior", "spec": "", "team": "blue", "peer": 0}], NOW, "normal", "bridge")
	eq(m.journal, null, "sin lección no hay diario")
	eq(m.stage, null, "sin lección no hay escenario")
	var yard := ArenaMatch.new(2, PracticeYard.entries("T", "mage", "fire"), NOW, "normal", GameMap.PRACTICE_ID)
	eq(yard.journal, null, "la arena de práctica tampoco")
	eq(yard.stage, null, "ni escenario")
	var now := NOW
	m.phase = "fight"
	m.fight_start = now
	m._damage(m.units[0], 5.0, m.units[1], now, "strike")
	m._cc(m.units[1], "stun", 1000.0, now)
	m.tick(now + 16.0)
	eq(m.journal, null, "pelear no crea el diario")


func test_casts_and_damage_are_logged() -> void:
	var m := _duel()
	var a := m.units[0]
	var b := m.units[1]
	m._execute(a, 0, b.x, b.z, b.id, NOW)
	var casts := _of(m, "cast")
	eq(casts.size(), 1, "un lanzamiento")
	eq(casts[0].u, a.id, "de quién")
	eq(casts[0].ability, str(a.ability(0).id), "cuál")
	m._damage(b, 10.0, a, NOW, "fireball")
	var dmg := _of(m, "dmg")
	eq(dmg.size(), 1, "un golpe")
	eq([dmg[0].t, dmg[0].by, dmg[0].ability], [b.id, a.id, "fireball"], "quién a quién con qué")
	near(float(dmg[0].amt), 10.0, 0.01, "cuánto")
	eq(dmg[0].dot, false, "golpe directo")
	eq(dmg[0].at, NOW, "cuándo")


func test_environment_damage_has_no_author() -> void:
	var m := _duel()
	m._damage(m.units[0], 3.0, null, NOW)
	var dmg := _of(m, "dmg")
	eq(dmg[0].by, -1, "la lava no tiene autor")


func test_absorbed_and_blocked_hits_are_logged() -> void:
	var m := _duel()
	var a := m.units[0]
	var b := m.units[1]
	b.shield_until = NOW + 1000.0
	m._damage(b, 10.0, a, NOW, "fireball")
	eq(_of(m, "absorb").size(), 1, "escudo: absorbido")
	eq(_of(m, "dmg").size(), 0, "no cuenta como daño")
	b.shield_until = 0.0
	b.absorb = 50.0
	b.absorb_until = NOW + 1000.0
	m._damage(b, 10.0, a, NOW, "fireball")
	eq(_of(m, "absorb").size(), 2, "absorción: también")
	b.absorb = 0.0
	b.rot = atan2(a.x - b.x, a.z - b.z)
	m.block_rng.seed = 7
	for i in 60:
		m._damage(b, 1.0, a, NOW, "strike")
	check(_of(m, "block").size() > 0, "el bloqueo del guerrero queda registrado")
	eq(_of(m, "block")[0].t, b.id, "quién bloqueó")


func test_crowd_control_is_logged_with_its_diminishing_return() -> void:
	var m := _duel()
	var b := m.units[1]
	m._cc(b, "incap", 4000.0, NOW, "poly")
	var cc := _of(m, "cc")
	eq(cc.size(), 1, "control aplicado")
	eq([cc[0].t, cc[0].cat, cc[0].kind], [b.id, "incap", "poly"], "a quién y qué")
	near(float(cc[0].ms), 4000.0, 0.01, "primera vez: entero")
	near(float(cc[0].dr), 1.0, 0.01, "sin retorno decreciente")
	b.incap_until = 0.0
	m._cc(b, "incap", 4000.0, NOW + 100.0, "poly")
	near(float(_of(m, "cc")[1].dr), 0.5, 0.01, "segunda vez: mitad")
	m._cc(b, "stun", 1000.0, NOW + 100.0)
	eq(_of(m, "cc")[2].kind, "", "otras categorías no tienen variante")


func test_immunity_says_why() -> void:
	var m := _duel()
	var b := m.units[1]
	b.shield_until = NOW + 1000.0
	m._cc(b, "stun", 1000.0, NOW)
	eq(_of(m, "cc_immune")[0].why, "shield", "inmune por escudo")
	b.shield_until = 0.0
	for i in 3:
		m._cc(b, "stun", 1000.0, NOW)
	m._cc(b, "stun", 1000.0, NOW)
	eq(_of(m, "cc_immune")[1].why, "dr", "inmune por retornos decrecientes")


func test_damage_that_breaks_a_control_names_who_broke_it() -> void:
	var m := _duel()
	var a := m.units[0]
	var b := m.units[1]
	m._cc(b, "incap", 4000.0, NOW, "poly")
	m._damage(b, 1.0, a, NOW, "fireball")
	var brk := _of(m, "cc_break")
	eq(brk.size(), 1, "el daño rompió la oveja")
	eq([brk[0].t, brk[0].cat, brk[0].by], [b.id, "incap", a.id], "quién la rompió")
	m._cc(b, "fear", 4000.0, NOW)
	m._damage(b, 30.0, a, NOW, "fireball")
	eq(_of(m, "cc_break").size(), 1, "el miedo aguanta hasta 40 de daño")
	m._damage(b, 20.0, a, NOW, "fireball")
	eq(_of(m, "cc_break")[1].cat, "fear", "al pasar 40 se rompe")


func test_interrupts_and_cancels_are_logged() -> void:
	var m := _duel()
	var a := m.units[0]
	var b := m.units[1]
	var slot := 1
	a.cast = {"slot": slot, "start_at": NOW, "ends_at": NOW + 2000.0, "ax": 0.0, "az": 0.0, "target_id": -1, "lock": -1, "pushes": 0}
	m._cc(a, "stun", 500.0, NOW)
	eq(_of(m, "interrupt")[0].t, a.id, "el aturdimiento cortó el lanzamiento")
	eq(_of(m, "interrupt")[0].ability, str(a.ability(slot).id), "qué lanzaba")
	a.stun_until = 0.0
	a.cast = {"slot": slot, "start_at": NOW, "ends_at": NOW + 2000.0, "ax": 0.0, "az": 0.0, "target_id": -1, "lock": -1, "pushes": 0}
	m.cancel_cast(a)
	eq(_of(m, "cast_cancel")[0].why, "esc", "Esc cancela")
	m.cancel_cast(a)
	eq(_of(m, "cast_cancel").size(), 1, "cancelar sin lanzamiento no cuenta")
	a.cast = {"slot": slot, "start_at": NOW, "ends_at": NOW + 2000.0, "ax": 0.0, "az": 0.0, "target_id": -1, "lock": -1, "pushes": 0}
	a.input = Vector2(1, 0)
	m._progress_cast(a, NOW + 1.0)
	eq(_of(m, "cast_cancel")[1].why, "moved", "moverse cancela")
	a.input = Vector2.ZERO
	a.cast = {"slot": slot, "start_at": NOW, "ends_at": NOW + 2000.0, "ax": 0.0, "az": 0.0, "target_id": -1, "lock": -1, "pushes": 0}
	m.jump(a, NOW + 10.0)
	eq(_of(m, "cast_cancel")[2].why, "jump", "saltar cancela")


func test_healing_death_trinket_and_gems_are_logged() -> void:
	var m := _duel()
	var a := m.units[0]
	var b := m.units[1]
	a.hp = a.max_hp - 50.0
	m._heal(a, 20.0, a, NOW)
	var heal := _of(m, "heal")
	near(float(heal[0].amt), 20.0, 0.01, "curación real")
	eq([heal[0].t, heal[0].by], [a.id, a.id], "a quién y de quién")
	a.stun_until = NOW + 1000.0
	check(m.use_trinket(a, NOW), "usa el abalorio")
	eq(_of(m, "trinket")[0].u, a.id, "abalorio")
	m._apply_power(a, "crit", NOW)
	eq(_of(m, "gem")[0].kind, "crit", "gema")
	b.hp = 1.0
	m._damage(b, 5.0, a, NOW, "fireball")
	eq(_of(m, "death")[0].t, b.id, "muerte")


func test_a_practice_down_is_logged() -> void:
	var m := ArenaMatch.new(2, PracticeYard.entries("T", "mage", "fire"), NOW, "normal", GameMap.PRACTICE_ID)
	m.journal = []
	var me := m.unit_for_peer(1)
	me.hp = 1.0
	m._damage(me, 5.0, null, NOW)
	eq(_of(m, "down")[0].t, me.id, "caíste y volviste")


class StageSpy extends RefCounted:
	var calls: Array = []
	func step(_m: ArenaMatch, now: float) -> void:
		calls.append(now)


func test_the_stage_runs_every_tick() -> void:
	var m := _duel()
	var spy := StageSpy.new()
	m.stage = spy
	m.tick(NOW + 16.0)
	m.tick(NOW + 32.0)
	eq(spy.calls, [NOW + 16.0, NOW + 32.0], "el escenario se ejecuta en cada paso")
