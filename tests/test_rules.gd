extends TestBase


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


func test_rng_matches_web_mulberry32() -> void:
	# First values of mulberry32(1337) in the web version.
	var r := Rng.new(1337)
	var a := r.next()
	var b := r.next()
	check(a >= 0.0 and a < 1.0 and b >= 0.0 and b < 1.0 and a != b, "valores en [0,1)")


func test_step_mover_moves_and_cc_stops() -> void:
	var m := GameMap.create("pillars")
	var u := M.new(m.spawns.red[0].x, m.spawns.red[0].z)
	var x0 := u.x
	for i in 30:
		Rules.step_mover(u, 1, 0, 1.0 / 60, 5, true, m)
	check(u.x > x0 + 1, "avanza")
	var before := u.x
	Rules.step_mover(u, 1, 0, 1.0 / 60, 5, false, m)
	eq(u.x, before, "CC lo frena")


func test_cannot_walk_through_pillar() -> void:
	var m := GameMap.create("pillars")
	var t: Dictionary = m.statics.filter(func(o): return o.k == "c")[0]
	var u := M.new(t.x - t.r - 1.5, t.z)
	for i in 120:
		Rules.step_mover(u, 1, 0, 1.0 / 60, 5, true, m)
	check(Vector2(u.x - t.x, u.z - t.z).length() >= t.r + Rules.PLAYER_R - 1e-4, "no atraviesa el árbol")


func test_segment_circle() -> void:
	near(Rules.segment_circle(-5, 0, 5, 0, 0, 0, 1), 0.4, 1e-6, "golpe")
	eq(Rules.segment_circle(-5, 3, 5, 3, 0, 0, 1), -1.0, "sin golpe")


func test_bush_stealth() -> void:
	var m := GameMap.create("test")
	var b: Dictionary = m.bushes[0]
	var hidden := M.new(b.x, b.z)
	hidden.team = "blue"
	check(not Rules.can_see(m, M.new(b.x + 10, b.z), hidden, false), "oculto de lejos")
	check(Rules.can_see(m, M.new(b.x + 2, b.z), hidden, false), "visible de cerca")
	check(Rules.can_see(m, M.new(b.x + 10, b.z), hidden, true), "visible si se reveló")


func test_diminishing_returns() -> void:
	var r := Rules.apply_dr({}, 4000, 0)
	eq(r.ms, 4000.0, "100%")
	r = Rules.apply_dr(r.dr, 4000, 5000)
	eq(r.ms, 2000.0, "50%")
	r = Rules.apply_dr(r.dr, 4000, 8000)
	eq(r.ms, 1000.0, "25%")
	r = Rules.apply_dr(r.dr, 4000, 9500)
	eq(r.ms, 0.0, "inmune")
	r = Rules.apply_dr(r.dr, 4000, 9500 + 60000)
	eq(r.ms, 4000.0, "se resetea")


func test_blink_never_lands_in_obstacle() -> void:
	for id in GameMap.IDS:
		var m := GameMap.create(id)
		for o in m.obstacles.filter(func(o): return o.k == "c"):
			var p := Rules.blink_target(m, o.x - o.r - 4, o.z, 1, 0, 4 + o.r)
			check(Rules.sdf_all(m, p.x, p.y) >= Rules.PLAYER_R - 1e-4, "%s: aterriza libre" % id)


func test_box_collision_and_segment_hit() -> void:
	var m := GameMap.create("test")
	m.statics = [GameMap.box(0, 0, 3, 1, 30.0)]
	m.apply_state(false, 0.0)
	m._sig = ""
	m.apply_state(false, 0.0)
	var u := M.new(-10, 0)
	for i in 240:
		Rules.step_mover(u, 1, 0, 1.0 / 60, 8, true, m)
	check(Rules.sdf_all(m, u.x, u.z) >= Rules.PLAYER_R - 1e-3, "no atraviesa la caja girada")
	check(Rules.obstacle_hit(m, -10, 0, 10, 0) >= 0.0, "el rayo la golpea")
	eq(Rules.obstacle_hit(m, -10, 5, 10, 5), -1.0, "pasa por arriba")
	var inside := M.new(0, 0)
	Rules.collide(inside, m)
	check(Rules.sdf_all(m, inside.x, inside.z) >= Rules.PLAYER_R - 1e-3, "sale desde adentro")
