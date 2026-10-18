extends TestBase

func _match() -> ArenaMatch:
	var m := ArenaMatch.new(2, [
		{"name": "W", "cls": "warlock", "team": "red", "peer": 1},
		{"name": "W2", "cls": "warlock", "team": "red", "peer": 2},
		{"name": "P", "cls": "priest", "team": "blue", "peer": 3}], 0, "hard", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	for i in m.units.size():
		m.units[i].x = 0
		m.units[i].z = i * 4
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	return m

func test_warlock_is_complete() -> void:
	check(GameData.classes.has("warlock"), "Brujo registrado")
	if not GameData.classes.has("warlock"): return
	var kit := GameData.kit("warlock")
	eq(kit.abilities.size(), 7, "siete habilidades")
	for a in kit.abilities:
		check(SpellKinds.TABLE.has(a.id), "objetivo explícito: " + a.id)
		check(SpellSchools.explicit(a.id), "escuela: " + a.id)
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "icono: " + a.id)
	check(CharacterRig.available("warlock"), "modelo disponible")

func test_curses_refresh_without_delaying_ticks_and_keep_each_owner() -> void:
	if not GameData.classes.has("warlock"): return
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	var t: ArenaUnit = m.units[2]
	m._execute(a, 1, t.x, t.z, t.id, 100)
	m._execute(a, 1, t.x, t.z, t.id, 400)
	m._execute(b, 1, t.x, t.z, t.id, 100)
	m._execute(a, 2, t.x, t.z, t.id, 100)
	m._step_effects(t, 600)
	near(a.dmg, 6.0, 0.01, "dos maldiciones propias, sin duplicar al refrescar")
	near(b.dmg, 3.5, 0.01, "atribución independiente")
	var hp := t.hp
	m._step_effects(t, 20000)
	eq(t.hp, hp, "no hay daño después de expirar")
	m._execute(a, 1, t.x, t.z, t.id, 21000)
	m._execute(t, 5, t.x, t.z, t.id, 21001)
	m._step_effects(t, 21600)
	eq(t.hp, hp, "disipar elimina maldiciones")
	m._reset_round(22000)
	m.phase = "fight"
	m._step_effects(t, 23000)
	eq(t.hp, t.max_hp, "la nueva ronda limpia efectos")

func test_drain_heals_only_lost_health_after_absorbs_and_dampening() -> void:
	if not GameData.classes.has("warlock"): return
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	a.hp = 200
	t.absorb = 100
	t.absorb_until = 10000
	m._execute(a, 5, t.x, t.z, t.id, 100)
	eq(a.hp, 200.0, "absorción completa no cura")
	t.absorb = 10
	m._execute(a, 5, t.x, t.z, t.id, 200)
	near(a.hp, 222.0, 0.01, "cura daño real (32 menos 10)")
	t.hp = 5
	# Keep the fight alive so the final siphon can heal after a kill.
	m.units[1].team = "blue"
	m._execute(a, 5, t.x, t.z, t.id, 300)
	near(a.hp, 227.0, 0.01, "sin curación por overkill")
	t.alive = true
	t.hp = 100
	m._execute(a, 5, t.x, t.z, t.id, 60000)
	near(a.hp, 246.2, 0.01, "amortiguación reduce la sanación")

func test_fear_forces_fleeing_blocks_casts_and_restores_input() -> void:
	if not GameData.classes.has("warlock"): return
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	t.input = Vector2.ZERO
	m._execute(a, 3, t.x, t.z, t.id, 100)
	var z := t.z
	m.tick(200)
	check(t.z > z, "huye realmente, no stun")
	check(not m.cast_ability(t, 0, a.x, a.z, 200, a.id), "servidor bloquea hechizos")
	eq(t.input, Vector2.ZERO, "miedo no sobrescribe entrada humana")
	t.fear_until = 250
	z = t.z
	m.tick(300)
	near(t.z, z, 0.01, "al expirar deja de huir")

func test_warlock_network_selection_and_snapshot() -> void:
	if not GameData.classes.has("warlock"): return
	var server := GameServer.new({"map": "test"})
	var pair := LoopbackTransport.pair()
	server.attach(pair[0], true)
	var client := GameClient.new()
	client.attach(pair[1], {"name": "Brujo", "cls": "warlock", "pref": "red"})
	for i in 5:
		server.process(50)
		client.poll(50)
	eq(server.players[client.peer_id].cls, "warlock", "hello acepta clase")
	client.send_start()
	for i in 12:
		server.process(50)
		client.poll(50)
	check(client.roster.any(func(r): return r.cls == "warlock"), "roster completo")
	var game := server.game
	game.phase = "fight"
	game.fight_start = server.sim_now
	game.map.apply_state(true, 0)
	var me := game.unit_for_peer(client.peer_id)
	var enemy: ArenaUnit = null
	for u in game.units:
		u.brain = null
		u.input = Vector2.ZERO
		u.x = 0
		u.z = 0 if u == me else 8 + u.id
		if u.team != me.team: enemy = u
	client.send_cast({"slot": 1, "ax": enemy.x, "az": enemy.z, "target": enemy.id})
	for i in 5:
		server.process(50)
		client.poll(50)
	check(not enemy.curses.is_empty(), "comando de red aplica Corrupción autoritativa")
	client.close()
	server.shutdown()
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	m._execute(a, 0, t.x, t.z, -1, 100, t.id)
	m._execute(a, 1, t.x, t.z, t.id, 100)
	var back := SnapshotCodec.unpack(SnapshotCodec.pack(m.snapshot_for(a, 200)))
	eq(back.projs[0].kind, "shadowbolt", "proyectil conserva tipo")
	check(back.units.any(func(u): return u.id == t.id and u.cc.has("corruption")), "maldición viaja al HUD")

func test_pact_has_its_own_absorb_and_never_creates_health() -> void:
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	a.hp = 200
	a.absorb = 42
	a.absorb_until = 10000
	m._execute(a, 4, 0, 0, -1, 100)
	eq(a.hp, 170.0, "precio de vida")
	m._damage(a, 100, t, 200)
	eq(a.hp, 170.0, "pacto y escudo aliado coexisten")
	m._damage(a, 30, t, 300)
	near(a.hp, 162.0, 0.01, "absorción total 122, no más")
	a.hp = 0.5
	m._execute(a, 4, 0, 0, -1, 400)
	eq(a.hp, 0.5, "no crea vida bajo 1 HP")

func test_casts_are_interruptible_and_recheck_range_and_sight() -> void:
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	check(not m.start_auto(a, t.id), "caster sin autoataque")
	check(m.cast_ability(a, 5, t.x, t.z, 100, t.id), "empieza drenaje")
	a.input = Vector2(1, 0)
	m.tick(200)
	check(a.cast.is_empty(), "mover cancela")
	eq(t.hp, t.max_hp, "sin daño parcial")
	a.input = Vector2.ZERO
	m.cast_ability(a, 5, t.x, t.z, 300, t.id)
	t.z = 35
	m.tick(1900)
	eq(t.hp, t.max_hp, "fuera de alcance al finalizar")
	t.z = 8
	a.cds[5] = 0
	m.cast_ability(a, 5, t.x, t.z, 2000, t.id)
	m._cc(a, "silence", 2000, 2100)
	m.tick(2200)
	check(a.cast.is_empty(), "silencio cancela")

func test_fear_damage_break_immunity_and_dr() -> void:
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	m._execute(a, 3, t.x, t.z, t.id, 100)
	m._damage(t, 41, a, 200)
	check(t.fear_until <= 200, "daño rompe miedo")
	m._execute(a, 3, t.x, t.z, t.id, 300)
	near(t.fear_until, 1800, 0.01, "segundo miedo dura la mitad")
	t.fear_until = 0
	t.shield_until = 5000
	m._execute(a, 3, t.x, t.z, t.id, 400)
	eq(t.fear_until, 0.0, "inmunidad bloquea miedo")

func test_bot_uses_curses_bolt_and_drain() -> void:
	seed(714)
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	a.brain = BotBrain.new("hard")
	a.hp = 240
	t.max_hp = 10000
	t.hp = 10000
	a.ult = 0
	var seen := {}
	for i in 1500:
		m.tick(100 + i * (1000.0 / 60.0))
		for f in m.fx:
			if f.k == "cast" and f.id == a.id: seen[f.ability] = true
		m.fx.clear()
	for id in ["corruption", "agony", "shadowbolt", "drainlife", "darkpact"]:
		check(seen.has(id), "bot usa " + id + " (" + str(seen.keys()) + ")")

func test_curses_keep_kill_credit_after_owner_death_and_do_not_replace_burn() -> void:
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	var t: ArenaUnit = m.units[2]
	m._execute(a, 1, t.x, t.z, t.id, 100)
	t.burn_by = b
	t.burn_dps = 6
	t.burn_until = 3000
	t.burn_next = 600
	m._step_effects(t, 600)
	near(a.dmg, 3.5, 0.01, "maldición atribuida al brujo")
	near(b.dmg, 3, 0.01, "quemadura independiente")
	a.alive = false
	t.hp = 1
	m._step_effects(t, 1100)
	eq(a.kills, 1, "autor muerto conserva crédito")
	eq(b.kills, 0, "no roba atribución la quemadura")

func test_ultimate_consumes_charge_and_does_not_replace_other_curses() -> void:
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	a.ult = 0
	check(not m.cast_ability(a, 6, t.x, t.z, 100, t.id), "sin carga no lanza")
	m.cast_ability(a, 1, t.x, t.z, 100, t.id)
	a.ult = 100
	check(m.cast_ability(a, 6, t.x, t.z, 200, t.id), "definitiva lista")
	check(a.ult < 20, "consume carga (puede generar por golpe)")
	eq(t.curses.size(), 2, "coexiste con Corrupción")
	near(t.max_hp - t.hp, 25, 0.01, "golpe inicial")


# ---------------------------------------------------------------- review follow-ups (0.5.0)

func test_cast_target_travels_in_the_snapshot_for_the_drain_beam() -> void:
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	a.x = 0.0
	a.z = 0.0
	t.x = 0.0
	t.z = 8.0
	var now := 1000.0
	check(m.cast_ability(a, 5, t.x, t.z, now, t.id), "empieza a drenar")
	var snap := m.snapshot_for(a, now + 100.0)
	var mine: Dictionary = snap.units.filter(func(u): return u.id == a.id)[0]
	eq(mine.cast.tid, t.id, "el snapshot dice a quién drena")
	var back := SnapshotCodec.unpack(SnapshotCodec.pack(snap))
	var mine2: Dictionary = back.units.filter(func(u): return u.id == a.id)[0]
	eq(mine2.cast.tid, t.id, "y sobrevive al paquete")


func test_curse_effects_have_names_descriptions_and_icons() -> void:
	var list := Effects.debuffs_of({"corruption": 5000, "agony": 7000, "soulrot": 3000, "fear": 2000})
	eq(list.size(), 4, "cuatro efectos")
	for e in list:
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % e.icon), "%s: ícono" % e.key)
		check(str(e.get("desc", "")).length() > 20, "%s: descripción para el tooltip" % e.key)
	check(Effects.buffs_of({"darkpact": 4000}).size() == 1, "el pacto oscuro es un beneficio visible")
	check(Effects.buffs_of({"darkpact": 4000})[0].get("desc", "") != "", "con descripción")


func test_priest_bot_dispels_curses_off_an_ally() -> void:
	var m := ArenaMatch.new(2, [
		{"name": "W", "cls": "warrior", "team": "red", "peer": 1},
		{"name": "P", "cls": "priest", "team": "red", "peer": 0},
		{"name": "L", "cls": "warlock", "team": "blue", "peer": 2},
		{"name": "L2", "cls": "warlock", "team": "blue", "peer": 3}], 0, "hard", "test")
	var now := 1_000_000.0
	var t := 0.0
	while t < 20100.0:
		now += 16.67
		t += 16.67
		m.tick(now)
	for i in 4:
		m.units[i].x = float(i) * 3.0
		m.units[i].z = 0.0
	m.units[2].x = 150.0   # warlocks parked far away so only the curses matter
	m.units[3].x = 150.0
	var ally: ArenaUnit = m.units[0]
	var lock: ArenaUnit = m.units[2]
	for slot in [1, 2]:
		m._execute(lock, slot, ally.x, ally.z, ally.id, now)
	check(ally.curses.size() == 2, "el aliado está maldito (%d)" % ally.curses.size())
	var seen := false
	var tt := 0.0
	while tt < 3000.0:
		now += 16.67
		tt += 16.67
		m.tick(now)
		if ally.curses.is_empty():
			seen = true
			break
	check(seen, "el sacerdote bot disipó las maldiciones en menos de 3 s")


func test_warlock_bot_keeps_curses_on_several_enemies_and_fears_a_healer() -> void:
	var m := ArenaMatch.new(3, [
		{"name": "L", "cls": "warlock", "team": "red", "peer": 0},
		{"name": "A", "cls": "warrior", "team": "red", "peer": 1},
		{"name": "B", "cls": "mage", "team": "red", "peer": 2},
		{"name": "E1", "cls": "warrior", "team": "blue", "peer": 3},
		{"name": "E2", "cls": "priest", "team": "blue", "peer": 4},
		{"name": "E3", "cls": "hunter", "team": "blue", "peer": 5}], 0, "hard", "test")
	var now := 1_000_000.0
	var t := 0.0
	while t < 20100.0:
		now += 16.67
		t += 16.67
		m.tick(now)
	var lock: ArenaUnit = m.units[0]
	lock.x = 0.0
	lock.z = 0.0
	var foes := [m.units[3], m.units[4], m.units[5]]
	for i in 3:
		foes[i].x = -6.0 + 6.0 * i
		foes[i].z = 10.0
		foes[i].root_until = now + 1.0e9   # rooted dummies (no brain): the bot just has to apply its kit
	m.units[1].x = 40.0
	m.units[2].x = -40.0
	var cursed := {}
	var feared_priest := false
	var feared_any := ""
	var tt := 0.0
	while tt < 20000.0:
		now += 16.67
		tt += 16.67
		m.tick(now)
		for f in foes:
			if not f.curses.is_empty():
				cursed[f.id] = true
		for f in foes:
			if now < f.fear_until:
				feared_priest = feared_priest or f.cls == "priest"
				feared_any = f.cls
	check(cursed.size() >= 2, "maldijo a varios enemigos distintos (%d)" % cursed.size())
	check(feared_priest, "aterrorizó al sacerdote enemigo (aterrorizó a: %s)" % feared_any)


func test_periodic_damage_is_marked_so_clients_do_not_flash_on_ticks() -> void:
	var m := _match()
	var a: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	m._execute(a, 1, t.x, t.z, t.id, 100)
	m.fx.clear()
	m._step_effects(t, 700)
	var ticks: Array = m.fx.filter(func(f): return f.k == "hit")
	check(ticks.size() >= 1 and ticks.all(func(f): return f.dot), "los ticks de maldición llevan dot=true")
	m.fx.clear()
	m._execute(a, 6, t.x, t.z, t.id, 800)
	var opening: Array = m.fx.filter(func(f): return f.k == "hit" and f.ability == "soulrot")
	check(opening.size() == 1 and not opening[0].dot, "el golpe inicial no es un tick")
