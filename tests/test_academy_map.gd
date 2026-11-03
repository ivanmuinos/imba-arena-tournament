extends TestBase
## The Academia's own arena: rooms in a line, doors that open by script, plates to step on. It never reaches the normal game.


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


func _map() -> GameMap:
	return GameMap.create(GameMap.ACADEMY_ID)


func test_the_academy_is_never_a_normal_map() -> void:
	check(not GameMap.IDS.has(GameMap.ACADEMY_ID), "no entra en el sorteo")
	check(not GameData.maps.has(GameMap.ACADEMY_ID), "no está en el catálogo")
	eq(MatchConfig.normalize({"map": GameMap.ACADEMY_ID}).map, "random", "una configuración no puede pedirlo")
	eq(_map().id, GameMap.ACADEMY_ID, "el mapa existe")


func test_other_maps_have_no_doors_or_plates() -> void:
	for id in GameMap.IDS + [GameMap.PRACTICE_ID, "test"]:
		var m := GameMap.create(id)
		eq(m.doors.size(), 0, "%s: sin puertas" % id)
		eq(m.plates.size(), 0, "%s: sin placas" % id)
		var before := m.obstacles.size()
		m.set_doors(7)
		eq(m.obstacles.size(), before, "%s: la máscara no cambia nada" % id)


func test_doors_start_closed_and_block_walking_and_sight() -> void:
	var m := _map()
	var z: float = m.doors[0].z
	check(not Rules.has_los(m, {"x": 0.0, "z": z + 3.0}, {"x": 0.0, "z": z - 3.0}), "puerta cerrada: no se ve")
	var walker := M.new(0.0, z + 0.2)
	Rules.collide(walker, m)
	check(absf(walker.z - z) > 0.7, "puerta cerrada: no se pasa (%.2f)" % walker.z)
	m.set_doors(1)
	check(Rules.has_los(m, {"x": 0.0, "z": z + 3.0}, {"x": 0.0, "z": z - 3.0}), "abierta: se ve")
	var through := M.new(0.0, z + 0.2)
	Rules.collide(through, m)
	near(through.z, z + 0.2, 0.001, "abierta: se pasa")
	m.set_doors(0)
	check(not Rules.has_los(m, {"x": 0.0, "z": z + 3.0}, {"x": 0.0, "z": z - 3.0}), "se puede volver a cerrar")


func test_only_the_masked_door_opens() -> void:
	var m := _map()
	m.set_doors(1 << 1)
	check(m.door_open(1), "la puerta 1 abre")
	check(not m.door_open(0), "la 0 sigue cerrada")
	var z: float = m.doors[0].z
	check(not Rules.has_los(m, {"x": 0.0, "z": z + 3.0}, {"x": 0.0, "z": z - 3.0}), "la 0 sigue tapando")


func test_a_grate_door_blocks_walking_but_not_sight() -> void:
	var m := _map()
	var z: float = m.doors[GameMap.GRATE_DOOR].z
	check(Rules.has_los(m, {"x": 0.0, "z": z + 3.0}, {"x": 0.0, "z": z - 3.0}), "la reja deja ver")
	var walker := M.new(0.0, z + 0.2)
	Rules.collide(walker, m)
	check(absf(walker.z - z) > 0.7, "pero no pasar")


func test_doors_survive_the_per_tick_state_refresh() -> void:
	var m := _map()
	m.set_doors(1)
	m.apply_state(true, 500.0)
	check(m.door_open(0), "sigue abierta")
	var z: float = m.doors[0].z
	check(Rules.has_los(m, {"x": 0.0, "z": z + 3.0}, {"x": 0.0, "z": z - 3.0}), "apply_state no la cierra")


func test_the_whole_line_can_be_walked_with_every_door_open() -> void:
	var m := _map()
	m.set_doors((1 << m.doors.size()) - 1)
	eq(Rules.obstacle_hit(m, 0.0, m.spawns.red[0].z, 0.0, m.spawns.blue[0].z), -1.0, "nada corta el eje central")
	for team in ["red", "blue"]:
		for s in m.spawns[team]:
			var w := M.new(s.x, s.z)
			Rules.collide(w, m)
			near(w.x, s.x, 0.001, "spawn libre x")
			near(w.z, s.z, 0.001, "spawn libre z")


func test_plates_are_reachable_and_found_by_position() -> void:
	var m := _map()
	check(m.plates.size() > 0 and m.plates.size() <= 30, "caben en una máscara")
	m.set_doors((1 << m.doors.size()) - 1)
	for i in m.plates.size():
		var p: Dictionary = m.plates[i]
		check(absf(p.x) < m.half_x and absf(p.z) < m.half_z, "placa %d adentro" % i)
		var w := M.new(p.x, p.z)
		Rules.collide(w, m)
		check(Vector2(w.x - p.x, w.z - p.z).length() < 0.01, "placa %d no está dentro de una pared o pilar" % i)
		check(Rules.hazard_at(m, p.x, p.z).is_empty(), "placa %d no está sobre lava" % i)
		eq(m.plate_at(p.x, p.z), i, "se encuentra por posición")
	eq(m.plate_at(0.0, 0.0), -1, "fuera de una placa")


func test_the_lava_room_does_not_hide_anyone() -> void:
	var m := _map()
	check(m.hazards.size() > 0, "hay lava para practicar")
	var h: Dictionary = m.hazards[0]
	check(not m.level_los_blocked(h.x, h.z, h.x + h.hx + 2.0, h.z), "acá la lava es plana: no corta la vista")
	var bridge := GameMap.create("bridge")
	var b: Dictionary = bridge.hazards[0]
	check(bridge.level_los_blocked(b.x, b.z, 0.0, 15.0), "en el Puente sigue cortándola")


func test_the_pillar_room_blocks_sight() -> void:
	var m := _map()
	var c := m.room_z(GameMap.PILLAR_ROOM)
	check(not Rules.has_los(m, {"x": -7.0, "z": c - 5.0}, {"x": -7.0, "z": c + 5.0}), "el pilar tapa")
