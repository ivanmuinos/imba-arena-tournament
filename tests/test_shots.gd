extends TestBase
## Menu background camera: shots stay smooth, inside the arena and out of every solid shape.


func test_shot_cycle_and_fade() -> void:
	var a := MenuShots.at(0.0)
	eq(a.shot, 0, "arranca en el primer plano")
	near(a.dark, 1.0, 1e-6, "negro al inicio del corte")
	var m := MenuShots.at(MenuShots.SHOT_LEN * 0.5)
	eq(m.dark, 0.0, "sin oscurecer a mitad del plano")
	eq(MenuShots.at(MenuShots.SHOT_LEN + 1.0).shot, 1, "segundo plano")
	eq(MenuShots.at(MenuShots.SHOT_LEN * 3.0 + 1.0).shot, 0, "vuelve al primero (ciclo de 3)")
	eq(MenuShots.at(1.0, 2).shot, 2, "se puede empezar por otro plano")
	check(MenuShots.at(MenuShots.SHOT_LEN - 0.05).dark > 0.8, "se oscurece antes del corte")


func test_every_shot_is_smooth() -> void:
	for map_id in GameMap.IDS:
		for shot in MenuShots.SHOTS:
			var prev: Dictionary = MenuShots.sample(map_id, shot, 0.0)
			var t := 0.1
			while t <= MenuShots.SHOT_LEN:
				var cur: Dictionary = MenuShots.sample(map_id, shot, t)
				var speed: float = (cur.pos as Vector3).distance_to(prev.pos) / 0.1
				check(speed < 4.0, "%s/%d: la cámara no se sacude (%.1f m/s en t=%.1f)" % [map_id, shot, speed, t])
				prev = cur
				t += 0.1


func test_cameras_stay_clear_of_solid_shapes_and_inside_the_arena() -> void:
	GameData.ensure_loaded()
	for map_id in GameMap.IDS:
		var map := GameMap.create(map_id)
		map.apply_state(true, 60000.0)  # gates open, every living pillar up: the worst case
		for shot in MenuShots.SHOTS:
			var t := 0.0
			while t <= MenuShots.SHOT_LEN:
				var s: Dictionary = MenuShots.sample(map_id, shot, t)
				var p: Vector3 = s.pos
				check(absf(p.x) <= 26.0 and absf(p.z) <= 22.0, "%s/%d: dentro del recinto" % [map_id, shot])
				if p.y < 14.0:
					check(Rules.sdf_all(map, p.x, p.z) > 0.9, "%s/%d t=%.1f: la cámara no atraviesa objetos (sdf %.2f en %.1f,%.1f)" % [map_id, shot, t, Rules.sdf_all(map, p.x, p.z), p.x, p.z])
				check(p.y > 1.4 and p.y < 9.0, "%s/%d: altura razonable (%.1f)" % [map_id, shot, p.y])
				t += 0.5
