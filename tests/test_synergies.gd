extends TestBase
## Team synergies (data/synergies.json): which pairs turn on, and what each effect does in a match.

func _match(red: Array, blue_cls := "priest") -> ArenaMatch:
	var entries := []
	for i in red.size():
		entries.append({"name": "R%d" % i, "cls": red[i], "team": "red", "peer": i + 1})
	entries.append({"name": "B0", "cls": blue_cls, "team": "blue", "peer": 10})
	entries.append({"name": "B1", "cls": "priest", "team": "blue", "peer": 11})
	var m := ArenaMatch.new(2, entries, 0, "hard", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = -1.0  # no crits, whatever the kit adds
	m.block_front = 0.0
	m.block_rear = 0.0
	return m


func _foe(m: ArenaMatch) -> ArenaUnit:
	return m.units[m.units.size() - 2]


func _hit(m: ArenaMatch, src: ArenaUnit, t: ArenaUnit, ability: String) -> float:
	t.hp = t.max_hp  # several hits in a row must not kill the target
	m._damage(t, 100.0, src, 1000.0, ability)
	return t.max_hp - t.hp


func test_pairs_only_turn_on_with_both_classes() -> void:
	check(Synergies.active(["mage", "rogue"]).size() == 1, "Mago + Asesino activa una")
	check(Synergies.active(["mage", "priest"]).is_empty(), "una pareja sin bonus no activa nada")
	check(Synergies.active(["mage"]).is_empty(), "una sola clase no activa nada")
	check(Synergies.effects(["hunter", "warrior", "mage"]).size() == 2, "3v3: se suman las dos parejas del Guerrero")
	check(Synergies.banner(["priest"]) == "", "sin sinergia no hay línea en la cuenta regresiva")
	check(Synergies.banner(["mage", "rogue"]).contains("Emboscada arcana"), "la cuenta regresiva nombra la sinergia")


func test_countdown_line_fits_on_screen_with_the_most_pairs() -> void:
	var line := Synergies.banner(["mage", "warrior", "hunter", "rogue"])
	check(line.length() <= 80, "la línea no se sale de la pantalla (%d caracteres)" % line.length())


func test_every_pair_is_made_of_playable_classes() -> void:
	for p in Synergies.all():
		check(p.classes.size() == 2 and p.classes.all(func(c): return GameData.playable(c)), "%s: dos clases jugables" % p.id)
		check(str(p.desc).length() > 20 and not p.effects.is_empty(), "%s: tiene descripción y efecto" % p.id)
		check(Synergies.partner(p, p.classes[0]) == p.classes[1], "%s: la pareja se encuentra" % p.id)


func test_mage_rogue_physical_bonus_on_controlled_targets() -> void:
	var m := _match(["mage", "rogue"])
	var rogue: ArenaUnit = m.units[1]
	var t := _foe(m)
	near(_hit(m, rogue, t, "stab"), 100.0, 0.01, "sin control no hay bonus")
	t.root_until = 5000.0
	near(_hit(m, rogue, t, "stab"), 110.0, 0.01, "enraizado: +10% físico")
	t.root_until = 0.0
	t.incap_until = 5000.0
	t.incap_kind = "blind"
	near(_hit(m, rogue, t, "stab"), 100.0, 0.01, "la Ceguera no cuenta")
	t.incap_until = 5000.0
	t.incap_kind = "poly"
	near(_hit(m, rogue, t, "stab"), 110.0, 0.01, "en Polimorfia: +10% físico")
	t.root_until = 5000.0
	near(_hit(m, m.units[0], t, "fireball"), 100.0, 0.01, "la magia no recibe el bonus")


func test_no_bonus_without_the_pair() -> void:
	var m := _match(["warlock", "rogue"])
	var t := _foe(m)
	t.root_until = 5000.0
	near(_hit(m, m.units[1], t, "stab"), 100.0, 0.01, "sin el mago, el enraizado no suma")


func test_dummies_do_not_complete_a_pair() -> void:
	var m := ArenaMatch.new(2, [
		{"name": "M", "cls": "mage", "team": "red", "peer": 1},
		{"name": "D", "cls": "rogue", "team": "red", "dummy": "stand", "hp": 1000.0, "x": 0.0, "z": 0.0},
		{"name": "E", "cls": "priest", "team": "blue", "peer": 2}], 0, "hard", "test")
	check(m.synergies.get("red", {}).is_empty(), "un muñeco no completa la pareja")


func _charge_stun(m: ArenaMatch, soften: Callable) -> float:
	var w: ArenaUnit = m.units[1]
	var t := _foe(m)
	w.x = 6.0
	w.z = 0.0
	w.rot = 0.0
	t.x = 6.0
	t.z = 8.0
	m.units[0].x = 2.0
	m.units[0].z = -6.0
	m.units[m.units.size() - 1].x = 12.0
	m.units[m.units.size() - 1].z = -6.0
	soften.call(t)
	var slot: int = GameData.abilities("warrior").map(func(a): return a.id).find("charge")
	m._execute(w, slot, t.x, t.z, t.id, 1000.0, t.id)
	return t.stun_until


func test_charge_stuns_longer_on_a_target_softened_by_the_mage() -> void:
	var plain := _charge_stun(_match(["mage", "warrior"]), func(_t): pass)
	var chilled := _charge_stun(_match(["mage", "warrior"]), func(t): t.chill_until = 5000.0)
	near(chilled - plain, 500.0, 0.01, "ralentizado por Descarga: +0,5 s")
	var burn_m := _match(["mage", "warrior"])
	var burned := _charge_stun(burn_m, func(t):
		t.burn_until = 5000.0
		t.burn_by = burn_m.units[0])
	near(burned - plain, 500.0, 0.01, "ardiendo por el mago: +0,5 s")
	var slowed := _charge_stun(_match(["mage", "warrior"]), func(t):
		t.slow_until = 5000.0
		t.slow_pct = 0.5)
	near(slowed - plain, 0.0, 0.01, "el Seccionar propio no cuenta")
	var alone := _charge_stun(_match(["priest", "warrior"]), func(t): t.chill_until = 5000.0)
	near(alone - plain, 0.0, 0.01, "sin el mago en el equipo no suma")


func _conc(m: ArenaMatch) -> ArenaUnit:
	var t := _foe(m)
	var hunter: ArenaUnit = m.units[0]
	var spec: Dictionary = hunter.ability_by_id("conc")
	m._on_proj_hit({"spec": spec, "owner": hunter, "vx": 0.0, "vz": 1.0}, t, 1000.0)
	return t


func test_concussive_shot_exposes_for_physical_hits() -> void:
	var m := _match(["hunter", "warrior"])
	var t := _conc(m)
	check(t.exposed_until == t.slow_until, "expuesto mientras dura el ralentizado")
	near(_hit(m, m.units[1], t, "mortal"), 105.0, 0.01, "expuesto: +5% físico")
	near(_hit(m, m.units[0], t, "conc"), 100.0, 0.01, "el daño de escarcha no recibe el bonus")
	t.exposed_until = 0.0
	near(_hit(m, m.units[1], t, "mortal"), 100.0, 0.01, "al terminar se va el bonus")


func test_concussive_shot_does_not_expose_without_the_pair() -> void:
	var m := _match(["hunter", "rogue"])
	var t := _conc(m)
	check(t.exposed_until == 0.0, "sin el Guerrero no expone")


func test_round_reset_clears_the_marks() -> void:
	var u := ArenaUnit.new()
	u.chill_until = 9.0
	u.exposed_until = 9.0
	u.exposed_pct = 0.1
	u.reset_effects()
	check(u.chill_until == 0.0 and u.exposed_until == 0.0 and u.exposed_pct == 0.0, "la ronda nueva limpia las marcas")


func test_pyroblast_crits_a_stunned_target() -> void:
	var m := _match(["mage", "warlock"])
	var mage: ArenaUnit = m.units[0]
	var t := _foe(m)
	var crit := float(m.C.CRIT_MULT)
	near(_hit(m, mage, t, "pyro"), 100.0, 0.01, "sin aturdir no es crítica")
	t.stun_until = 5000.0
	near(_hit(m, mage, t, "pyro"), 100.0 * crit, 0.01, "aturdido: crítica")
	near(_hit(m, mage, t, "fireball"), 100.0, 0.01, "solo la Piroexplosión")
	m.combos = false
	near(_hit(m, mage, t, "pyro"), 100.0, 0.01, "sin combos no hay crítica")


func _trap_on(m: ArenaMatch, feared: bool) -> ArenaUnit:
	var v := _foe(m)
	if feared:
		v.fear_until = 5000.0
	m.traps.append({"x": v.x, "z": v.z, "armed_at": 0.0, "expires_at": 9000.0, "owner": m.units[0]})
	m._step_traps(1000.0)
	return v


func test_trap_on_a_feared_target_resists_damage_for_a_second() -> void:
	var m := _match(["hunter", "warlock"])
	var v := _trap_on(m, true)
	check(v.incap_until > 1000.0, "la trampa congela")
	m._damage(v, 10.0, m.units[1], 1500.0, "shadowbolt")
	check(v.incap_until > 1500.0, "el primer segundo el daño no lo libera")
	m._damage(v, 10.0, m.units[1], 2500.0, "shadowbolt")
	check(v.incap_until == 0.0, "después se rompe como siempre")


func test_trap_breaks_on_damage_without_fear_or_with_combos_off() -> void:
	var plain := _match(["hunter", "warlock"])
	var v := _trap_on(plain, false)
	plain._damage(v, 10.0, plain.units[1], 1500.0, "shadowbolt")
	check(v.incap_until == 0.0, "sin Miedo se rompe enseguida")
	var off := _match(["hunter", "warlock"])
	off.combos = false
	var w := _trap_on(off, true)
	off._damage(w, 10.0, off.units[1], 1500.0, "shadowbolt")
	check(w.incap_until == 0.0, "sin combos se rompe enseguida")


func test_divine_shield_keeps_a_cast_from_being_pushed_back() -> void:
	var m := _match(["mage", "rogue"])
	var t := _foe(m)
	t.cast = {"slot": 1, "start_at": 900.0, "ends_at": 3000.0, "pushes": 0}
	t.absorb = 500.0
	t.absorb_until = 9000.0
	m._damage(t, 50.0, m.units[1], 1000.0, "stab")
	near(float(t.cast.ends_at), 3000.0, 0.01, "con escudo no hay retroceso")
	t.absorb = 0.0
	m._damage(t, 50.0, m.units[1], 1000.0, "stab")
	near(float(t.cast.ends_at), 3000.0 + float(m.C.PUSHBACK_MS), 0.01, "sin escudo sí")


func _healed(m: ArenaMatch, healer: ArenaUnit, t: ArenaUnit) -> float:
	t.hp = 1.0
	m._heal(t, 100.0, healer, 1000.0)
	return t.hp - 1.0


func test_healer_pairs_heal_their_partner_more() -> void:
	for pair in [["priest", "warlock"], ["paladin", "warrior"], ["druid", "hunter"]]:
		var m := _match(pair)
		near(_healed(m, m.units[0], m.units[1]), 110.0, 0.01, "%s cura 10%% más a %s" % pair)
		near(_healed(m, m.units[0], m.units[0]), 100.0, 0.01, "%s no se cura más a sí mismo" % pair[0])
		check(Synergies.banner(pair) != "", "%s tiene aviso" % str(pair))


func test_healer_bonus_needs_the_exact_partner() -> void:
	var m := _match(["priest", "warrior"])
	near(_healed(m, m.units[0], m.units[1]), 100.0, 0.01, "el Sacerdote no tiene bonus con el Guerrero")
