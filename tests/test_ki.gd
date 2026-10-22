extends TestBase
## Guerrero Ki: punches, ki blast, flash step, ki guard, awakening, ki palm and the ki wave ultimate.

func _match() -> ArenaMatch:
	var m := ArenaMatch.new(2, [
		{"name": "G", "cls": "ki", "team": "red", "peer": 1},
		{"name": "M", "cls": "mage", "team": "blue", "peer": 2},
		{"name": "H", "cls": "hunter", "team": "blue", "peer": 3}], 0, "hard", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	var g: ArenaUnit = m.units[0]
	g.x = 6
	g.z = 0
	g.rot = 0.0
	m.units[1].x = 6  # off the test map's bushes
	m.units[1].z = 2
	m.units[2].x = 6
	m.units[2].z = 9
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.block_front = 0.0
	m.block_rear = 0.0
	return m


func _slot(id: String) -> int:
	return GameData.abilities("ki").map(func(a): return a.id).find(id)


func test_ki_is_complete() -> void:
	check(GameData.classes.has("ki"), "Guerrero Ki registrado")
	var kit := GameData.kit("ki")
	eq(kit.abilities.size(), 7, "siete habilidades")
	check(ResourceLoader.exists("res://assets/icons/%s.svg" % kit.icon), "icono de clase")
	for a in kit.abilities:
		check(SpellKinds.TABLE.has(a.id), "objetivo explícito: " + a.id)
		check(SpellSchools.explicit(a.id), "escuela: " + a.id)
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "icono: " + a.id)
		check(MatchView.CAST_SOUND.has(a.id), "sonido: " + a.id)
	check(CharacterRig.available("ki"), "modelo disponible")
	check(BotBrain.PREF_RANGE.has("ki"), "los bots saben a qué distancia jugarlo")


func test_ki_wave_hits_everyone_on_the_line() -> void:
	var m := _match()
	var g: ArenaUnit = m.units[0]
	var a: ArenaUnit = m.units[1]
	var b: ArenaUnit = m.units[2]
	g.ult = 100.0
	var ha := a.hp
	var hb := b.hp
	check(m.cast_ability(g, _slot("kiwave"), b.x, b.z, 1000, b.id), "carga la onda")
	for i in 110:
		m.tick(1000 + i * (1000.0 / 60.0))
	near(ha - a.hp, 140.0, 0.01, "le pega al primero de la línea")
	near(hb - b.hp, 140.0, 0.01, "y al que está detrás")
	check(m.fx.any(func(f): return f.k == "beam"), "rayo en el cliente")


func test_flash_step_awaken_guard_and_palm() -> void:
	var m := _match()
	var g: ArenaUnit = m.units[0]
	var far: ArenaUnit = m.units[2]
	m._execute(g, _slot("flashstep"), far.x, far.z, far.id, 1000)
	check(Vector2(g.x - far.x, g.z - far.z).length() < 2.0, "aparece junto al objetivo")
	m._execute(g, _slot("awaken"), g.x, g.z, -1, 1000)
	check(g.haste_until >= 9000 and g.crit_until >= 9000, "despertar: velocidad y críticos 8 s")
	m._execute(g, _slot("kiguard"), g.x, g.z, -1, 1000)
	eq(g.absorb, 65.0, "la guardia absorbe 65")
	far.cast = {"slot": 1, "start_at": 1000, "ends_at": 3000, "ax": 0, "az": 0, "target_id": -1, "lock": -1, "pushes": 0}
	m._execute(g, _slot("palm"), far.x, far.z, far.id, 1500)
	check(far.cast.is_empty(), "la palma interrumpe")
	check(far.dash_left > 0.0, "y lo empuja")


func test_ki_bot_fights() -> void:
	seed(6)
	var m := _match()
	var g: ArenaUnit = m.units[0]
	g.brain = BotBrain.new("hard")
	m.units[1].alive = false
	var t: ArenaUnit = m.units[2]
	t.z = 14.0
	t.max_hp = 100000
	t.hp = 30000
	var seen := {}
	for i in 2400:
		var now := 100 + i * (1000.0 / 60.0)
		if i % 500 == 0:
			g.ult = 100.0
		if i % 300 == 150:
			t.x = g.x
			t.z = g.z + 9.0 if g.z < 10.0 else g.z - 9.0
		m.tick(now)
		for f in m.fx:
			if f.k == "cast" and f.id == g.id: seen[f.ability] = true
		m.fx.clear()
	for id in ["punch", "kiblast", "flashstep", "kiwave"]:
		check(seen.has(id), "el bot usa " + id + " (" + str(seen.keys()) + ")")
