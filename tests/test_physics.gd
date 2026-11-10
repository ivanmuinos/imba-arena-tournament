extends TestBase
## Vertical physics: gravity, jumps that keep their momentum, falls, steep slopes and knockbacks that fly in an arc.

const DT := 1.0 / 60.0
const STEP := 1000.0 / 60.0
var now := 0.0


class M:
	var x := 0.0
	var z := 0.0
	var y := 0.0
	var vx := 0.0
	var vz := 0.0
	var vy := 0.0
	var air := false
	var dash_left := 0.0
	var dash_vx := 0.0
	var dash_vz := 0.0
	var team := "red"

	func _init(px := 0.0, pz := 0.0) -> void:
		x = px
		z = pz


func _run(u, map: GameMap, dx: float, dz: float, ticks: int, speed := 7.0, can_move := true) -> void:
	for i in ticks:
		Rules.step_mover(u, dx, dz, DT, speed, can_move, map)


func _match(entries: Array, map_id := "test") -> ArenaMatch:
	now = 1_000_000.0
	var m := ArenaMatch.new(entries.size() / 2, entries, now, "normal", map_id)
	m.block_front = 0.0
	m.block_rear = 0.0
	return m


func _advance(m: ArenaMatch, ms: float) -> void:
	var t := 0.0
	while t < ms:
		now += STEP
		t += STEP
		m.tick(now)


func _duel(a: String, b: String, map_id := "test") -> ArenaMatch:
	var m := _match([{"name": "A", "cls": a, "team": "red", "peer": 1}, {"name": "B", "cls": b, "team": "blue", "peer": 2}], map_id)
	_advance(m, 20100)  # prep -> fight
	return m


# ---------------------------------------------------------------- jump

func test_jump_rises_and_lands_in_under_a_second() -> void:
	var map := GameMap.create("test")
	var u := M.new(0, 0)
	check(Rules.jump(u), "salta desde el suelo")
	check(u.air, "queda en el aire")
	var top := 0.0
	var ticks := 0
	while u.air and ticks < 240:
		Rules.step_mover(u, 0, 0, DT, 7, true, map)
		top = maxf(top, u.y)
		ticks += 1
	near(top, 1.6, 0.25, "altura del salto")
	check(ticks > 40 and ticks < 60, "dura ~0,8 s (%d ticks)" % ticks)
	eq(u.y, 0.0, "aterriza en el piso")
	eq(u.vy, 0.0, "sin velocidad vertical al aterrizar")


func test_cannot_jump_again_in_the_air() -> void:
	var u := M.new(0, 0)
	check(Rules.jump(u), "primer salto")
	check(not Rules.jump(u), "no hay doble salto")


func test_jump_keeps_momentum_and_ignores_steering() -> void:
	var map := GameMap.create("test")
	var u := M.new(0, 0)
	_run(u, map, 1, 0, 30)  # running along +x at full speed
	near(u.vx, 7.0, 0.01, "velocidad de carrera")
	Rules.jump(u)
	var x0 := u.x
	var ticks := 0
	while u.air:
		Rules.step_mover(u, -1, 0, DT, 7, true, map)  # pulling back mid-air
		ticks += 1
	near(u.x - x0, 7.0 * ticks * DT, 0.05, "el salto conserva el impulso")
	near(u.z, 0.0, 0.001, "no se desvía")


func test_standing_jump_can_commit_to_one_direction() -> void:
	var map := GameMap.create("test")
	var u := M.new(0, 0)
	Rules.jump(u)
	_run(u, map, 0, 1, 5)
	check(u.vz > 3.0, "salto parado: elige rumbo en el aire")
	var vz := u.vz
	_run(u, map, 1, 0, 5)
	eq(u.vz, vz, "ya eligió: no cambia")
	near(u.vx, 0.0, 0.001, "sin velocidad lateral nueva")


func test_stun_in_the_air_does_not_freeze_the_fall() -> void:
	var map := GameMap.create("test")
	var u := M.new(0, 0)
	_run(u, map, 1, 0, 30)
	Rules.jump(u)
	_run(u, map, 0, 0, 10, 7.0, false)
	check(u.air and u.y > 0.5, "sigue volando")
	var x1 := u.x
	_run(u, map, 0, 0, 80, 7.0, false)
	check(not u.air, "aterriza aunque esté aturdido")
	check(u.x > x1 + 1.0, "el impulso sigue en el aire")
	var x2 := u.x
	_run(u, map, 0, 0, 10, 7.0, false)
	eq(u.x, x2, "en el piso queda clavado")


# ---------------------------------------------------------------- ground, ledges and slopes

func test_ground_follows_the_terrain() -> void:
	var map := GameMap.create("bridge")
	var u := M.new(0, 20)
	_run(u, map, 0, 0, 2)
	near(u.y, 3.0, 0.01, "parado sobre la meseta")
	check(not u.air, "en el suelo")


func test_walking_off_a_cliff_falls_into_the_chasm() -> void:
	var map := GameMap.create("bridge")
	var u := M.new(11, 14)
	_run(u, map, 0, 0, 2)
	var seen_air := false
	var min_ticks_air := 0
	for i in 200:
		Rules.step_mover(u, 0, -1, DT, 7, true, map)
		if u.air:
			seen_air = true
			min_ticks_air += 1
			check(u.y > map.height_at(u.x, u.z) - 0.001, "nunca por debajo del piso")
	check(seen_air, "cae por el borde")
	check(min_ticks_air > 25, "la caída lleva tiempo (%d ticks)" % min_ticks_air)
	check(map.is_low(u.x, u.z), "termina en el abismo")
	near(u.y, -2.0, 0.05, "en el fondo")


func test_cliff_cannot_be_climbed_but_ramp_can() -> void:
	var map := GameMap.create("bridge")
	var u := M.new(11, 0)
	Rules.ground(u, map)
	near(u.y, -2.0, 0.01, "empieza en el fondo")
	_run(u, map, 0, 1, 400)
	check(u.z < 9.6, "la pared del acantilado lo frena (z=%s)" % u.z)
	check(u.y < 0.0, "sigue abajo (y=%s)" % u.y)
	var r := M.new(23, 0)
	Rules.ground(r, map)
	_run(r, map, 0, 1, 400)
	check(r.z > 9.0, "por la rampa sube (z=%s)" % r.z)
	near(r.y, 3.0, 0.05, "llega a la meseta")
	check(not r.air, "caminando, sin despegarse")


func test_steep_ground_slides_down() -> void:
	var map := GameMap.create("bridge")
	# The cliff face between the plateau and the chasm is far too steep to stand on.
	var u := M.new(11, 9.0)
	u.y = map.height_at(11, 9.0)
	_run(u, map, 0, 0, 120)
	check(map.is_low(u.x, u.z) and u.y < -1.9, "resbala hasta el fondo (z=%s y=%s)" % [u.z, u.y])


func test_dash_does_not_climb_cliffs() -> void:
	var map := GameMap.create("bridge")
	var u := M.new(11, 6)
	Rules.ground(u, map)
	u.dash_left = 0.5
	u.dash_vz = 30.0
	_run(u, map, 0, 0, 40)
	check(u.z < 9.6 and u.y < 0.0, "la carga no trepa el acantilado (z=%s y=%s)" % [u.z, u.y])


func test_teleport_lands_on_the_ground() -> void:
	var map := GameMap.create("bridge")
	var u := M.new(11, 0)
	Rules.ground(u, map)
	u.x = 0.0
	u.z = 20.0  # blinked onto the plateau
	_run(u, map, 0, 0, 1)
	near(u.y, 3.0, 0.01, "queda parado arriba")
	check(not u.air, "sin caer")


# ---------------------------------------------------------------- backpedal

func test_backpedal_is_slower_but_strafing_is_not() -> void:
	near(Rules.facing_speed(Vector2(0, 1), 0.0), 1.0, 0.001, "adelante: velocidad plena")
	near(Rules.facing_speed(Vector2(1, 0), 0.0), 1.0, 0.001, "de costado: velocidad plena")
	near(Rules.facing_speed(Vector2(1, 1), 0.0), 1.0, 0.001, "diagonal adelante: plena")
	near(Rules.facing_speed(Vector2(0, -1), 0.0), Rules.BACKPEDAL, 0.001, "hacia atrás: más lento")
	near(Rules.facing_speed(Vector2(1, -1), 0.0), Rules.BACKPEDAL, 0.001, "diagonal atrás: más lento")
	near(Rules.facing_speed(Vector2.ZERO, 0.0), 1.0, 0.001, "quieto")
	near(Rules.facing_speed(Vector2(-1, 0), PI / 2), Rules.BACKPEDAL, 0.001, "respeta la orientación")


func test_match_backpedal_slows_players_only() -> void:
	var m := _duel("mage", "mage")
	var a := m.units[0]
	var b := m.units[1]
	for u in [a, b]:
		u.x = 0.0 if u == a else 20.0
		u.z = 0.0
		u.vx = 0.0
		u.vz = 0.0
	# Both look along +z; A runs forward, B walks backwards.
	m.input(a, 0, 1, a.x, a.z + 30.0)
	m.input(b, 0, -1, b.x, b.z + 30.0)
	_advance(m, 1000)
	var fwd := a.z
	var back := -b.z
	check(fwd > 5.0, "avanza (%s)" % fwd)
	near(back / fwd, Rules.BACKPEDAL, 0.05, "retroceder es más lento")


# ---------------------------------------------------------------- match integration

func test_match_jump_is_real_and_needs_the_ground() -> void:
	var m := _duel("warrior", "mage")
	var a := m.units[0]
	m.jump(a, now)
	check(a.air, "despega")
	_advance(m, 300)
	check(a.y > 0.8, "está en el aire (y=%s)" % a.y)
	var vy := a.vy
	m.jump(a, now)
	near(a.vy, vy, 0.001, "saltar en el aire no hace nada")
	_advance(m, 700)
	check(not a.air and a.y == 0.0, "aterrizó")
	m.jump(a, now)
	check(a.air, "apenas toca el piso puede volver a saltar")


func test_rooted_or_stunned_units_cannot_jump() -> void:
	var m := _duel("warrior", "mage")
	var a := m.units[0]
	a.root_until = now + 5000
	m.jump(a, now)
	check(not a.air, "enraizado no salta")
	a.root_until = 0.0
	a.stun_until = now + 5000
	m.jump(a, now)
	check(not a.air, "aturdido no salta")


func test_cast_time_spells_cannot_start_in_the_air() -> void:
	var m := _duel("mage", "warrior")
	var a := m.units[0]
	var b := m.units[1]
	a.x = b.x
	a.z = b.z - 12.0
	m.jump(a, now)
	_advance(m, 100)
	check(not m.cast_ability(a, old(a, 1), b.x, b.z, now, b.id), "no se puede lanzar en el aire")
	check(a.cast.is_empty(), "sin lanzamiento")
	_advance(m, 1000)
	check(m.cast_ability(a, old(a, 1), b.x, b.z, now, b.id), "en el piso sí")


func test_knockback_flies_in_an_arc_and_cannot_be_steered() -> void:
	var m := _duel("warrior", "mage")
	var a := m.units[0]
	a.x = 0.0
	a.z = 0.0
	_advance(m, 50)
	Rules.knock(a, Vector2(1, 0), 6.0, 0.5)
	check(a.air and a.knocked, "sale volando")
	m.input(a, -1, 0, a.x - 30.0, a.z)  # fighting it
	var top := 0.0
	var t := 0
	while a.air and t < 120:
		_advance(m, STEP)
		top = maxf(top, a.y)
		t += 1
	check(top > 0.3, "describe una parábola (pico %s)" % top)
	near(a.x, 6.0, 0.4, "recorre la distancia del empujón")
	check(not a.knocked, "al aterrizar recupera el control")
	near(t * STEP, 500.0, 60.0, "tiempo de vuelo")


func test_knocked_units_are_server_driven_in_snapshots() -> void:
	var m := _duel("warrior", "mage")
	var a := m.units[0]
	a.x = 0.0
	a.z = 0.0
	_advance(m, 50)
	var s: Dictionary = m.snapshot_for(a, now).units.filter(func(u): return u.id == a.id)[0]
	check(not s.air and not s.dashing, "en el piso")
	near(s.y, 0.0, 0.001, "altura en el snapshot")
	Rules.knock(a, Vector2(0, 1), 5.0, 0.5)
	_advance(m, 150)
	s = m.snapshot_for(a, now).units.filter(func(u): return u.id == a.id)[0]
	check(s.air, "en el aire")
	check(s.dashing, "el cliente sigue al servidor durante el empujón")
	check(s.y > 0.2, "la altura viaja (y=%s)" % s.y)


func test_snapshot_codec_carries_height_and_air() -> void:
	var m := _duel("warrior", "mage")
	var a := m.units[0]
	m.jump(a, now)
	_advance(m, 250)
	var snap := m.snapshot_for(a, now)
	var back := SnapshotCodec.unpack(SnapshotCodec.pack(snap))
	var s0: Dictionary = snap.units.filter(func(u): return u.id == a.id)[0]
	var s1: Dictionary = back.units.filter(func(u): return u.id == a.id)[0]
	near(s1.y, s0.y, 0.001, "altura")
	eq(s1.air, true, "en el aire")
	eq(s1.dashing, false, "un salto propio no es un empujón")


func test_knockback_off_the_bridge_drops_into_the_lava() -> void:
	var m := _duel("warrior", "mage", "bridge")
	var a := m.units[0]
	a.x = 1.0
	a.z = 0.0
	a.y = 3.0
	_advance(m, 50)
	near(a.y, 3.0, 0.01, "sobre el puente")
	Rules.knock(a, Vector2(1, 0), 6.0, 0.5)
	_advance(m, 1500)
	check(m.map.is_low(a.x, a.z), "cayó al abismo")
	near(a.y, -2.0, 0.05, "en el fondo")
	var hp := a.hp
	_advance(m, 1000)
	check(a.hp < hp, "la lava lo quema")


func test_units_at_different_heights_do_not_push_each_other() -> void:
	var a := M.new(0, 0)
	var b := M.new(0.2, 0)
	b.y = 2.5
	b.air = true
	Rules.separate([a, b])
	eq(a.x, 0.0, "el de abajo no se mueve")
	var c := M.new(0, 0)
	var d := M.new(0.2, 0)
	Rules.separate([c, d])
	check(d.x - c.x >= Rules.PLAYER_R * 2 - 0.001, "a la misma altura se separan")


func test_round_reset_puts_units_on_the_ground() -> void:
	var m := _duel("warrior", "mage", "bridge")
	for u in m.units:
		near(u.y, m.map.height_at(u.x, u.z), 0.01, "sobre el terreno")
		check(not u.air, "en el suelo")


func test_bots_climb_out_of_the_chasm() -> void:
	var map := GameMap.create("bridge")
	var u := M.new(10, 0)
	Rules.ground(u, map)
	for i in 1200:
		var wp := map.waypoint(Vector2(u.x, u.z), Vector2(0, -15))
		var d := wp - Vector2(u.x, u.z)
		Rules.step_mover(u, d.x, d.y, DT, 7, true, map)
		if not map.is_low(u.x, u.z) and u.y > 2.9 and not u.air and absf(u.x) < 2.0 and u.z < -12.0:
			break
	check(u.y > 2.9 and u.z < -10.0, "sale por la rampa y cruza (x=%s z=%s y=%s)" % [u.x, u.z, u.y])


# ---------------------------------------------------------------- client prediction

func test_predictor_jumps_locally_and_tracks_height() -> void:
	var map := GameMap.create("bridge")
	var p := Predictor.new()
	p.place(0.0, 20.0, map)
	near(p.m.y, 3.0, 0.01, "arranca sobre el terreno")
	var me := {"x": 0.0, "z": 20.0, "y": 3.0, "rot": 0.0, "alive": true, "cc": {}, "buffs": {}, "cast": null, "dashing": false, "air": false}
	check(p.jump(me), "salto local")
	p.step(DT, Vector2.ZERO, me, "warrior", "fight", map, 1.0, 0.0, 0.0)
	check(p.m.air and p.m.y > 3.0, "sube sin esperar al servidor")
	me.cc = {"root": 1.0}
	var q := Predictor.new()
	q.place(0.0, 20.0, map)
	check(not q.jump(me), "enraizado no salta")


func test_predictor_follows_the_server_while_knocked() -> void:
	var map := GameMap.create("test")
	var p := Predictor.new()
	p.place(0.0, 0.0, map)
	var me := {"x": 2.0, "z": 0.0, "y": 0.6, "rot": 0.0, "alive": true, "cc": {}, "buffs": {}, "cast": null, "dashing": true, "air": true}
	for i in 30:
		p.step(DT, Vector2(-1, 0), me, "warrior", "fight", map, 0.01, 1.0, 0.0)
	near(p.m.x, 2.0, 0.1, "sigue la posición del servidor")
	near(p.m.y, 0.6, 0.1, "y su altura")
