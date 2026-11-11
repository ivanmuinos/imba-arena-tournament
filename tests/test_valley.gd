extends TestBase
## The Academia's valley: an open map you can walk from end to end, with zones, paths and a lava river with fords.

const NOW := 1000000.0


func _map() -> GameMap:
	return GameMap.create(GameMap.VALLEY_ID)


func _blocked(m: GameMap, x: float, z: float, r := 0.6) -> bool:
	for o in m.obstacles:
		if o.k == "c":
			if Vector2(x - o.x, z - o.z).length() < o.r + r:
				return true
		elif absf(x - o.x) < o.hx + r and absf(z - o.z) < o.hz + r:
			return true
	return false


func test_the_valley_is_a_lesson_map_outside_the_catalog() -> void:
	var m := _map()
	eq(m.id, GameMap.VALLEY_ID, "se construye")
	eq(m.name, GameMap.VALLEY_NAME, "con su nombre")
	check(not GameMap.IDS.has(GameMap.VALLEY_ID), "no entra en el sorteo de arenas")
	check(not GameData.maps.has(GameMap.VALLEY_ID), "ni en el catálogo de salas")
	check(GameMap.is_lesson_map(GameMap.VALLEY_ID) and GameMap.is_lesson_map(GameMap.ACADEMY_ID), "es un mapa de la Academia")
	check(not GameMap.is_lesson_map("bridge"), "una arena no lo es")
	check(m.half_x >= 60.0 and m.half_z >= 60.0, "es grande: %s x %s" % [m.half_x * 2.0, m.half_z * 2.0])


func test_every_zone_is_inside_flat_and_has_a_name() -> void:
	var m := _map()
	check(m.zones.size() >= 6, "tiene zonas")
	var names := {}
	for zn in m.zones:
		check(str(zn.name) != "" and not names.has(zn.name), "%s tiene un nombre propio" % zn.id)
		names[zn.name] = true
		check(absf(float(zn.x)) + float(zn.r) < m.half_x and absf(float(zn.z)) + float(zn.r) < m.half_z, "%s entra en el mapa" % zn.id)
		eq(str(m.zone_at(float(zn.x), float(zn.z)).get("id", "")), str(zn.id), "%s se reconoce en su centro" % zn.id)
		if str(zn.id) not in ["river", "grove"]:
			near(m.height_at(float(zn.x), float(zn.z)), 0.0, 0.05, "%s está en piso plano" % zn.id)
	check(m.zone_at(0.0, 20.0).is_empty(), "el campo abierto no es ninguna zona")


func test_no_slope_in_the_valley_stops_a_walker() -> void:
	var m := _map()
	var worst := 0.0
	var x := -m.half_x + 1.0
	while x < m.half_x:
		var z := -m.half_z + 1.0
		while z < m.half_z:
			worst = maxf(worst, m.slope_at(x, z).length())
			z += 1.5
		x += 1.5
	check(worst < Rules.MAX_SLOPE * 0.75, "la pendiente más brava se camina (%.2f)" % worst)


func test_the_paths_are_clear_from_the_camp_to_every_zone() -> void:
	var m := _map()
	for line in GameMap.VALLEY_PATHS:
		for i in line.size() - 1:
			var a := Vector2(line[i][0], line[i][1])
			var b := Vector2(line[i + 1][0], line[i + 1][1])
			var steps := int(a.distance_to(b) / 0.5)
			for k in steps + 1:
				var p := a.lerp(b, float(k) / maxf(1.0, float(steps)))
				if p.distance_to(Vector2(0, -50)) < 3.0:
					continue
				check(not _blocked(m, p.x, p.y), "sendero libre en %s" % str(p))
				check(Rules.hazard_at(m, p.x, p.y).is_empty(), "y sin lava en %s" % str(p))
				near(m.path_weight(p.x, p.y), 1.0, 0.001, "es sendero")
	near(m.path_weight(20.0, 50.0), 0.0, 0.001, "el pasto no es sendero")
	near(GameMap.create(GameMap.ACADEMY_ID).path_weight(0.0, 34.0), 0.0, 0.001, "otros mapas no tienen senderos")


func test_the_river_burns_except_at_the_fords() -> void:
	var m := _map()
	check(not Rules.hazard_at(m, 0.0, GameMap.RIVER_Z).is_empty(), "el río quema en el medio")
	check(not Rules.hazard_at(m, 60.0, GameMap.RIVER_Z).is_empty(), "y cerca del borde")
	for f in GameMap.FORDS:
		check(Rules.hazard_at(m, float(f), GameMap.RIVER_Z).is_empty(), "el vado en x=%s no quema" % f)
		near(m.height_at(float(f), GameMap.RIVER_Z), 0.0, 0.05, "y está a nivel")
	check(m.height_at(0.0, GameMap.RIVER_Z) < -0.5, "la lava corre por un cauce hundido")
	check(not m.level_los_blocked(0.0, GameMap.RIVER_Z, 0.0, 0.0), "el cauce no tapa la vista")
	eq(m.ground_kind(0.0, GameMap.RIVER_Z), "lava", "lava")
	eq(m.ground_kind(GameMap.POND.x, GameMap.POND.y), "water", "agua")
	eq(m.ground_kind(0.0, 20.0), "path", "sendero")
	eq(m.ground_kind(15.0, 44.0), "grass", "pasto")


func test_the_scenery_is_the_same_every_time_and_leaves_room() -> void:
	var a := _map()
	var b := _map()
	eq(a.statics.size(), b.statics.size(), "misma cantidad de cosas")
	var same := true
	for i in a.statics.size():
		same = same and is_equal_approx(a.statics[i].x, b.statics[i].x) and is_equal_approx(a.statics[i].z, b.statics[i].z)
	check(same, "en los mismos lugares")
	var trees: Array = a.statics.filter(func(o): return str(o.get("art", "")).begins_with("tree"))
	check(trees.size() >= 60, "hay un bosque (%d árboles)" % trees.size())
	for o in a.statics:
		check(absf(o.x) < a.half_x and absf(o.z) < a.half_z, "todo queda dentro")
	check(not _blocked(a, 0.0, 57.0), "el punto de inicio está libre")
	eq(a.plates.size(), a.zones.size(), "una placa por zona, para las misiones")
	for p in a.plates:
		check(not _blocked(a, p.x, p.z, 0.3), "placa libre en %s, %s" % [p.x, p.z])


func test_a_player_walks_from_the_camp_to_the_yard() -> void:
	var sc := LessonScenarios.scenario("valley_free")
	eq(LessonScenarios.map_of(sc), GameMap.VALLEY_ID, "el escenario pide el valle")
	eq(LessonScenarios.map_of(LessonScenarios.scenario("move_1")), GameMap.ACADEMY_ID, "los demás siguen en la sala")
	var m := ArenaMatch.new(2, LessonScenarios.entries(sc, "Yo", "mage", "fire", 1), NOW, "normal", LessonScenarios.map_of(sc))
	m.journal = []
	m.stage = LessonStage.new(sc)
	m.stage.setup(m, NOW)
	var me := m.unit_for_peer(1)
	check(m.practice, "corre como práctica: sin rondas")
	near(me.z, 57.0, 0.01, "arranca en el campamento")
	var now := NOW
	var route := [Vector2(0, 34), Vector2(-20, 28), Vector2(-34, 26)]
	for goal in route:
		var guard := 0
		while Vector2(me.x, me.z).distance_to(goal) > 1.0 and guard < 3000:
			guard += 1
			now += 1000.0 / 60.0
			m.input(me, goal.x - me.x, goal.y - me.z, goal.x, goal.y)
			m.tick(now)
		check(Vector2(me.x, me.z).distance_to(goal) <= 1.0, "llega a %s (quedó en %.1f, %.1f)" % [str(goal), me.x, me.z])
	eq(str(m.map.zone_at(me.x, me.z).get("id", "")), "yard", "termina en el patio")
	near(me.y, m.map.height_at(me.x, me.z), 0.2, "pisando el suelo")


func test_the_valley_starts_over_the_local_link_only() -> void:
	var server := GameServer.new({"lesson": "valley_free"})
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var client := GameClient.new()
	var got := [""]
	client.match_started.connect(func(msg): got[0] = str(msg.map))
	client.attach(link[1], {"name": "Yo", "cls": "mage", "spec": "fire", "pref": "red"})
	for i in 10:
		server.process(16.0)
		client.poll(16.0)
	check(server.start_match(true), "arranca")
	for i in 10:
		server.process(16.0)
		client.poll(16.0)
	eq(got[0], GameMap.VALLEY_ID, "el cliente recibe el valle")
	eq(server.game.map.id, GameMap.VALLEY_ID, "y el servidor lo juega")
	check(MatchConfig.normalize({"map": GameMap.VALLEY_ID}).map != GameMap.VALLEY_ID, "una sala online no lo puede pedir")


# ---------------------------------------------------------------- minimap

func test_the_minimap_picture_shows_what_the_ground_is() -> void:
	var m := _map()
	var img := MinimapImage.paint(m, 128)
	eq(img.get_size(), Vector2i(128, 128), "del tamaño pedido")
	var at := func(x: float, z: float) -> Color:
		var uv := MinimapImage.uv_of(m, x, z)
		return img.get_pixel(int(uv.x * 128.0), int(uv.y * 128.0))
	eq(MinimapImage.uv_of(m, 0.0, 0.0), Vector2(0.5, 0.5), "el centro del mapa es el centro de la imagen")
	check(MinimapImage.uv_of(m, 0.0, -m.half_z).y < 0.01, "el norte (-z) va arriba")
	var lava: Color = at.call(0.0, GameMap.RIVER_Z)
	check(lava.r > 0.7 and lava.b < 0.3, "la lava se ve naranja (%s)" % str(lava))
	var water: Color = at.call(GameMap.POND.x, GameMap.POND.y)
	check(water.b > water.r, "la laguna se ve azul (%s)" % str(water))
	var path: Color = at.call(0.0, 20.0)
	var grass: Color = at.call(15.0, 44.0)
	check(path.r > grass.r + 0.15, "el sendero se distingue del pasto")
	check(grass.g > grass.r and grass.g > grass.b, "el pasto es verde")
	var wall: Color = at.call(0.0, 67.0)
	check(wall.v < 0.25, "los muros se ven oscuros (%s)" % str(wall))


func test_the_minimap_keeps_you_in_the_middle_and_far_things_on_the_rim() -> void:
	var mm := Minimap.new(_map())
	mm.me = Vector2(10.0, 20.0)
	eq(mm.spot(Vector2(10.0, 20.0)).at, Vector2(Minimap.SIZE, Minimap.SIZE) / 2.0, "vos, en el centro")
	var north: Dictionary = mm.spot(Vector2(10.0, 20.0 - mm.reach() * 0.5))
	check(north.inside, "algo cerca entra en la ventana")
	check(north.at.y < Minimap.SIZE / 2.0 and is_equal_approx(north.at.x, Minimap.SIZE / 2.0), "lo que está al norte se dibuja arriba")
	var east: Dictionary = mm.spot(Vector2(10.0 + mm.reach() * 0.5, 20.0))
	check(east.at.x > Minimap.SIZE / 2.0, "y lo que está al este, a la derecha")
	var far: Dictionary = mm.spot(Vector2(10.0, -60.0))
	check(not far.inside, "algo lejano queda fuera")
	near(far.at.distance_to(Vector2(Minimap.SIZE, Minimap.SIZE) / 2.0), Minimap.SIZE / 2.0 - 7.0, 0.01, "y se marca en el borde, en su dirección")
	var wide := mm.reach()
	mm.zoom = 0
	check(mm.reach() < wide, "acercar muestra menos terreno")
	mm.free()


func test_the_academy_screen_opens_the_valley() -> void:
	SettingsStore.path = "user://test_valley_settings.cfg"
	SettingsStore.clear_shared()
	var m := MenuScreen.new()
	m.offer_tutorial = false
	m.visible = false
	TestBase.tree.root.add_child(m)
	m.visible = true
	m.nav.go("academy")
	var got := [0]
	m.start_valley.connect(func(_cfg): got[0] += 1)
	(m._views.academy as MAcademy).valley_button.pressed.emit()
	eq(got[0], 1, "el botón abre el valle con tu campeón")
	TestBase.tree.root.remove_child(m)
	m.free()
	SettingsStore.path = SettingsStore.PATH
	SettingsStore.clear_shared()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_valley_settings.cfg"))
