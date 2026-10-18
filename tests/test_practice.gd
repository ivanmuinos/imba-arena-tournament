extends TestBase
## Arena de práctica: dummy rules, instant respawn, no rounds/dampening, DPS meter math, practice commands.

func _yard(cls := "mage", spec := "") -> ArenaMatch:
	var m := ArenaMatch.new(2, PracticeYard.entries("Tester", cls, spec), 1000.0, "normal", GameMap.PRACTICE_ID)
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	return m


func _dummy(m: ArenaMatch, kind: String) -> ArenaUnit:
	for u in m.units:
		if u.dummy == kind:
			return u
	return null


func _me(m: ArenaMatch) -> ArenaUnit:
	return m.unit_for_peer(1)


# ---------------------------------------------------------------- meter math

func test_meter_totals_shares_crits_and_casts() -> void:
	var meter := PracticeMeter.new()
	meter.record_cast("fireball", 1000.0)
	meter.record_damage("fireball", 30.0, false, 1000.0)
	meter.record_cast("fireball", 2000.0)
	meter.record_damage("fireball", 60.0, true, 2000.0)
	meter.record_cast("pyro", 3000.0)
	meter.record_damage("pyro", 110.0, false, 3000.0)
	var s := meter.snapshot(3000.0)
	eq(s.total, 200, "daño total")
	eq(s.rows.size(), 2, "dos habilidades")
	eq(s.rows[0].id, "pyro", "ordenado por daño")
	eq(s.rows[0].dmg, 110, "daño de pyro")
	near(s.rows[0].pct, 55.0, 0.01, "porcentaje")
	eq(s.rows[1].casts, 2, "lanzamientos")
	eq(s.rows[1].hits, 2, "impactos")
	eq(s.rows[1].crits, 1, "críticos")
	near(s.rows[0].pct + s.rows[1].pct, 100.0, 0.01, "los porcentajes suman 100")


func test_meter_dps_windows() -> void:
	var meter := PracticeMeter.new()
	meter.record_damage("a", 100.0, false, 1000.0)
	meter.record_damage("a", 100.0, false, 6000.0)
	meter.record_damage("a", 100.0, false, 11000.0)
	var s := meter.snapshot(11000.0)
	near(s.dps, 30.0, 0.01, "DPS total: 300 en 10 s")
	near(s.dps10, 20.0, 0.01, "últimos 10 s: dos golpes sobre 10 s")
	var late := meter.snapshot(40000.0)
	near(late.dps10, 0.0, 0.01, "sin daño reciente, la ventana queda en cero")
	check(late.dps < s.dps, "el DPS total sigue bajando mientras no pegás")


func test_meter_short_fight_is_not_underreported_and_reset_clears() -> void:
	var meter := PracticeMeter.new()
	meter.record_damage("a", 50.0, false, 5000.0)
	meter.record_damage("a", 50.0, false, 6000.0)
	var s := meter.snapshot(6000.0)
	near(s.dps10, 100.0, 0.01, "con 1 s de pelea, 100 de daño son 100 DPS")
	meter.record_heal(80.0, 6000.0)
	eq(meter.snapshot(6000.0).heal, 80, "curación hecha")
	meter.reset(7000.0)
	var z := meter.snapshot(7000.0)
	eq(z.total, 0, "reinicio: daño")
	eq(z.heal, 0, "reinicio: curación")
	eq(z.rows.size(), 0, "reinicio: tabla vacía")


func test_meter_counts_casts_that_did_no_damage() -> void:
	var meter := PracticeMeter.new()
	meter.record_cast("blink", 1000.0)
	var s := meter.snapshot(1000.0)
	eq(s.rows.size(), 1, "aparece en la tabla")
	eq(s.rows[0].casts, 1, "un lanzamiento")
	eq(s.rows[0].dmg, 0, "sin daño")
	eq(s.total, 0, "total en cero")


# ---------------------------------------------------------------- the yard

func test_yard_starts_in_the_fight_with_the_gates_open_and_no_timers() -> void:
	var m := _yard()
	eq(m.phase, "fight", "sin sala de preparación")
	check(m.practice, "modo práctica")
	var snap := m.snapshot_for(_me(m), 1000.0)
	eq(snap.phaseLeft, 0.0, "sin cuenta regresiva")
	m.tick(1_000_000.0)
	eq(m.phase, "fight", "mucho después sigue la misma fase (sin rondas)")
	eq(m.score.red + m.score.blue, 0, "sin marcador")
	check(not m.done, "la práctica no termina sola")


func test_yard_has_the_expected_dummies_at_the_right_distances() -> void:
	var m := _yard()
	var me := _me(m)
	for kind in ["melee", "mid", "far", "patrol", "caster", "cover", "ally"]:
		check(_dummy(m, kind) != null, "muñeco " + kind)
	check(m._dist(me, _dummy(m, "melee")) <= 3.0, "cuerpo a cuerpo: a mano")
	near(m._dist(me, _dummy(m, "mid")), 15.0, 1.5, "a 15 m")
	near(m._dist(me, _dummy(m, "far")), 25.0, 1.5, "a 25 m")
	eq(_dummy(m, "ally").team, me.team, "el herido es aliado")
	check(_dummy(m, "melee").team != me.team, "los demás son enemigos")
	for u in m.units:
		if u.dummy != "":
			check(u.max_hp >= 20000.0, "vida enorme: " + u.dummy)
			check(u.brain == null, "sin IA: " + u.dummy)


func test_cover_dummy_is_really_hidden_behind_the_pillar() -> void:
	var m := _yard()
	var me := _me(m)
	var cover := _dummy(m, "cover")
	check(not Rules.has_los(m.map, me, cover), "desde el inicio el pilar tapa al muñeco")
	var sees := false
	for x in range(-20, 21):
		me.x = float(x)
		me.z = 17.5
		sees = sees or Rules.has_los(m.map, me, cover)
	check(sees, "moviéndose se lo puede ver (hay línea de visión posible)")


func test_dummies_never_die_and_reset_their_health() -> void:
	var m := _yard()
	var me := _me(m)
	var d := _dummy(m, "mid")
	for i in 30:
		m._damage(d, d.max_hp, me, 2000.0 + i, "fireball")
	check(d.alive, "sigue vivo")
	check(d.hp > 0.0, "vida positiva")
	var hits := m.fx.filter(func(f): return f.k == "hit" and f.id == d.id)
	check(hits.size() >= 30, "los números de daño se siguen emitiendo")


func test_dummies_can_be_crowd_controlled() -> void:
	var m := _yard()
	var d := _dummy(m, "mid")
	m._cc(d, "fear", 3000.0, 2000.0)
	check(2500.0 < d.fear_until, "se puede aterrorizar")
	m._cc(d, "stun", 2000.0, 2000.0)
	check(d.stun_until > 2000.0, "se puede aturdir")
	m._cc(d, "root", 2000.0, 2000.0)
	check(d.root_until > 2000.0, "se puede enraizar")


func test_player_respawns_instantly_when_killed() -> void:
	var m := _yard()
	var me := _me(m)
	me.x = 5.0
	me.z = 0.0
	m._damage(me, 1.0e9, _dummy(m, "melee"), 3000.0, "strike")
	check(me.alive, "revive al instante")
	eq(me.hp, me.max_hp, "con la vida completa")
	near(me.z, 17.5, 3.5, "en el punto de partida")
	eq(m.phase, "fight", "no termina nada")
	eq(m.score.red + m.score.blue, 0, "no suma al marcador")


func test_no_dampening_in_practice() -> void:
	var m := _yard("priest")
	var me := _me(m)
	var ally := _dummy(m, "ally")
	ally.hp = 100.0
	var snap := m.snapshot_for(me, 900_000.0)
	eq(snap.damp, 0.0, "el snapshot no informa amortiguación")
	m._heal(ally, 200.0, me, 900_000.0)
	near(ally.hp, 300.0, 0.01, "la curación no se reduce con el tiempo")


func test_patrol_dummy_walks_a_line_and_the_others_stay_put() -> void:
	var m := _yard()
	var p := _dummy(m, "patrol")
	var z0 := p.z
	var minx := p.x
	var maxx := p.x
	var held := {}
	for u in m.units:
		if u.dummy in ["melee", "mid", "far", "caster", "cover"]:
			held[u.id] = Vector2(u.x, u.z)
	var now := 1000.0
	for i in 60 * 14:
		now += 1000.0 / 60.0
		m.tick(now)
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
	check(maxx - minx > 8.0, "patrulla: recorre al menos 8 m (%.1f)" % (maxx - minx))
	near(p.z, z0, 0.3, "siempre sobre su línea")
	for u in m.units:
		if held.has(u.id):
			check(Vector2(u.x, u.z).distance_to(held[u.id]) < 0.6, "fijo: " + u.dummy)


func test_caster_dummy_casts_long_spells_and_can_be_interrupted() -> void:
	var m := _yard("warrior")
	var c := _dummy(m, "caster")
	var now := 1000.0
	var cast_seen := 0.0
	for i in 60 * 6:
		now += 1000.0 / 60.0
		m.tick(now)
		if not c.cast.is_empty():
			cast_seen = maxf(cast_seen, c.cast.ends_at - c.cast.start_at)
	check(cast_seen >= 2400.0, "lanza hechizos largos (%.0f ms)" % cast_seen)
	var me := _me(m)
	var hp := me.hp
	# wait for the next cast, then interrupt it
	for i in 60 * 10:
		now += 1000.0 / 60.0
		m.tick(now)
		if not c.cast.is_empty():
			break
	check(not c.cast.is_empty(), "empieza otro lanzamiento")
	m._interrupt(c, now)
	check(c.cast.is_empty(), "la interrupción corta el hechizo")
	var relaunched_early := false
	for i in int(60.0 * 3.5):
		now += 1000.0 / 60.0
		m.tick(now)
		if not c.cast.is_empty():
			relaunched_early = true
	check(not relaunched_early, "tras interrumpirlo no vuelve a lanzar durante unos 4 s")
	eq(me.hp, hp, "el muñeco nunca le hace daño al jugador")


func test_ally_dummy_is_missing_health_and_can_be_healed() -> void:
	var m := _yard("priest")
	var me := _me(m)
	var ally := _dummy(m, "ally")
	check(ally.hp < ally.max_hp * 0.5, "empieza herido")
	var now := 1000.0
	for i in 60 * 20:
		now += 1000.0 / 60.0
		m.tick(now)
	check(ally.hp < ally.max_hp * 0.5, "sigue necesitando curación (%.0f%%)" % (ally.hp / ally.max_hp * 100.0))
	var before := ally.hp
	m._heal(ally, 1000.0, me, now)
	check(ally.hp > before, "se cura")


# ---------------------------------------------------------------- meter wired into the match

func test_meter_records_the_players_damage_casts_crits_and_heals() -> void:
	var m := _yard()
	var me := _me(m)
	var d := _dummy(m, "melee")
	var now := 2000.0
	m.C.CRIT_CHANCE = 1.0
	check(m.cast_ability(me, 0, d.x, d.z, now, d.id), "lanza bola de fuego")
	for i in 60 * 3:
		now += 1000.0 / 60.0
		m.tick(now)
	var s: Dictionary = m.meter_for(me).snapshot(now)
	check(s.total > 0, "el medidor suma daño (%d)" % s.total)
	var row = s.rows.filter(func(r): return r.id == "fireball")
	check(not row.is_empty(), "fila de bola de fuego")
	if not row.is_empty():
		eq(row[0].casts, 1, "un lanzamiento")
		check(row[0].crits >= 1, "cuenta el crítico")
	var snap := m.snapshot_for(me, now)
	check(snap.you.has("meter"), "el snapshot lleva el medidor")
	check(snap.you.meter.total == s.total, "el snapshot coincide")
	var pm := _yard("priest")
	var pme := _me(pm)
	var ally := _dummy(pm, "ally")
	pm._execute(pme, 1, ally.x, ally.z, ally.id, 2000.0)
	check(pm.meter_for(pme).snapshot(2000.0).heal > 0, "cuenta la curación hecha")


func test_enemy_dummies_attacks_are_not_counted_as_the_players() -> void:
	var m := _yard()
	var me := _me(m)
	m._damage(me, 10.0, _dummy(m, "melee"), 2000.0, "strike")
	eq(m.meter_for(me).snapshot(2000.0).total, 0, "sólo cuenta lo que hacés vos")
	var ally := _dummy(m, "ally")
	m._damage(ally, 10.0, me, 2000.0, "fireball")
	eq(m.meter_for(me).snapshot(2000.0).total, 0, "dañar a un aliado no cuenta")


# ---------------------------------------------------------------- practice commands

func test_command_reset_clears_meter_dummies_and_cooldowns() -> void:
	var m := _yard()
	var me := _me(m)
	var d := _dummy(m, "mid")
	m._damage(d, 500.0, me, 2000.0, "fireball")
	me.cds[1] = 99999.0
	d.hp = 123.0
	m.cast_ability(me, 0, d.x, d.z, 2500.0, d.id)
	check(not m.projs.is_empty(), "hay un proyectil en vuelo")
	m.practice_command(me, "reset", true, 3000.0)
	check(m.projs.is_empty(), "reiniciar borra los proyectiles en vuelo")
	eq(m.meter_for(me).snapshot(3000.0).total, 0, "medidor en cero")
	eq(d.hp, d.max_hp, "muñecos curados")
	eq(me.cds[1], 0.0, "cooldowns listos")
	check(_dummy(m, "ally").hp < _dummy(m, "ally").max_hp * 0.5, "el aliado vuelve a estar herido")


func test_command_no_cooldowns_mode_and_ultimate_ready() -> void:
	var m := _yard()
	var me := _me(m)
	var d := _dummy(m, "melee")
	m.practice_command(me, "nocd", true, 2000.0)
	var now := 2000.0
	check(m.cast_ability(me, 1, d.x, d.z, now, d.id), "primer pyro")
	for i in 60 * 3:
		now += 1000.0 / 60.0
		m.tick(now)
	check(m.cast_ability(me, 1, d.x, d.z, now, d.id), "sin cooldown: pyro otra vez enseguida")
	m.practice_command(me, "nocd", false, now)
	for i in 60 * 3:
		now += 1000.0 / 60.0
		m.tick(now)
	me.cds[1] = now + 5000.0
	check(not m.cast_ability(me, 1, d.x, d.z, now, d.id), "con el modo apagado vuelve el cooldown")
	me.ult = 0.0
	m.practice_command(me, "ult", true, now)
	eq(me.ult, 100.0, "definitiva lista")


func test_commands_are_ignored_outside_practice() -> void:
	var m := ArenaMatch.new(2, [{"name": "A", "cls": "mage", "team": "red", "peer": 1}, {"name": "B", "cls": "mage", "team": "blue", "peer": 0}], 0, "normal", "bridge")
	var me := m.unit_for_peer(1)
	me.ult = 0.0
	m.practice_command(me, "ult", true, 1000.0)
	eq(me.ult, 0.0, "no hace nada fuera de la arena de práctica")
	check(not m.practice, "una partida normal no es práctica")


func test_wire_cleans_practice_commands() -> void:
	eq(Wire.clean_practice({"t": "practice", "cmd": "reset", "on": true}).cmd, "reset", "comando válido")
	check(Wire.clean_practice({"t": "practice", "cmd": "hack"}).is_empty(), "comando desconocido")
	check(Wire.clean_practice({"t": "practice", "cmd": 7}).is_empty(), "tipo incorrecto")


func test_server_runs_a_practice_match_and_applies_commands() -> void:
	var server := GameServer.new({"practice": true, "map": GameMap.PRACTICE_ID})
	var pair := LoopbackTransport.pair()
	server.attach(pair[0], true)
	var client := GameClient.new()
	client.attach(pair[1], {"name": "Pro", "cls": "mage", "pref": "red"})
	for i in 5:
		server.process(50)
		client.poll(50)
	client.send_start()
	for i in 12:
		server.process(50)
		client.poll(50)
	check(server.state == "match" and server.game != null and server.game.practice, "arranca la práctica sin lobby de bots")
	check(client.roster.any(func(r): return r.get("dummy", "") == "caster"), "el roster informa los muñecos")
	var me := server.game.unit_for_peer(client.peer_id)
	me.ult = 0.0
	client.send_practice("ult", true)
	for i in 4:
		server.process(50)
		client.poll(50)
	eq(me.ult, 100.0, "el servidor aplicó el comando")
	client.close()
	server.shutdown()


func test_god_mode_makes_humans_untouchable_for_playtests() -> void:
	var m := ArenaMatch.new(2, [{"name": "A", "cls": "mage", "team": "red", "peer": 1}, {"name": "B", "cls": "rogue", "team": "blue", "peer": 0}], 0, "normal", "test")
	m.phase = "fight"
	m.god = true
	var me := m.unit_for_peer(1)
	var bot := m.unit_by_id(2)
	m._damage(me, 9999.0, bot, 1000.0, "stab")
	eq(me.hp, me.max_hp, "sin daño")
	m._cc(me, "stun", 3000.0, 1000.0)
	eq(me.stun_until, 0.0, "sin control")
	m._damage(bot, 50.0, me, 1000.0, "fireball")
	check(bot.hp < bot.max_hp, "los bots sí reciben daño")
