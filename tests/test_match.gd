extends TestBase

const STEP := 1000.0 / 60.0
var now := 0.0

func test_directional_blocks_use_defender_facing_and_skip_magic_dots_cc() -> void:
	var m := _duel("rogue", "warrior", "", true)
	var a: ArenaUnit = m.units[0]
	var d: ArenaUnit = m.units[1]
	d.rot = 0.0
	a.x = d.x
	a.z = d.z + 2.0
	near(m.block_chance(d, a, now, "stab"), 0.30, 0.001, "front 30 percent")
	a.z = d.z - 2.0
	near(m.block_chance(d, a, now, "stab"), 0.05, 0.001, "rear 5 percent")
	eq(m.block_chance(d, a, now, "fireball"), 0.0, "magic cannot block")
	m._dot_tick = true
	eq(m.block_chance(d, a, now, "stab"), 0.0, "periodic cannot block")
	m._dot_tick = false
	d.stun_until = now + 100
	eq(m.block_chance(d, a, now, "stab"), 0.0, "stunned cannot block")
	d.stun_until = 0
	m.block_front = 1.0
	m.block_rear = 1.0
	var hp := d.hp
	m._damage(d, 50, a, now, "stab")
	eq(d.hp, hp, "guaranteed block prevents damage")
	check(m.fx.any(func(f): return f.k == "block" and f.id == d.id), "replicated block feedback")
	check(FxFilter.for_team(m, d.team, now).any(func(f): return f.k == "block"), "block included in defender team FX")
	d.rot = PI
	m.block_front = 0.30
	m.block_rear = 0.05
	near(m.block_chance(d, a, now, "stab"), 0.30, 0.001, "rotating defender reverses attack hemisphere")
	eq(m.block_chance(a, d, now, "strike"), 0.0, "non-warriors cannot shield block")


func _match(entries: Array, map_id := "test", diff := "normal") -> ArenaMatch:
	now = 1_000_000.0
	return ArenaMatch.new(entries.size() / 2, entries, now, diff, map_id)


func _advance(m: ArenaMatch, ms: float) -> void:
	var t := 0.0
	while t < ms:
		now += STEP
		t += STEP
		m.tick(now)


## Two (or three) units with no AI, placed in the red spawn area (open ground, line of sight).
func _duel(a: String, b: String, ally := "", blocks := false) -> ArenaMatch:
	var e := [{"name": "A", "cls": a, "team": "red", "peer": 1}, {"name": "B", "cls": b, "team": "blue", "peer": 2}]
	if ally != "":
		e.append({"name": "H", "cls": ally, "team": "blue", "peer": 3})
	var m := _match(e)
	if not blocks:  # damage/cast fixtures need guaranteed hits; block test opts in
		m.block_front = 0.0
		m.block_rear = 0.0
	_advance(m, 20100)  # prep -> fight
	var s: Array = m.map.spawns.red
	m.units[0].x = s[0].x
	m.units[0].z = s[0].z
	m.units[1].x = s[2].x
	m.units[1].z = s[2].z
	if m.units.size() > 2:
		m.units[2].x = s[1].x
		m.units[2].z = s[1].z
	_advance(m, 30)
	return m


func _bots(classes: Array) -> Array:
	var out := []
	for i in classes.size():
		out.append({"name": "b%d" % i, "cls": classes[i], "team": "red" if i < classes.size() / 2 else "blue"})
	return out


func _play_out(m: ArenaMatch) -> void:
	var limit := now + 15 * 60_000
	while not m.done and now < limit:
		now += STEP
		m.tick(now)


func test_full_bot_matches_reach_a_winner() -> void:
	for spec in [["test", ["mage", "hunter", "warrior", "priest"]], ["tomb", ["rogue", "priest", "mage", "warrior", "hunter", "rogue"]]]:
		var m := _match(_bots(spec[1]), spec[0])
		_play_out(m)
		check(m.done, "%s: la partida termina" % spec[0])
		eq(maxi(m.score.red, m.score.blue), int(GameData.C.ROUNDS_TO_WIN), "%s: alguien gana 2 rondas" % spec[0])
		var dmg := 0.0
		for u in m.units:
			dmg += u.dmg
		check(dmg > 500, "%s: hubo pelea" % spec[0])
		var deaths := 0
		var kills := 0
		for u in m.units:
			deaths += u.deaths
			kills += u.kills
		check(deaths > 0 and deaths >= kills, "%s: se cuentan las muertes" % spec[0])


func test_counterspell_interrupts_silences_and_locks() -> void:
	var m := _duel("mage", "mage")
	var red := m.units[0]
	var blue := m.units[1]
	check(m.cast_ability(blue, 1, red.x, red.z, now), "Piroexplosión empieza")
	check(not blue.cast.is_empty(), "está casteando")
	check(m.cast_ability(red, 5, blue.x, blue.z, now, blue.id), "Contrahechizo")
	check(blue.cast.is_empty(), "interrumpido")
	check(blue.silence_until > now, "silenciado")
	check(not m.cast_ability(blue, 2, red.x, red.z, now), "silenciado no puede castear")
	check(blue.cds[1] >= now + 3900, "hechizo bloqueado 4 s")


func test_charge_closes_gap_and_stuns() -> void:
	var m := _duel("warrior", "mage")
	var a := m.units[0]
	var b := m.units[1]
	check(not m.cast_ability(a, 1, b.x, b.z, now, b.id), "Golpe mortal fuera de alcance")
	check(m.cast_ability(a, 2, b.x, b.z, now, b.id), "Carga")
	_advance(m, 400)
	check(Vector2(a.x - b.x, a.z - b.z).length() < 2.5, "llegó al objetivo")
	check(b.stun_until > now, "aturdido")


## Human warrior (A) + priest bot (P) vs an idle human enemy (E); returns [m, A, P, E].
func _priest_setup(enemy_cls := "rogue") -> Array:
	var e := [{"name": "A", "cls": "warrior", "team": "red", "peer": 1}, {"name": "P", "cls": "priest", "team": "red"},
		{"name": "E", "cls": enemy_cls, "team": "blue", "peer": 2}, {"name": "F", "cls": "mage", "team": "blue", "peer": 3}]
	var m := _match(e)
	_advance(m, 20100)
	var s: Array = m.map.spawns.red
	for i in 4:
		m.units[i].x = s[0].x
		m.units[i].z = s[0].z
	m.units[3].x += 200.0  # second enemy parked far away, out of the fight
	return [m, m.units[0], m.units[1], m.units[2]]


func _healed(a: ArenaUnit, hp0: float) -> bool:
	return a.hp > hp0 + 1.0 or a.absorb > 0.0


func test_priest_bot_heals_hurt_ally_with_no_enemy_in_sight() -> void:
	var r := _priest_setup()
	var m: ArenaMatch = r[0]
	var a: ArenaUnit = r[1]
	var p: ArenaUnit = r[2]
	var e: ArenaUnit = r[3]
	e.x += 200.0  # enemy far away: nothing to shoot at
	p.x += 4.0
	a.hp = a.max_hp * 0.4
	var hp0 := a.hp
	_advance(m, 4000)
	check(_healed(a, hp0), "el sacerdote cura aunque no vea enemigos (%.0f → %.0f)" % [hp0, a.hp])


func test_priest_bot_heals_while_an_enemy_is_on_it() -> void:
	var r := _priest_setup("warrior")
	var m: ArenaMatch = r[0]
	var a: ArenaUnit = r[1]
	var p: ArenaUnit = r[2]
	var e: ArenaUnit = r[3]
	p.x += 4.0
	e.x = p.x + 1.0  # enemy warrior glued to the priest (idle human, never attacks)
	e.z = p.z
	p.cds[3] = now + 60_000  # Psychic Scream on cooldown
	a.hp = a.max_hp * 0.35
	var hp0 := a.hp
	_advance(m, 4000)
	check(_healed(a, hp0), "cura al aliado aunque tenga un melee encima (%.0f → %.0f)" % [hp0, a.hp])


func test_priest_bot_walks_to_a_hurt_ally_out_of_range() -> void:
	var r := _priest_setup()
	var m: ArenaMatch = r[0]
	var a: ArenaUnit = r[1]
	var p: ArenaUnit = r[2]
	var e: ArenaUnit = r[3]
	e.x += 200.0
	var best := Vector2.ZERO
	for o in [Vector2(30, 0), Vector2(-30, 0), Vector2(0, 30), Vector2(0, -30)]:
		var q := {"x": a.x + o.x, "z": a.z + o.y}
		Rules.collide(q, m.map)
		if Vector2(q.x - a.x, q.z - a.z).length() > best.length():
			best = Vector2(q.x - a.x, q.z - a.z)
	p.x = a.x + best.x
	p.z = a.z + best.y
	var d0 := best.length()
	check(d0 > 25.0, "el sacerdote arranca fuera de alcance (%.1f m)" % d0)
	a.hp = a.max_hp * 0.4
	var hp0 := a.hp
	_advance(m, 8000)
	check(Vector2(p.x - a.x, p.z - a.z).length() < d0 - 3.0, "se acercó al aliado herido")
	check(_healed(a, hp0), "y lo curó (%.0f → %.0f)" % [hp0, a.hp])


func test_disengage_always_leaps_backwards_from_the_aim() -> void:
	var m := _duel("hunter", "warrior")
	var h := m.units[0]
	var x0 := h.x
	var z0 := h.z
	# The client sends a point in front of the hunter; the leap goes the other way.
	check(m.cast_ability(h, 4, h.x + 12.0, h.z, now), "Retirada")
	_advance(m, 500)
	check(h.x < x0 - 3.0, "saltó hacia atrás (%.1f → %.1f)" % [x0, h.x])
	near(h.z, z0, 0.5, "sin desvío lateral")


func test_mortal_strike_halves_healing() -> void:
	var m := _duel("warrior", "mage", "priest")
	var a := m.units[0]
	var b := m.units[1]
	var h := m.units[2]
	a.x = b.x + 1.5
	a.z = b.z
	b.hp = 100.0
	m.cast_ability(h, 1, b.x, b.z, now, b.id)
	_advance(m, 1600)
	var healed := b.hp - 100.0
	check(healed > 30, "la Sanación cura (%s)" % healed)
	b.hp = 100.0
	h.cds[1] = 0.0
	m.cast_ability(a, 1, b.x, b.z, now, b.id)
	var after := b.hp
	m.cast_ability(h, 1, b.x, b.z, now, b.id)
	_advance(m, 1600)
	check(b.hp - after < healed * 0.6, "Herida mortal reduce la curación")


func test_absorb_shield_soaks_damage() -> void:
	var m := _duel("warrior", "mage", "priest")
	var a := m.units[0]
	var b := m.units[1]
	a.x = b.x + 1.5
	a.z = b.z
	m.cast_ability(m.units[2], 2, b.x, b.z, now, b.id)
	var hp := b.hp
	m.cast_ability(a, 1, b.x, b.z, now, b.id)
	eq(b.hp, hp, "el escudo absorbe")


func test_fear_makes_enemies_run_away() -> void:
	var m := _duel("warrior", "mage", "priest")
	var a := m.units[0]
	var h := m.units[2]
	a.x = h.x + 3
	a.z = h.z
	m.cast_ability(h, 3, h.x, h.z, now)
	check(a.fear_until > now, "aterrorizado")
	var d0 := Vector2(a.x - h.x, a.z - h.z).length()
	_advance(m, 1000)
	check(Vector2(a.x - h.x, a.z - h.z).length() > d0 + 2, "huye")


func test_bush_hides_enemy_from_snapshot() -> void:
	var m := _duel("mage", "mage")
	var red := m.units[0]
	var blue := m.units[1]
	var b: Dictionary = m.map.bushes[0]
	blue.x = b.x
	blue.z = b.z
	red.x = b.x - 12 if b.x > 0 else b.x + 12
	red.z = b.z
	blue.revealed_until = 0.0
	var ids: Array = m.snapshot_for(red, now).units.map(func(u): return u.id)
	check(not ids.has(blue.id), "el rival no recibe al oculto")
	check(m.snapshot_for(blue, now).you.inBush, "sabe que está oculto")


func _adjacent(m: ArenaMatch) -> void:
	var a := m.units[0]
	var b := m.units[1]
	a.x = b.x + 1.5
	a.z = b.z
	m.input(a, 0, 0, b.x, b.z)  # facing the target
	_advance(m, 20)  # the server applies the new facing on the next tick


func test_casters_never_auto_attack() -> void:
	for cls in ["mage", "priest"]:
		var m := _duel(cls, "warrior")
		var a := m.units[0]
		var b := m.units[1]
		check(not m.start_auto(a, b.id), "%s no puede iniciar auto-ataque" % cls)
		m.set_target(a, b.id)
		var hp := b.hp
		_advance(m, 3000)
		eq(b.hp, hp, "%s: sin daño automático con objetivo seleccionado" % cls)
		check(not a.auto_on, "%s: auto apagado" % cls)


func test_melee_auto_attack_needs_target_range_and_front() -> void:
	var m := _duel("warrior", "mage")
	var a := m.units[0]
	var b := m.units[1]
	_adjacent(m)
	m.set_target(a, b.id)
	var hp := b.hp
	_advance(m, 2000)
	eq(b.hp, hp, "seleccionar no ataca: hay que iniciar el auto-ataque")
	check(m.start_auto(a, b.id), "inicia")
	_advance(m, 3000)
	check(hp - b.hp >= GameData.ability("warrior", 0).dmg * 2, "golpea solo (%s)" % (hp - b.hp))
	m.input(a, 0, 0, a.x + 10, a.z)  # looking away
	_advance(m, 100)
	var hp2 := b.hp
	_advance(m, 2500)
	eq(b.hp, hp2, "de espaldas no pega")
	check(a.auto_on, "pero sigue encendido")
	m.input(a, 0, 0, b.x, b.z)
	a.x = b.x + 12.0  # out of melee reach
	_advance(m, 100)
	hp2 = b.hp
	_advance(m, 2000)
	eq(b.hp, hp2, "fuera de alcance no pega")
	check(a.auto_on, "y sigue encendido")


func test_auto_attack_stops_on_death_friendly_target_or_clear() -> void:
	var m := _duel("warrior", "mage")
	var a := m.units[0]
	var b := m.units[1]
	_adjacent(m)
	m.start_auto(a, b.id)
	b.hp = 5.0
	_advance(m, 1500)
	check(not b.alive, "murió")
	check(not a.auto_on, "el auto-ataque se apaga con la muerte del objetivo")
	var m2 := _duel("mage", "warrior", "priest")
	var w := m2.units[1]
	var ally := m2.units[2]
	m2.units[0].x = w.x + 1.5
	m2.units[0].z = w.z
	m2.input(w, 0, 0, m2.units[0].x, m2.units[0].z)
	m2.units[0].hp = 9999.0
	check(m2.start_auto(w, m2.units[0].id), "inicia contra el mago")
	m2.set_target(w, ally.id)
	check(not w.auto_on, "elegir un aliado lo apaga")
	m2.start_auto(w, m2.units[0].id)
	m2.set_target(w, -1)
	check(not w.auto_on, "limpiar el objetivo lo apaga")
	check(not m2.start_auto(w, ally.id), "no se puede atacar a un aliado")


func test_melee_ability_on_target_starts_auto_attack() -> void:
	var m := _duel("warrior", "mage")
	var a := m.units[0]
	var b := m.units[1]
	_adjacent(m)
	check(m.cast_ability(a, 1, b.x, b.z, now, b.id), "Golpe mortal")
	check(a.auto_on and a.auto_target == b.id, "enciende el auto-ataque")


func test_hunter_auto_attack_is_ranged() -> void:
	var m := _duel("hunter", "mage")
	var a := m.units[0]
	var b := m.units[1]
	m.input(a, 0, 0, b.x, b.z)
	check(m.start_auto(a, b.id), "inicia")
	var hp := b.hp
	_advance(m, 2500)
	check(hp - b.hp >= GameData.ability("hunter", 0).dmg * 2, "dispara solo a distancia (%s)" % (hp - b.hp))
	check(m.snapshot_for(a, now).you.auto, "el snapshot informa el auto-ataque")


# ---------------------------------------------------------------- dampening (replaces the closing zone)

func test_dampening_curve_starts_late_grows_linearly_and_is_capped() -> void:
	var C := GameData.C
	eq(Rules.dampening(0.0), 0.0, "sin amortiguación al empezar")
	eq(Rules.dampening(float(C.DAMP_START_MS) - 1.0), 0.0, "ni un instante antes del inicio")
	near(Rules.dampening(float(C.DAMP_START_MS) + 10000.0), 10.0 * float(C.DAMP_PER_S), 1e-6, "crece por segundo")
	eq(Rules.dampening(1e9), float(C.DAMP_MAX), "tope")
	check(not GameData.C.has("ZONE_FULL") and not GameData.C.has("ZONE_DPS"), "la zona que se cierra ya no existe en los datos")


func test_dampening_reduces_healing_and_nobody_burns_outside_the_old_zone() -> void:
	var m := _duel("warrior", "mage", "priest")
	var b := m.units[1]
	var h := m.units[2]
	b.hp = 100.0
	m.cast_ability(h, 1, b.x, b.z, now, b.id)
	_advance(m, 1600)
	var normal := b.hp - 100.0
	# jump the fight clock forward: heal again at ~45% dampening
	m.fight_start -= float(GameData.C.DAMP_START_MS) + 45000.0 / maxf(1.0, float(GameData.C.DAMP_PER_S) * 100.0) * 1.0
	b.hp = 100.0
	h.cds[1] = 0.0
	var damp := Rules.dampening(now - m.fight_start)
	check(damp > 0.2, "hay amortiguación (%.2f)" % damp)
	m.cast_ability(h, 1, b.x, b.z, now, b.id)
	_advance(m, 1600)
	var damped := b.hp - 100.0
	check(damped < normal * (1.0 - damp * 0.7), "la curación se reduce (%.1f -> %.1f con %.0f%%)" % [normal, damped, damp * 100.0])
	# standing far from the centre costs nothing any more
	b.x = 40.0
	b.z = 0.0
	var hp := b.hp
	_advance(m, 3000)
	check(b.hp >= hp - 0.01, "fuera del antiguo círculo no hay daño")
	var snap := m.snapshot_for(m.units[0], now)
	check(snap.has("damp") and not snap.has("zone") and snap.damp > 0.0, "el snapshot informa la amortiguación y no la zona")


# ---------------------------------------------------------------- casting is not cancelled by repeats; melee feel

func test_spamming_the_same_or_another_spell_never_restarts_or_cancels_a_cast() -> void:
	var m := _duel("mage", "warrior")
	var a := m.units[0]
	var b := m.units[1]
	a.x = b.x
	a.z = b.z - 12.0
	a.rot = 0.0
	check(m.cast_ability(a, 1, b.x, b.z, now, b.id), "pirotecnia empieza a lanzarse")
	var started: float = a.cast.start_at
	for i in 10:
		_advance(m, 60)
		check(not m.cast_ability(a, 1, b.x, b.z, now, b.id), "repetir la misma no hace nada")
		check(not m.cast_ability(a, 0, b.x, b.z, now, b.id), "otra tampoco")
		eq(a.cast.get("start_at", -1.0), started, "el lanzamiento no se reinició (%d)" % i)
	var hp := b.hp
	_advance(m, 2200)
	check(b.hp < hp, "el lanzamiento original se completó y pegó")


func test_jump_and_escape_cancel_a_cast_without_cooldown() -> void:
	var m := _duel("mage", "warrior")
	var a := m.units[0]
	var b := m.units[1]
	a.x = b.x
	a.z = b.z - 12.0
	m.cast_ability(a, 1, b.x, b.z, now, b.id)
	m.jump(a, now)
	check(a.cast.is_empty(), "saltar cancela el lanzamiento")
	a.cds[1] = 0.0
	m.cast_ability(a, 1, b.x, b.z, now, b.id)
	m.cancel_cast(a)
	check(a.cast.is_empty(), "Esc cancela el lanzamiento")
	check(a.cds[1] <= now + 1.0, "cancelar no deja recarga")


func test_melee_needs_facing_but_with_a_generous_cone_and_range_leeway() -> void:
	var m := _duel("rogue", "warrior")
	var a := m.units[0]
	var b := m.units[1]
	a.x = b.x
	a.z = b.z - 2.0
	a.rot = PI   # facing away
	check(not m.cast_ability(a, 1, b.x, b.z, now, b.id), "de espaldas no pega")
	a.rot = 1.2  # ~70 degrees off: still inside the 180 degree cone
	check(m.cast_ability(a, 1, b.x, b.z, now, b.id), "70 grados de costado todavía pega")
	var m2 := _duel("rogue", "warrior")
	var r := m2.units[0]
	var t := m2.units[1]
	r.rot = 0.0
	r.x = t.x
	r.z = t.z - 4.4   # range 3 + 0.8 leeway = 3.8: out when the target stands still
	check(not m2.cast_ability(r, 1, t.x, t.z, now, t.id), "quieto a 4.4 m: fuera de alcance")
	t.vx = 0.0
	t.vz = 5.0
	check(m2.cast_ability(r, 1, t.x, t.z, now, t.id), "a 4.4 m pero corriendo: la tolerancia para blancos móviles alcanza")


func test_auto_attack_warns_once_when_it_cannot_hit() -> void:
	var m := _duel("rogue", "warrior")
	var a := m.units[0]
	var b := m.units[1]
	a.x = b.x
	a.z = b.z - 9.0
	a.rot = 0.0
	check(m.start_auto(a, b.id), "se prende el auto-ataque")
	m.errors.clear()
	_advance(m, 3000)
	var warns := m.errors.filter(func(e): return e.text == "Fuera de alcance")
	check(warns.size() >= 1 and warns.size() <= 3, "avisa que está fuera de alcance, sin spamear (%d)" % warns.size())
	a.rot = PI
	b.z = a.z + 2.0
	b.x = a.x
	m.errors.clear()
	_advance(m, 2500)
	check(m.errors.any(func(e): return e.text.contains("mirar")), "avisa que hay que mirar al objetivo")


# ---------------------------------------------------------------- priest AI: stays with the team and keeps the human healed

func _team_fight(map_id: String, enemy_cls: String, enemy_spec := "") -> Array:
	# Reproduce bot skill, movement, think timing and crits independently of earlier tests.
	# These are fixed regression scenarios; the balance simulator covers random fights.
	seed(0)
	now = 1_000_000.0
	var e := [
		{"name": "Human", "cls": "warrior", "team": "red", "peer": 1},
		{"name": "Pri", "cls": "priest", "team": "red", "peer": 0},
		{"name": "Foe", "cls": enemy_cls, "spec": enemy_spec, "team": "blue", "peer": 0},
		{"name": "Foe2", "cls": enemy_cls, "spec": enemy_spec, "team": "blue", "peer": 0},
	]
	var m := ArenaMatch.new(2, e, now, "normal", map_id)
	m.block_rng.seed = 0  # warrior blocks roll on their own generator: fix it too
	_advance(m, 20100)
	return [m, m.units[0], m.units[1], m.units[2], m.units[3]]


func test_priest_bot_keeps_a_fighting_human_ally_healed_over_a_real_fight() -> void:
	var healed_total := 0.0
	var human_hp_min := 1.0
	for map_id in ["test", "pillars"]:
		var r := _team_fight(map_id, "warrior")
		var m: ArenaMatch = r[0]
		# This fixture measures healing under sustained damage, independently of random blocks.
		m.block_front = 0.0
		m.block_rear = 0.0
		var human: ArenaUnit = r[1]
		var pri: ArenaUnit = r[2]
		# the human "player" fights the enemy warriors by standing still (never moves): they come to him
		var t := 0.0
		while t < 20000.0 and m.phase == "fight":
			_advance(m, 100)
			t += 100.0
			human_hp_min = minf(human_hp_min, human.hp / human.max_hp)
		healed_total += pri.healed
		check(pri.healed > 20.0 or not human.alive, "%s: el sacerdote curó (%.0f) mientras el humano peleaba" % [map_id, pri.healed])
	check(healed_total > 40.0, "en total curó una cantidad real (%.0f)" % healed_total)


func test_priest_bot_stays_close_to_and_in_sight_of_the_team_when_nobody_needs_healing() -> void:
	var r := _team_fight("pillars", "warrior")
	var m: ArenaMatch = r[0]
	var human: ArenaUnit = r[1]
	var pri: ArenaUnit = r[2]
	for e in [r[3], r[4]]:
		e.stun_until = now + 1.0e9   # enemies frozen in place at the far end: nobody gets hurt
	pri.x = 0.0   # the priest starts far from his team (arena centre; the human waits in his start room)
	pri.z = -2.0
	var far0 := Vector2(pri.x - human.x, pri.z - human.z).length()
	_advance(m, 9000)
	var d := Vector2(pri.x - human.x, pri.z - human.z).length()
	check(d < 18.0, "vuelve con el equipo: %.1f m -> %.1f m" % [far0, d])
	check(Rules.has_los(m.map, pri, human), "y con línea de visión al aliado")
	var close_samples := 0
	var total := 0
	for i in 40:
		_advance(m, 200)
		total += 1
		if Vector2(pri.x - human.x, pri.z - human.z).length() < 18.0 and Rules.has_los(m.map, pri, human):
			close_samples += 1
	check(close_samples >= total - 3, "se queda cerca y a la vista (%d/%d muestras)" % [close_samples, total])


func test_priest_bot_takes_cover_from_an_enemy_caster_when_nobody_needs_healing() -> void:
	var r := _team_fight("pillars", "mage", "fire")
	var m: ArenaMatch = r[0]
	var human: ArenaUnit = r[1]
	var pri: ArenaUnit = r[2]
	var foe: ArenaUnit = r[3]
	var foe2: ArenaUnit = r[4]
	foe2.x = 40.0   # parked far away
	foe2.z = 40.0
	# a spot where the caster can see the priest, with the ally close by
	human.x = 10.0
	human.z = 0.0
	pri.x = 12.0
	pri.z = -4.0
	foe.x = 2.0
	foe.z = -14.0
	foe.stun_until = now + 1.0e9   # the enemy mage stands there (stunned) and never attacks
	foe.brain = null
	foe2.stun_until = now + 1.0e9
	var exposed := 0
	var total := 0
	for i in 50:
		_advance(m, 200)
		if i < 20:
			continue
		total += 1
		if Rules.has_los(m.map, foe, pri):
			exposed += 1
	check(exposed < total * 0.75, "el sacerdote se esconde de la línea de visión del mago enemigo (expuesto %d/%d)" % [exposed, total])
	check(Vector2(pri.x - human.x, pri.z - human.z).length() < 18.0, "sin alejarse de su equipo")


func test_a_stalled_round_ends_by_time_limit_for_the_team_with_more_health() -> void:
	var m := _duel("rogue", "warrior")
	var a := m.units[0]
	var b := m.units[1]
	b.hp = b.max_hp * 0.4
	m.fight_start = now - float(GameData.C.ROUND_LIMIT_MS) + 500.0
	var before: Dictionary = m.score.duplicate()
	_advance(m, 300)
	eq(m.score, before, "todavía no se cumplió el límite")
	_advance(m, 600)
	eq(m.score.red, before.red + 1, "al límite gana el equipo con más vida (rojo)")
	check(m.phase != "fight", "la ronda terminó")
	var m2 := _duel("rogue", "warrior")
	m2.units[0].hp = 100.0
	m2.units[1].hp = 100.0
	m2.fight_start = now - float(GameData.C.ROUND_LIMIT_MS) - 100.0
	_advance(m2, 100)
	eq(m2.score, {"red": 0, "blue": 0}, "con vida pareja la ronda es empate: nadie suma")
	check(m2.phase != "fight", "y termina igual")
