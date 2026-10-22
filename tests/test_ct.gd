extends TestBase
## Counter-terrorist: rifle auto-attack, headshot, flashbang, kevlar, knife sprint, butt-stroke and the sniper ultimate.

func _match() -> ArenaMatch:
	var m := ArenaMatch.new(2, [
		{"name": "C", "cls": "ct", "team": "red", "peer": 1},
		{"name": "M", "cls": "mage", "team": "blue", "peer": 2},
		{"name": "P", "cls": "priest", "team": "blue", "peer": 3}], 0, "hard", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	m.units[0].x = 0
	m.units[0].z = 0
	m.units[1].x = 6  # off the test map's bush at (0, 12)
	m.units[1].z = 10
	m.units[2].x = 8
	m.units[2].z = 11
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.units[0].rot = 0.0
	return m


func _slot(id: String) -> int:
	return GameData.abilities("ct").map(func(a): return a.id).find(id)


func _fly(m: ArenaMatch, from: float, ms: float) -> void:
	for i in int(ms / (1000.0 / 60.0)):
		m._step_projectiles(from + i * (1000.0 / 60.0))


func test_ct_is_complete() -> void:
	check(GameData.classes.has("ct"), "Antiterrorista registrado")
	var kit := GameData.kit("ct")
	eq(kit.abilities.size(), 7, "siete habilidades")
	check(ResourceLoader.exists("res://assets/icons/%s.svg" % kit.icon), "icono de clase")
	for a in kit.abilities:
		check(SpellKinds.TABLE.has(a.id), "objetivo explícito: " + a.id)
		check(SpellSchools.explicit(a.id), "escuela: " + a.id)
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "icono: " + a.id)
		check(MatchView.CAST_SOUND.has(a.id), "sonido: " + a.id)
	eq(SpellKinds.kind(kit.abilities[0]), "auto", "el fusil es un auto-ataque")
	check(CharacterRig.available("ct"), "modelo disponible")
	check(BotBrain.PREF_RANGE.has("ct"), "los bots saben a qué distancia jugarlo")


func test_rifle_and_headshot_hit_their_target() -> void:
	var m := _match()
	var c: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[1]
	var hp := t.hp
	check(m.cast_ability(c, _slot("rifle"), t.x, t.z, 1000, t.id), "dispara")
	_fly(m, 1000, 400)
	near(hp - t.hp, 30.0, 0.01, "una bala: 30")
	hp = t.hp
	check(m.cast_ability(c, _slot("headshot"), t.x, t.z, 3000, t.id), "empieza a apuntar")
	for i in 120:
		m.tick(3000 + i * (1000.0 / 60.0))
	near(hp - t.hp, 72.0, 0.01, "tiro a la cabeza: 72")
	check(m.fx.any(func(f): return f.k == "label" and f.text == "¡A LA CABEZA!"), "cartel ¡A LA CABEZA!")


func test_flashbang_blinds_everyone_around_where_it_lands() -> void:
	var m := _match()
	var c: ArenaUnit = m.units[0]
	var a: ArenaUnit = m.units[1]
	var b: ArenaUnit = m.units[2]
	check(m.cast_ability(c, _slot("flashbang"), a.x, a.z, 1000), "tira la granada")
	eq(a.incap_kind, "blind", "ciega al primero")
	check(a.incap_until > 3000 and b.incap_until > 3000, "y al que estaba al lado")
	check(c.incap_until <= 0.0, "no al que la tira")
	check(m.fx.any(func(f): return f.k == "flash"), "destello en el cliente")


func test_kevlar_knife_and_butt_stroke() -> void:
	var m := _match()
	var c: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[1]
	m._execute(c, _slot("kevlar"), c.x, c.z, -1, 1000)
	eq(c.absorb, 80.0, "el chaleco absorbe 80")
	c.slow_until = 9000
	c.root_until = 9000
	m._execute(c, _slot("knife"), c.x, c.z, -1, 1000)
	check(c.haste_until >= 5000, "corre más rápido 4 s")
	eq(c.root_until, 0.0, "se saca las raíces")
	eq(c.slow_until, 0.0, "y la ralentización")
	t.z = 2.0
	t.cast = {"slot": 1, "start_at": 1000, "ends_at": 3000, "ax": 0, "az": 0, "target_id": -1, "lock": -1, "pushes": 0}
	m._execute(c, _slot("bash"), t.x, t.z, t.id, 1500)
	check(t.cast.is_empty(), "el culatazo interrumpe")
	check(t.silence_until > 3000, "y silencia 2 s")


func test_sniper_ultimate_needs_charge_and_hits_hard() -> void:
	var m := _match()
	var c: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[1]
	t.x = 0.0
	t.z = 30.0
	check(not m.cast_ability(c, _slot("awp"), t.x, t.z, 1000, t.id), "sin carga no se puede")
	c.ult = 100.0
	check(m.cast_ability(c, _slot("awp"), t.x, t.z, 1000, t.id), "con carga apunta")
	var hp := t.hp
	for i in 150:
		m.tick(1000 + i * (1000.0 / 60.0))
	var dealt := hp - t.hp
	check(is_equal_approx(dealt, 150.0) or is_equal_approx(dealt, 150.0 * float(m.C.CRIT_MULT)), "150 de daño desde 30 m (o su crítico): %s" % dealt)


func test_ct_bot_shoots_flashes_and_snipes() -> void:
	seed(5)
	var m := _match()
	var c: ArenaUnit = m.units[0]
	c.brain = BotBrain.new("hard")
	for u in m.units:
		if u != c:
			u.max_hp = 100000
			u.hp = 100000
	var seen := {}
	for i in 3000:
		var now := 100 + i * (1000.0 / 60.0)
		if i % 600 == 0:
			c.ult = 100.0
			m.units[1].hp = 30000  # a weak-looking target to snipe
		m.tick(now)
		for f in m.fx:
			if f.k == "cast" and f.id == c.id: seen[f.ability] = true
		m.fx.clear()
	for id in ["rifle", "headshot", "flashbang", "awp"]:
		check(seen.has(id), "el bot usa " + id + " (" + str(seen.keys()) + ")")
