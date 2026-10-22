extends TestBase
## The four hand-designed arenas: symmetry, start-room gates, 10 s prep, living pillars, bridge/lava,
## random selection and bots playing every map to the end.

const STEP := 1000.0 / 60.0
var now := 0.0


class M:
	var x := 0.0
	var z := 0.0
	var vx := 0.0
	var vz := 0.0
	var dash_left := 0.0
	var dash_vx := 0.0
	var dash_vz := 0.0
	var team := "red"

	func _init(px := 0.0, pz := 0.0) -> void:
		x = px
		z = pz


func _same_shape(a: Dictionary, b: Dictionary) -> bool:
	if a.k != b.k or absf(a.x + b.x) > 1e-6 or absf(a.z + b.z) > 1e-6:
		return false
	if a.k == "c":
		return absf(a.r - b.r) < 1e-6
	return absf(a.hx - b.hx) < 1e-6 and absf(a.hz - b.hz) < 1e-6 and absf(a.c - b.c) < 1e-6 and absf(a.s - b.s) < 1e-6


func test_catalog_has_four_maps_plus_hidden_test_map() -> void:
	eq(GameMap.IDS, ["bridge", "pillars", "tomb", "living", "spire"], "los cinco mapas")
	for id in GameMap.IDS:
		check(GameData.maps.has(id), "%s tiene datos (nombre/zona)" % id)
		var m := GameMap.create(id)
		eq(m.id, id, "id")
		check(m.name != "", "nombre")
	check(GameMap.create("test").id == "test", "mapa de pruebas")


func test_every_map_is_point_symmetric() -> void:
	for id in GameMap.IDS:
		var m := GameMap.create(id)
		for list in [m.statics, m.hazards, m.gate_shapes]:
			for c in list:
				check(list.any(func(o): return _same_shape(c, o)), "%s: falta el espejo de %s" % [id, str(c)])
		for i in m.spawns.red.size():
			near(m.spawns.red[i].x, -m.spawns.blue[i].x, 1e-6, "%s: spawn x" % id)
			near(m.spawns.red[i].z, -m.spawns.blue[i].z, 1e-6, "%s: spawn z" % id)
		for p in m.dyn_pillars:
			var twin := m.dyn_pillars.filter(func(q): return absf(q.x + p.x) < 1e-6 and absf(q.z + p.z) < 1e-6 and q.start == p.start)
			check(twin.size() == 1 or (p.x == 0.0 and p.z == 0.0), "%s: pilar vivo sin espejo" % id)
		for p in m.power_spots:
			check(m.power_spots.any(func(q): return absf(q.x + p.x) < 1e-6 and absf(q.z + p.z) < 1e-6), "%s: power spot sin espejo" % id)


func test_maps_are_clean_few_los_blockers_and_no_bushes() -> void:
	for id in GameMap.IDS:
		var m := GameMap.create(id)
		eq(m.bushes.size(), 0, "%s: sin arbustos" % id)
		var interior := m.statics.filter(func(o): return not o.get("wall", false)).size() + m.dyn_pillars.size()
		check(interior >= 2 and interior <= 8, "%s: pocos objetos de visión (%d)" % [id, interior])


func test_spawns_are_inside_enclosed_rooms_and_free() -> void:
	for id in GameMap.IDS:
		var m := GameMap.create(id)
		for team in ["red", "blue"]:
			for s in m.spawns[team]:
				check(Rules.sdf_all(m, s.x, s.z) > Rules.PLAYER_R + 0.5, "%s: spawn libre" % id)
				check(absf(s.z) > 22.0, "%s: spawn dentro de la sala" % id)


func test_closed_gate_blocks_movement_and_los_until_open() -> void:
	for id in GameMap.IDS:
		var m := GameMap.create(id)
		m.apply_state(false, 0.0)
		var red: Dictionary = m.spawns.red[1]
		var u := M.new(red.x, red.z)
		for i in 360:
			Rules.step_mover(u, 0, -1, 1.0 / 60, 8, true, m)
		check(u.z > 22.0, "%s: no atraviesa la puerta cerrada (z=%s)" % [id, u.z])
		check(not Rules.has_los(m, M.new(0, 28), M.new(0, -28)), "%s: puerta cerrada tapa la vista" % id)
		m.apply_state(true, 0.0)
		for i in 360:
			Rules.step_mover(u, 0, -1, 1.0 / 60, 8, true, m)
		check(u.z < 20.0, "%s: con la puerta abierta sale (z=%s)" % [id, u.z])


func _bots_match(map_id: String, classes: Array) -> ArenaMatch:
	now = 1_000_000.0
	var entries := []
	for i in classes.size():
		entries.append({"name": "b%d" % i, "cls": classes[i], "team": "red" if i < classes.size() / 2 else "blue"})
	return ArenaMatch.new(classes.size() / 2, entries, now, "normal", map_id)


func _advance(m: ArenaMatch, ms: float) -> void:
	var t := 0.0
	while t < ms:
		now += STEP
		t += STEP
		m.tick(now)


func test_prep_is_10_seconds_every_round() -> void:
	var m := _bots_match("pillars", ["mage", "warrior"])
	eq(m.phase, "prep", "arranca en preparación")
	near(m.phase_ends_at - now, 10000.0, 1.0, "10 s")
	_advance(m, 9500)
	eq(m.phase, "prep", "sigue esperando")
	_advance(m, 700)
	eq(m.phase, "fight", "empieza la pelea")
	m._damage(m.units[1], 99999.0, null, now)
	eq(m.phase, "between", "terminó la ronda")
	_advance(m, 4100)
	eq(m.phase, "prep", "nueva preparación")
	near(m.phase_ends_at - now, 10000.0, 100.0, "10 s entre rondas")


func test_gates_follow_the_phase_in_a_match() -> void:
	var m := _bots_match("tomb", ["mage", "warrior"])
	_advance(m, 100)
	check(not m.map.gates_open, "cerradas en prep")
	_advance(m, 20100)
	check(m.map.gates_open, "abiertas en pelea")


func test_prep_lets_you_move_inside_the_room_but_not_leave() -> void:
	var m := _bots_match("bridge", ["mage", "warrior"])
	var u := m.units[0]
	u.brain = null
	var z0 := u.z
	m.input(u, 1.0, -1.0, 0, 0)
	_advance(m, 6000)
	check(Vector2(u.x, u.z).distance_to(Vector2(m.map.spawns.red[0].x, z0)) > 2.0, "se mueve en la sala")
	check(u.z > 22.0, "pero no sale")


func test_pillar_cycle_is_deterministic_and_telegraphed() -> void:
	var m := GameMap.create("living")
	check(m.dyn_pillars.size() >= 4, "hay pilares vivos")
	var states := []
	for ft in range(0, 40000, 100):
		var a := m.pillar_info(0, float(ft))
		var b := GameMap.create("living").pillar_info(0, float(ft))
		eq(a, b, "determinista en %d" % ft)
		if states.is_empty() or states[-1] != a.state:
			states.append(a.state)
	eq(states.slice(0, 5), ["down", "warn", "rise", "up", "sink"], "ciclo completo")
	var p0: Dictionary = m.dyn_pillars[0]
	var info := m.pillar_info(0, p0.start * 1000.0 - 1000.0)
	eq(info.state, "warn", "avisa 1 s antes de subir")
	check(info.warn > 0.0, "indicador de aviso")
	eq(m.pillar_info(0, 0.0).h, 0.0, "hundido al principio de la pelea")


func test_pillars_block_movement_and_los_only_while_up() -> void:
	var m := GameMap.create("living")
	var p: Dictionary = m.dyn_pillars[0]
	var t_up: float = p.start * 1000.0 + 3000.0
	m.apply_state(true, 0.0)
	check(Rules.sdf_all(m, p.x, p.z) > 0.0, "hundido: se puede pisar")
	var a := M.new(p.x - 8, p.z)
	var b := M.new(p.x + 8, p.z)
	check(Rules.has_los(m, a, b), "hundido: hay vista")
	m.apply_state(true, t_up)
	check(Rules.sdf_all(m, p.x, p.z) < 0.0, "arriba: bloquea")
	check(not Rules.has_los(m, a, b), "arriba: tapa la vista")
	m.apply_state(true, t_up + 12000.0)
	check(Rules.has_los(m, a, b), "volvió a hundirse")


func test_rising_pillar_pushes_players_out_and_never_traps() -> void:
	var m := GameMap.create("living")
	var p: Dictionary = m.dyn_pillars[0]
	var u := M.new(p.x + 0.3, p.z)  # standing almost at the centre
	var start: float = p.start * 1000.0
	var ft := start - 2000.0
	while ft < start + 2500.0:
		m.apply_state(true, ft)
		Rules.collide(u, m)
		ft += 16.7
	var d := Vector2(u.x - p.x, u.z - p.z).length()
	check(d >= p.r + Rules.PLAYER_R - 0.01, "quedó fuera del pilar (d=%s)" % d)
	check(Rules.sdf_all(m, u.x, u.z) >= Rules.PLAYER_R - 0.01, "libre de todo sólido")


func test_bridge_lava_and_ramps() -> void:
	var m := GameMap.create("bridge")
	check(not Rules.in_pool(m, 0.0, 0.0), "el puente es seguro")
	check(Rules.in_pool(m, 10.0, 0.0), "el abismo quema")
	check(Rules.in_pool(m, -10.0, 3.0), "también del otro lado")
	check(not Rules.in_pool(m, 23.0, 6.5), "la rampa no quema")
	check(m.height_at(0.0, 0.0) > m.height_at(10.0, 0.0) + 3.0, "el puente está alto sobre el abismo")
	check(m.height_at(10.0, 15.0) > m.height_at(10.0, 0.0) + 3.0, "las plataformas están altas")
	# Units in the chasm cannot see the high ground (cliff walls and bridge supports) but see each other.
	check(not Rules.has_los(m, M.new(10, 0), M.new(10, 15)), "desde abajo no se ve arriba")
	check(Rules.has_los(m, M.new(8, 0), M.new(14, 0)), "abajo se ven entre sí")
	check(Rules.has_los(m, M.new(0, 14), M.new(0, -14)), "sobre el puente hay vista")
	# A unit can climb out through a ramp.
	var u := M.new(23.0, 0.0)
	for i in 360:
		Rules.step_mover(u, 0, 1, 1.0 / 60, 7, true, m)
	check(u.z > 9.0, "sube por la rampa (z=%s)" % u.z)


func test_lava_hurts_in_a_match() -> void:
	var m := _bots_match("bridge", ["mage", "warrior"])
	_advance(m, 20100)
	var u := m.units[0]
	for x in m.units:
		x.brain = null
	u.x = 10.0
	u.z = 0.0
	var hp := u.hp
	_advance(m, 1000)
	check(hp - u.hp > 10.0, "pierde vida en la lava (%s)" % (hp - u.hp))


func test_random_pick_is_deterministic_and_covers_all_maps() -> void:
	var seen := {}
	for s in 60:
		var a := GameMap.pick_id(s)
		eq(a, GameMap.pick_id(s), "mismo seed, mismo mapa")
		check(a in GameMap.IDS, "mapa válido")
		seen[a] = true
	eq(seen.size(), GameMap.IDS.size(), "salen todos")


func test_bots_finish_matches_on_every_map() -> void:
	for id in GameMap.IDS:
		var m := _bots_match(id, ["mage", "warrior", "priest", "rogue"])
		var limit := now + 20 * 60_000
		var crossed := false
		var lava := 0.0
		while not m.done and now < limit:
			now += STEP
			m.tick(now)
			if id == "bridge":
				for u in m.units:
					if u.alive and Rules.in_pool(m.map, u.x, u.z):
						lava += 1.0 / 60.0
			if absf(m.units[0].z) < 8.0:
				crossed = true
		check(m.done, "%s: la partida termina" % id)
		eq(maxi(m.score.red, m.score.blue), int(GameData.C.ROUNDS_TO_WIN), "%s: hay ganador" % id)
		if id == "bridge":
			check(crossed or m.units.any(func(u): return u.dmg > 0), "bridge: pelean")
			check(lava < 120.0, "bridge: los bots esquivan la lava (%s s en lava)" % lava)
