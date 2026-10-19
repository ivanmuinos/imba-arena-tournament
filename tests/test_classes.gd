extends TestBase
## Class identities: asymmetric health, armor and crit, and the time-to-kill matchups they create.

func _hp(cls: String, spec := "") -> float:
	return float(GameData.kit(cls, spec).hp)


func _armor(cls: String, spec := "") -> float:
	return float(GameData.kit(cls, spec).get("armor", 0.0))


func _duel(a_cls: String, a_spec: String, b_cls: String, b_spec := "") -> ArenaMatch:
	var m := ArenaMatch.new(2, [{"name": "A", "cls": a_cls, "spec": a_spec, "team": "red", "peer": 1}, {"name": "B", "cls": b_cls, "spec": b_spec, "team": "blue", "peer": 2}], 0, "normal", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = -1.0  # never crits, whatever the class bonus
	m.units[0].x = 0.0
	m.units[0].z = 0.0
	m.units[1].x = 0.0
	m.units[1].z = 3.0
	return m


## Seconds a scripted rotation (abilities in priority order, no movement) needs to kill the other unit; -1 when it never does.
func _ttk(a_cls: String, a_spec: String, b_cls: String, b_spec: String, order: Array, from_stealth := false) -> float:
	var m := _duel(a_cls, a_spec, b_cls, b_spec)
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	a.ult = 0.0
	if from_stealth:
		a.stealth_until = 1.0e9
	var now := 1000.0
	var start := now
	while b.alive and now - start < 40000.0:
		now += 1000.0 / 60.0
		m.tick(now)
		if a.cast.is_empty():
			for slot in order:
				if m.cast_ability(a, slot, b.x, b.z, now, b.id):
					break
		if a.auto_on == false and a.ability(0).get("auto", false):
			m.start_auto(a, b.id)
	return (now - start) / 1000.0 if not b.alive else -1.0


func test_health_spread_follows_the_identities() -> void:
	var rogue := _hp("rogue")
	var warrior := _hp("warrior")
	for c in GameData.classes:
		for sp in (GameData.spec_ids(c) if not GameData.spec_ids(c).is_empty() else [""]):
			if c != "rogue":
				check(_hp(c, sp) > rogue, "%s/%s tiene más vida que el asesino" % [c, sp])
			if c != "warrior":
				check(_hp(c, sp) < warrior, "%s/%s tiene menos vida que el guerrero" % [c, sp])
	near(rogue, 380.0, 25.0, "el asesino ronda las 380")
	near(warrior, 640.0, 25.0, "el guerrero ronda las 640")
	check(_hp("mage", "fire") < _hp("mage", "frost"), "Fuego más frágil que Escarcha")
	for c in ["priest", "hunter", "warlock"]:
		check(_hp("mage", "fire") < _hp(c), "Fuego tiene menos vida que %s" % c)
	check(_hp("warlock") > _hp("hunter"), "el brujo aguanta más que el cazador")


func test_only_the_warrior_has_heavy_armor_and_the_rogue_the_crit() -> void:
	for c in GameData.classes:
		if c != "warrior":
			check(_armor(c) < _armor("warrior"), "%s tiene menos armadura que el guerrero" % c)
	near(_armor("warrior"), 0.20, 0.04, "el guerrero reduce ~18-22% del daño físico")
	check(float(GameData.kit("rogue").get("crit", 0.0)) >= 0.10, "el asesino tiene mucho crítico")
	for c in ["warrior", "priest", "hunter", "warlock"]:
		check(float(GameData.kit(c).get("crit", 0.0)) < float(GameData.kit("rogue").crit), "%s crítica menos que el asesino" % c)


func test_armor_reduces_physical_damage_only() -> void:
	var m := _duel("rogue", "", "warrior")
	var rogue: ArenaUnit = m.units[0]
	var warrior: ArenaUnit = m.units[1]
	var armor := float(warrior.spec().armor)
	var hp := warrior.hp
	m._damage(warrior, 100.0, rogue, 1000.0, "stab")
	near(hp - warrior.hp, 100.0 * (1.0 - armor), 0.01, "daño físico reducido por la armadura")
	hp = warrior.hp
	m._damage(warrior, 100.0, rogue, 1000.0, "fireball")
	near(hp - warrior.hp, 100.0, 0.01, "la magia no se reduce")
	hp = warrior.hp
	m._damage(warrior, 100.0, rogue, 1000.0, "burn")
	near(hp - warrior.hp, 100.0, 0.01, "los efectos periódicos tampoco")
	hp = rogue.hp
	m._damage(rogue, 100.0, warrior, 1000.0, "strike")
	near(hp - rogue.hp, 100.0, 0.01, "sin armadura no hay reducción")


func test_units_use_the_spec_health_and_crit_bonus() -> void:
	var m := ArenaMatch.new(2, [{"name": "A", "cls": "mage", "spec": "fire", "team": "red", "peer": 1}, {"name": "B", "cls": "mage", "spec": "frost", "team": "blue", "peer": 2}], 0, "normal", "test")
	eq(m.units[0].max_hp, _hp("mage", "fire"), "vida de Fuego")
	eq(m.units[1].max_hp, _hp("mage", "frost"), "vida de Escarcha")
	eq(GameData.entry_max_hp({"cls": "mage", "spec": "frost"}), _hp("mage", "frost"), "el cliente calcula la misma vida")
	var r := _duel("rogue", "", "warrior")
	r.C.CRIT_CHANCE = 0.15
	near(r.crit_chance(r.units[0]), 0.15 + float(r.units[0].spec().crit), 0.001, "el crítico del asesino se suma al base")
	near(r.crit_chance(r.units[1]), 0.15, 0.001, "el guerrero tiene el crítico base")


func test_assassin_kills_a_mage_fast_but_not_a_warrior() -> void:
	# an opener from stealth, then the burst rotation: stun, evisceration, stabs
	var vs_mage := _ttk("rogue", "", "mage", "fire", [2, 1, 0], true)
	check(vs_mage > 0.0 and vs_mage >= 3.0 and vs_mage <= 10.0, "el asesino mata a un mago de fuego en 3-10 s sin crítico ni movimiento (%.1f)" % vs_mage)
	var vs_warrior := _ttk("rogue", "", "warrior", "", [2, 1, 0], true)
	check(vs_warrior < 0.0 or vs_warrior > vs_mage * 1.8, "al guerrero le lleva mucho más (%.1f vs %.1f)" % [vs_warrior, vs_mage])


func test_everyone_needs_longer_to_kill_the_warrior_than_a_mage() -> void:
	for pair in [["hunter", "", [1, 0]], ["warlock", "", [5, 0]], ["rogue", "", [2, 1, 0]]]:
		var vs_mage := _ttk(pair[0], pair[1], "mage", "frost", pair[2])
		var vs_war := _ttk(pair[0], pair[1], "warrior", "", pair[2])
		check(vs_mage > 0.0, "%s mata al mago (%.1f)" % [pair[0], vs_mage])
		check(vs_war < 0.0 or vs_war > vs_mage * 1.15, "%s tarda bastante más en matar al guerrero (%.1f vs %.1f)" % [pair[0], vs_war, vs_mage])


func test_champion_stat_bars_reflect_the_identities_and_tooltips_show_numbers() -> void:
	var rogue := GameData.kit("rogue")
	var warrior := GameData.kit("warrior")
	eq(int(rogue.stats.hp), 1, "asesino: vida mínima en la barra")
	eq(int(warrior.stats.hp), 5, "guerrero: vida máxima")
	check(int(rogue.stats.damage) > int(warrior.stats.damage), "el asesino pega más que el guerrero")
	check(int(GameData.kit("mage", "fire").stats.damage) > int(GameData.kit("mage", "frost").stats.damage), "Fuego pega más que Escarcha")
	check(int(GameData.kit("mage", "frost").stats.control) >= 5, "Escarcha: el mejor control")
	check(HowToContent.stat_tip(warrior, "hp").contains("620") and HowToContent.stat_tip(warrior, "hp").contains("%d%%" % roundi(float(warrior.armor) * 100.0)), "tooltip de vida con armadura")
	check(HowToContent.stat_tip(rogue, "damage").contains("crítico"), "tooltip de daño con el crítico del asesino")
	check(HowToContent.stat_tip(rogue, "mobility").contains("7.4"), "tooltip de movilidad")
	for c in GameData.classes:
		check(str(GameData.classes[c].get("identity", "")).length() > 30, "%s tiene identidad escrita" % c)
	check(HowToContent.classes().contains("Armadura") and HowToContent.classes().contains("Cañón de cristal"), "la página Campeones muestra armadura e identidad")


func test_a_sheep_regains_health_quickly() -> void:
	var m := ArenaMatch.new(1, [{"name": "M", "cls": "mage", "spec": "frost", "team": "red", "peer": 0}, {"name": "V", "cls": "warrior", "spec": "", "team": "blue", "peer": 0}], 1000000.0, "normal", "bridge")
	var now := 1000000.0
	while m.phase != "fight":
		now += 1000.0 / 60.0
		m.tick(now)
	var v: ArenaUnit = m.units[1]
	for u in m.units:
		u.brain = null
	v.hp = v.max_hp * 0.5
	m._cc(v, "incap", 4000.0, now, "poly")
	var start := v.hp
	var numbers := 0
	for i in 240:
		now += 1000.0 / 60.0
		m.tick(now)
		numbers += m.fx.filter(func(f): return f.k == "heal" and f.id == v.id).size()
		m.fx.clear()
	near(v.hp - start, v.max_hp * float(GameData.C.POLY_HEAL_PCT) * 4.0, v.max_hp * 0.03, "4 s de oveja curan ~%d%% de la vida" % roundi(GameData.C.POLY_HEAL_PCT * 400.0))
	check(numbers >= 3 and numbers <= 5, "un número por segundo, no uno por cuadro")
	var hp := v.hp
	for i in 60:
		now += 1000.0 / 60.0
		m.tick(now)
	check(v.hp <= hp + 0.01, "terminada la oveja, deja de curar")


func _fight_duel(a_cls: String, a_spec: String, b_cls: String) -> ArenaMatch:
	var m := ArenaMatch.new(1, [{"name": "A", "cls": a_cls, "spec": a_spec, "team": "red", "peer": 0}, {"name": "B", "cls": b_cls, "spec": "", "team": "blue", "peer": 0}], 1000000.0, "normal", "test")
	var now := 1000000.0
	while m.phase != "fight":
		now += 1000.0 / 60.0
		m.tick(now)
	for u in m.units:
		u.brain = null
	m.units[0].x = 0.0
	m.units[0].z = 0.0
	m.units[1].x = 0.0
	m.units[1].z = 8.0
	m.units[0].rot = 0.0  # facing +Z, at the enemy
	m.set_meta("now", now)
	return m


func test_global_cooldown_like_wow() -> void:
	var m := _fight_duel("mage", "frost", "warrior")
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	var now: float = m.get_meta("now")
	check(m.cast_ability(a, 1, b.x, b.z, now, b.id), "lanza de hielo")
	check(not m.cast_ability(a, 2, b.x, b.z, now + 500.0, b.id), "nova durante el GCD: no")
	check(m.cast_ability(a, 5, b.x, b.z, now + 500.0, b.id), "contrahechizo está fuera del GCD")
	check(m.cast_ability(a, 2, b.x, b.z, now + 1550.0, b.id), "pasado 1,5 s, sí")
	var r := _fight_duel("rogue", "", "mage")
	eq(ArenaMatch.gcd_ms(r.units[0]), 1000.0, "el asesino tiene GCD de 1 s")
	check(not ArenaMatch.on_gcd(r.units[0].ability(0)), "el ataque automático no usa GCD")
	var snap := m.snapshot_for(a, now + 600.0)
	check(int(snap.you.cds[2]) > 0, "el cliente ve el GCD en la barra")


func test_damage_pushes_a_cast_back_twice() -> void:
	var m := _fight_duel("mage", "frost", "hunter")
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	var now: float = m.get_meta("now")
	check(m.cast_ability(a, 0, b.x, b.z, now, b.id), "empieza la descarga de escarcha")
	var end0: float = a.cast.ends_at
	for i in 3:
		m._damage(a, 5.0, b, now + 100.0, "shot")
	near(a.cast.ends_at - end0, 1000.0, 0.01, "3 golpes: se atrasa 0,5 s dos veces y no más")


func test_trinket_breaks_control_once_every_two_minutes() -> void:
	var m := _fight_duel("rogue", "", "warrior")
	var a: ArenaUnit = m.units[0]
	var now: float = m.get_meta("now")
	a.stun_until = now + 4000.0
	a.fear_until = now + 4000.0
	a.slow_until = now + 4000.0
	check(m.use_trinket(a, now), "usa el abalorio aturdido")
	check(now >= a.stun_until and now >= a.fear_until and now >= a.slow_until, "rompe aturdimiento, miedo y ralentización")
	a.stun_until = now + 4000.0
	check(not m.use_trinket(a, now + 1000.0), "no otra vez enseguida")
	check(m.use_trinket(a, now + float(GameData.C.TRINKET_CD_MS)), "a los 2 minutos, sí")
