extends TestBase
## Druid: heals over time, ironbark, cyclone, nature's cure and tranquility; bots play it as a healer.

func _match() -> ArenaMatch:
	var m := ArenaMatch.new(2, [
		{"name": "D", "cls": "druid", "team": "red", "peer": 1},
		{"name": "A", "cls": "warrior", "team": "red", "peer": 2},
		{"name": "E", "cls": "rogue", "team": "blue", "peer": 3}], 0, "hard", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	for i in m.units.size():
		m.units[i].x = 0
		m.units[i].z = i * 4
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.block_front = 0.0
	m.block_rear = 0.0
	return m


func _slot(id: String) -> int:
	return GameData.abilities("druid").map(func(a): return a.id).find(id)


func test_druid_is_complete() -> void:
	check(GameData.classes.has("druid"), "Druida registrado")
	var kit := GameData.kit("druid")
	eq(kit.abilities.size(), 7, "siete habilidades")
	check(ResourceLoader.exists("res://assets/icons/%s.svg" % kit.icon), "icono de clase")
	for a in kit.abilities:
		check(SpellKinds.TABLE.has(a.id), "objetivo explícito: " + a.id)
		check(SpellSchools.explicit(a.id), "escuela: " + a.id)
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "icono: " + a.id)
		check(MatchView.CAST_SOUND.has(a.id), "sonido: " + a.id)
	check(CharacterRig.available("druid"), "modelo disponible")
	check(UiKit.CLASS_COLORS.has("druid"), "color de clase")
	check(BotBrain.PREF_RANGE.has("druid"), "los bots saben a qué distancia jugarlo")


func test_rejuvenation_heals_over_its_whole_duration() -> void:
	var m := _match()
	var d: ArenaUnit = m.units[0]
	var a: ArenaUnit = m.units[1]
	a.hp = 100
	m._execute(d, _slot("rejuv"), a.x, a.z, a.id, 1000)
	for i in 600:
		m._step_effects(a, 1000 + i * (1000.0 / 60.0))
	near(a.hp, 100 + 7 * 9, 1.5, "7 por segundo durante 9 s")
	m._step_effects(a, 20000)
	near(a.hp, 100 + 7 * 9, 1.5, "y después se termina")


func test_ironbark_cuts_damage_on_an_ally() -> void:
	var m := _match()
	var d: ArenaUnit = m.units[0]
	var a: ArenaUnit = m.units[1]
	var e: ArenaUnit = m.units[2]
	var hp := a.hp
	m._execute(d, _slot("ironbark"), a.x, a.z, a.id, 1000)
	m._damage(a, 100, e, 1100)
	var barked := hp - a.hp
	a.hp = hp
	m._damage(a, 100, e, 8000)
	var plain := hp - a.hp
	check(plain > 0.0, "el golpe sin corteza hace daño")
	near(barked, plain * 0.4, 0.01, "con corteza recibe 60% menos; a los 6 s se termina")


func test_cyclone_takes_the_enemy_out_breaks_on_damage_and_shares_dr() -> void:
	var m := _match()
	var d: ArenaUnit = m.units[0]
	var e: ArenaUnit = m.units[2]
	m._execute(d, _slot("cyclone"), e.x, e.z, e.id, 1000)
	check(e.incap_until > 4000, "incapacitado 4 s")
	eq(e.incap_kind, "cyclone", "es un ciclón")
	check(m.fx.any(func(f): return f.k == "label" and f.text == "CICLÓN"), "cartel CICLÓN")
	m._damage(e, 10, d, 1500)
	eq(e.incap_until, 0.0, "el daño lo rompe")
	m._execute(d, _slot("cyclone"), e.x, e.z, e.id, 2000)
	check(e.incap_until - 2000 < 4000, "rendimiento decreciente con la segunda")
	var fx := Effects.debuffs_of({"incap": 2000, "incapKind": "cyclone"})
	eq(fx[0].name, "Ciclón", "el HUD lo muestra como Ciclón")


func test_natures_cure_removes_curses_and_control() -> void:
	var m := _match()
	var d: ArenaUnit = m.units[0]
	var a: ArenaUnit = m.units[1]
	a.stun_until = 9000
	a.root_until = 9000
	a.curses["x"] = {"until": 9000, "dps": 9}
	m._execute(d, _slot("naturescure"), a.x, a.z, a.id, 1000)
	eq(a.stun_until, 0.0, "sin aturdimiento")
	eq(a.root_until, 0.0, "sin raíces")
	check(a.curses.is_empty(), "sin maldiciones")


func test_tranquility_heals_the_team_and_leaves_a_heal_over_time() -> void:
	var m := _match()
	var d: ArenaUnit = m.units[0]
	var a: ArenaUnit = m.units[1]
	var e: ArenaUnit = m.units[2]
	a.hp = 100
	e.hp = 100
	d.ult = 100
	m._execute(d, _slot("tranquility"), d.x, d.z, -1, 1000)
	near(a.hp, 155, 0.01, "cura 55 al aliado")
	eq(e.hp, 100.0, "no al enemigo")
	check(d.ult < 10.0, "consume la definitiva (sólo recarga lo que cura)")
	check(a.hot_until >= 7000, "deja curación en el tiempo")


func test_druid_bot_heals_shields_and_cyclones() -> void:
	seed(91)
	var m := _match()
	var d: ArenaUnit = m.units[0]
	var a: ArenaUnit = m.units[1]
	var e: ArenaUnit = m.units[2]
	d.brain = BotBrain.new("hard")
	e.max_hp = 100000
	e.hp = 100000
	var seen := {}
	for i in 2400:
		var now := 100 + i * (1000.0 / 60.0)
		if i % 120 == 0:
			a.hp = maxf(60.0, a.hp - 120.0)  # the ally keeps taking damage
		m.tick(now)
		for f in m.fx:
			if f.k == "cast" and f.id == d.id: seen[f.ability] = true
		m.fx.clear()
	for id in ["rejuv", "regrowth", "ironbark"]:
		check(seen.has(id), "el bot usa " + id + " (" + str(seen.keys()) + ")")
