extends TestBase
## El Crack (footballer): ball auto-attack, chip shot, nutmeg, dribble, one-two with an ally, tackle and the golazo.

func _match() -> ArenaMatch:
	var m := ArenaMatch.new(2, [
		{"name": "K", "cls": "crack", "team": "red", "peer": 1},
		{"name": "A", "cls": "priest", "team": "red", "peer": 4},
		{"name": "W", "cls": "warrior", "team": "blue", "peer": 2},
		{"name": "M", "cls": "mage", "team": "blue", "peer": 3}], 0, "hard", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	var k: ArenaUnit = m.units[0]
	k.x = 6
	k.z = 0
	k.rot = 0.0
	m.units[1].x = 6
	m.units[1].z = -14
	m.units[2].x = 6  # off the test map's bushes
	m.units[2].z = 2.5
	m.units[3].x = 10
	m.units[3].z = 10
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.block_front = 0.0
	m.block_rear = 0.0
	return m


func _slot(id: String) -> int:
	return GameData.abilities("crack").map(func(a): return a.id).find(id)


func test_crack_is_complete() -> void:
	check(GameData.classes.has("crack"), "El Crack registrado")
	var kit := GameData.kit("crack")
	eq(kit.abilities.size(), 7, "siete habilidades")
	check(ResourceLoader.exists("res://assets/icons/%s.svg" % kit.icon), "icono de clase")
	for a in kit.abilities:
		check(SpellKinds.TABLE.has(a.id), "objetivo explícito: " + a.id)
		check(SpellSchools.explicit(a.id), "escuela: " + a.id)
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "icono: " + a.id)
		check(MatchView.CAST_SOUND.has(a.id), "sonido: " + a.id)
	check(CharacterRig.available("crack"), "modelo disponible")
	check(BotBrain.PREF_RANGE.has("crack"), "los bots saben a qué distancia jugarlo")


func test_nutmeg_slips_behind_and_disorients() -> void:
	var m := _match()
	var k: ArenaUnit = m.units[0]
	var w: ArenaUnit = m.units[2]
	w.rot = PI  # facing the crack
	var hp := w.hp
	m._execute(k, _slot("nutmeg"), w.x, w.z, w.id, 1000)
	check(hp - w.hp > 0.0 and hp - w.hp <= 10.0, "10 de daño (menos la armadura del guerrero): %s" % (hp - w.hp))
	eq(w.incap_kind, "disorient", "desorientado")
	check(w.incap_until > 2500, "2 s")
	check(k.z > w.z, "aparece del otro lado")
	check(m.fx.any(func(f): return f.k == "label" and f.text == "¡CAÑO!"), "cartel ¡CAÑO!")


func test_dribble_and_one_two_move_fast() -> void:
	var m := _match()
	var k: ArenaUnit = m.units[0]
	var ally: ArenaUnit = m.units[1]
	k.slow_until = 9000
	m._execute(k, _slot("dribble"), k.x, k.z + 5, -1, 1000)
	check(k.dash_left > 0.0 and k.dash_vz > 0.0, "arranca hacia adelante")
	eq(k.slow_until, 0.0, "se saca la ralentización")
	check(k.haste_until >= 3000, "corre más rápido")
	k.dash_left = 0.0
	m._execute(k, _slot("onetwo"), ally.x, ally.z, ally.id, 2000)
	check(k.dash_left > 0.0 and k.dash_vz < 0.0, "pique hacia el aliado")
	check(ally.haste_until >= 5000, "el aliado también corre más")


func test_golazo_knocks_back_and_stuns() -> void:
	var m := _match()
	var k: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[3]
	m.units[2].x = -20.0  # out of the ball's path
	k.ult = 100.0
	check(m.cast_ability(k, _slot("golazo"), t.x, t.z, 1000, t.id), "se acomoda")
	var hp := t.hp
	for i in 120:
		m.tick(1000 + i * (1000.0 / 60.0))
	near(hp - t.hp, 120.0, 0.01, "120 de daño")
	check(m.fx.any(func(f): return f.k == "label" and f.text == "¡GOLAZO!") or t.stun_until > 0.0, "¡GOLAZO! y aturdido")


func test_crack_bot_plays_its_kit() -> void:
	seed(8)
	var m := _match()
	var k: ArenaUnit = m.units[0]
	k.brain = BotBrain.new("hard")
	m.units[2].z = 8.0
	for u in m.units:
		if u.team != k.team:
			u.max_hp = 100000
			u.hp = 30000
	var seen := {}
	for i in 2400:
		var now := 100 + i * (1000.0 / 60.0)
		if i % 500 == 0:
			k.ult = 100.0
		if i % 300 == 150:  # someone runs at the crack
			m.units[2].x = k.x
			m.units[2].z = k.z + 2.0
		m.tick(now)
		for f in m.fx:
			if f.k == "cast" and f.id == k.id: seen[f.ability] = true
		m.fx.clear()
	for id in ["pass", "chip", "nutmeg", "golazo"]:
		check(seen.has(id), "el bot usa " + id + " (" + str(seen.keys()) + ")")
