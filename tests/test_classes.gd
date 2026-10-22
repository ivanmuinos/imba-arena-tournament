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
	m.block_front = 0.0  # armor / rotation fixtures measure unblocked damage
	m.block_rear = 0.0
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
	check(HowToContent.stat_tip(warrior, "hp").contains("640") and HowToContent.stat_tip(warrior, "hp").contains("%d%%" % roundi(float(warrior.armor) * 100.0)), "tooltip de vida con armadura")
	check(HowToContent.stat_tip(rogue, "damage").contains("crítico"), "tooltip de daño con el crítico del asesino")
	check(HowToContent.stat_tip(rogue, "mobility").contains("7.4"), "tooltip de movilidad")
	for c in GameData.classes:
		check(str(GameData.classes[c].get("identity", "")).length() > 30, "%s tiene identidad escrita" % c)
	check(HowToContent.classes().contains("Armadura") and HowToContent.classes().contains("Cañón de cristal"), "la página Campeones muestra armadura e identidad")
