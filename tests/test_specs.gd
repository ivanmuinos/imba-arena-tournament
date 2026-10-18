extends TestBase
## Class specializations (mage: Fuego / Escarcha): data, selection, entries, abilities, network.

const STEP := 1000.0 / 60.0
var now := 0.0


# ---------------------------------------------------------------- data

func test_spec_data_is_complete_and_icons_exist() -> void:
	GameData.ensure_loaded()
	var mage: Dictionary = GameData.classes.mage
	check(mage.has("specs") and mage.specs.has("fire") and mage.specs.has("frost"), "el mago tiene Fuego y Escarcha")
	eq(GameData.default_spec("mage"), "fire", "por defecto Fuego")
	eq(GameData.spec_ids("warrior"), [], "otras clases no tienen especialización (todavía)")
	for sid in GameData.spec_ids("mage"):
		var sp: Dictionary = mage.specs[sid]
		for k in ["name", "icon", "color", "role", "desc", "stats", "abilities"]:
			check(sp.has(k), "%s: campo %s" % [sid, k])
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % sp.icon), "%s: ícono de especialización" % sid)
		var kit := GameData.abilities("mage", sid)
		eq(kit.size(), int(GameData.C.SLOT_COUNT), "%s: 7 habilidades" % sid)
		for i in kit.size():
			var a: Dictionary = kit[i]
			for k in ["id", "name", "icon", "desc", "cd", "cast", "range"]:
				check(a.has(k), "%s/%d: campo %s" % [sid, i, k])
			check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "%s/%s: ícono existe" % [sid, a.id])
			check(SpellSchools.explicit(str(a.id)), "%s/%s: tiene escuela" % [sid, a.id])
			check(SpellKinds.TABLE.has(str(a.id)), "%s/%s: tiene tipo de objetivo" % [sid, a.id])
		check(kit[6].get("ult", false), "%s: la definitiva está en la ranura R" % sid)
		for stat in ["hp", "mobility", "damage", "control", "difficulty"]:
			var v := int(sp.stats[stat])
			check(v >= 1 and v <= 5, "%s: estadística %s" % [sid, stat])


func test_spec_resolution_falls_back_safely() -> void:
	eq(GameData.normalize_spec("mage", "frost"), "frost", "válida")
	eq(GameData.normalize_spec("mage", "veneno"), "fire", "inválida: la de por defecto")
	eq(GameData.normalize_spec("mage", ""), "fire", "vacía: la de por defecto")
	eq(GameData.normalize_spec("warrior", "fire"), "", "una clase sin especializaciones ignora la elección")
	eq(GameData.ability("mage", 0, "frost").id, "frostbolt", "ranura 1 de Escarcha")
	eq(GameData.ability("mage", 0, "fire").id, "fireball", "ranura 1 de Fuego")
	eq(GameData.ability("warrior", 0, "fire").id, "strike", "sin especialización se usa el kit base")
	eq(GameData.kit("mage", "frost").name, "Mago", "el kit conserva el nombre de la clase")
	eq(GameData.kit("mage", "frost").spec_name, "Escarcha", "y trae el nombre de la especialización")


# ---------------------------------------------------------------- entries / settings / wire

func test_match_config_normalizes_and_builds_entries_with_spec() -> void:
	var c := MatchConfig.normalize({"cls": "mage", "spec": "frost"})
	eq(c.spec, "frost", "se conserva")
	eq(MatchConfig.normalize({"cls": "mage", "spec": "zzz"}).spec, "fire", "inválida -> Fuego")
	eq(MatchConfig.normalize({"cls": "rogue", "spec": "fire"}).spec, "", "clase sin especialización")
	var humans := [{"peer": 1, "name": "Ana", "cls": "mage", "spec": "frost", "pref": "red"}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var entries := MatchConfig.build_entries(2, humans, rng)
	var me: Dictionary = entries.filter(func(e): return e.peer == 1)[0]
	eq(me.spec, "frost", "el humano mantiene su especialización")
	for e in entries:
		check(e.has("spec"), "toda entrada trae spec (%s)" % e.name)
		if e.cls == "mage":
			check(GameData.spec_ids("mage").has(e.spec), "un mago bot elige una especialización válida")


func test_settings_persist_and_validate_spec() -> void:
	var s := SettingsStore.new()
	eq(s.get_value("spec"), "fire", "por defecto")
	s.set_value("spec", "frost")
	eq(s.get_value("spec"), "frost", "se guarda")
	s.set_value("spec", "otra")
	eq(s.get_value("spec"), "fire", "inválida")
	s.set_value("spec", "frost")
	check(s.save("user://test_spec.cfg"), "guarda")
	var t := SettingsStore.new()
	check(t.load("user://test_spec.cfg"), "carga")
	eq(t.get_value("spec"), "frost", "vuelve")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_spec.cfg"))
	eq(t.to_cfg().spec, "frost", "va en la configuración de partida")


# ---------------------------------------------------------------- match mechanics

func _duel(a_spec: String, b_cls := "warrior", b_spec := "") -> ArenaMatch:
	now = 1_000_000.0
	var e := [{"name": "A", "cls": "mage", "spec": a_spec, "team": "red", "peer": 1}, {"name": "B", "cls": b_cls, "spec": b_spec, "team": "blue", "peer": 2}]
	var m := ArenaMatch.new(2, e, now, "normal", "test")
	_adv(m, 20100)
	m.units[0].x = 0.0
	m.units[0].z = 20.0
	m.units[0].rot = PI
	m.units[1].x = 0.0
	m.units[1].z = 8.0
	_adv(m, 30)
	return m


func _adv(m: ArenaMatch, ms: float) -> void:
	var t := 0.0
	while t < ms:
		now += STEP
		t += STEP
		m.tick(now)


func _face(m: ArenaMatch, a: ArenaUnit, b: ArenaUnit) -> void:
	a.rot = atan2(b.x - a.x, b.z - a.z)


func test_units_use_the_spec_kit_and_roster_and_snapshot_expose_it() -> void:
	var m := _duel("frost")
	eq(m.units[0].ability(0).id, "frostbolt", "la unidad usa el kit de Escarcha")
	eq(m.roster()[0].spec, "frost", "el roster trae la especialización")
	var snap := m.snapshot_for(m.units[0], now)
	eq(snap.you.cds.size(), 7, "recargas del kit")
	var f := _duel("fire")
	eq(f.units[0].ability(2).id, "dragonbreath", "Q de Fuego: Aliento de dragón")


func test_fireball_burns_the_target_over_time() -> void:
	var m := _duel("fire")
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	_face(m, a, b)
	var spec := a.ability(0)
	check(m.cast_ability(a, 0, b.x, b.z, now, b.id), "lanza la bola")
	_adv(m, 900)
	var after_hit := b.hp
	check(after_hit < b.max_hp - float(spec.dmg) + 1.0, "la bola pegó (%.0f)" % after_hit)
	check(now < b.burn_until, "queda ardiendo")
	var before := b.hp
	_adv(m, 2200)
	check(b.hp < before - 8.0, "la quemadura sigue dañando (%.1f -> %.1f)" % [before, b.hp])
	_adv(m, 3000)
	var settled := b.hp
	_adv(m, 1000)
	eq(b.hp, settled, "la quemadura termina")


func test_dragon_breath_disorients_in_a_cone_and_breaks_on_damage() -> void:
	var m := _duel("fire")
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	b.x = a.x
	b.z = a.z - 4.0
	_face(m, a, b)
	check(m.cast_ability(a, 2, b.x, b.z, now, b.id), "usa el aliento")
	check(now < b.incap_until and b.incap_kind == "disorient", "el enemigo del cono queda desorientado")
	_adv(m, 200)
	var other := _duel("fire")
	var oa: ArenaUnit = other.units[0]
	var ob: ArenaUnit = other.units[1]
	ob.x = oa.x + 6.0   # beside the mage: outside the cone
	ob.z = oa.z
	oa.rot = PI
	other.cast_ability(oa, 2, oa.x, oa.z - 5.0, now, -1)
	check(not (now < ob.incap_until), "fuera del cono no pasa nada")
	m.units[0].cds[0] = 0.0
	_face(m, a, b)
	m.cast_ability(a, 0, b.x, b.z, now, b.id)
	_adv(m, 400)
	check(not (now < b.incap_until), "el daño rompe la desorientación")


func test_frostbolt_slows_and_ice_lance_shatters_rooted_targets() -> void:
	var crit: float = GameData.C.CRIT_CHANCE
	GameData.C["CRIT_CHANCE"] = 0.0   # random crits would make the damage comparison flaky
	var m := _duel("frost")
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	_face(m, a, b)
	check(m.cast_ability(a, 0, b.x, b.z, now, b.id), "empieza la descarga")
	_adv(m, 1500 + 700)
	check(now < b.slow_until and absf(b.slow_pct - 0.4) < 0.01, "ralentiza 40%% (%.2f)" % b.slow_pct)
	# ice lance: normal vs frozen
	var lance := a.ability(1)
	b.slow_until = 0.0
	var hp0 := b.hp
	_face(m, a, b)
	check(m.cast_ability(a, 1, b.x, b.z, now, b.id), "lanza de hielo")
	_adv(m, 500)
	var normal := hp0 - b.hp
	check(normal > 0.0 and absf(normal - float(lance.dmg)) < 1.5, "daño normal (%.1f)" % normal)
	a.cds[1] = 0.0
	b.root_until = now + 3000.0   # rooted by a nova
	var hp1 := b.hp
	_face(m, a, b)
	m.cast_ability(a, 1, b.x, b.z, now, b.id)
	_adv(m, 500)
	var shattered := hp1 - b.hp
	GameData.C["CRIT_CHANCE"] = crit
	near(shattered, normal * float(lance.shatter), 2.0, "contra un objetivo enraizado pega x%s (%.1f vs %.1f)" % [str(lance.shatter), shattered, normal])


func test_blizzard_ticks_damage_and_heavily_slows_inside_and_expires() -> void:
	var m := _duel("frost")
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	a.ult = 100.0
	b.x = a.x
	b.z = a.z - 8.0
	_face(m, a, b)
	check(m.cast_ability(a, 6, b.x, b.z, now, -1), "lanza la ventisca")
	check(m.aoes.size() == 1, "hay un área persistente")
	var spec := a.ability(6)
	_adv(m, 600)
	var h1 := b.hp
	check(h1 < b.max_hp, "primeros golpes de la ventisca")
	check(now < b.slow_until and b.slow_pct >= 0.55, "ralentización fuerte (%.2f)" % b.slow_pct)
	_adv(m, 2000)
	var ticks := (b.max_hp - b.hp) / float(spec.dmg)
	check(ticks >= 3.5, "daño continuo en ticks (%.1f ticks)" % ticks)
	check(m.aoes.size() == 1, "sigue activa a los 2.6 s")
	b.x = a.x + 20.0   # leave the area
	_adv(m, 4000)
	check(m.aoes.is_empty(), "termina a los %s ms" % str(spec.durationMs))
	var out := b.hp
	_adv(m, 1000)
	eq(b.hp, out, "fuera del área no hay más daño")


func test_cast_spam_rules_still_hold_for_frostbolt() -> void:
	var m := _duel("frost")
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	_face(m, a, b)
	m.cast_ability(a, 0, b.x, b.z, now, b.id)
	var started: float = a.cast.start_at
	for i in 5:
		_adv(m, 100)
		check(not m.cast_ability(a, 0, b.x, b.z, now, b.id), "repetir la descarga no hace nada")
	eq(a.cast.start_at, started, "no se reinició")


func test_each_class_remembers_its_own_spec_in_settings() -> void:
	var s := SettingsStore.new()
	s.set_value("spec", "frost")
	s.set_value("cls", "rogue")
	eq(s.get_value("spec"), "", "el asesino no tiene especialización")
	s.set_value("cls", "mage")
	eq(s.get_value("spec"), "frost", "al volver al mago se recuerda Escarcha")
	check(s.save("user://test_spec2.cfg"), "guarda")
	var t := SettingsStore.new()
	t.load("user://test_spec2.cfg")
	eq(t.get_value("spec"), "frost", "persiste")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_spec2.cfg"))


# ---------------------------------------------------------------- bots

func test_mage_bots_cast_their_spec_abilities() -> void:
	for spec in ["fire", "frost"]:
		now = 1_000_000.0
		var e := [{"name": "M", "cls": "mage", "spec": spec, "team": "red", "peer": 0}, {"name": "W", "cls": "warrior", "spec": "", "team": "blue", "peer": 0}]
		var m := ArenaMatch.new(2, e, now, "hard", "test")
		var seen := {}
		var t := 0.0
		_adv(m, 20100)
		m.units[0].x = 0.0
		m.units[0].z = 16.0
		m.units[1].x = 0.0
		m.units[1].z = 0.0
		var ids := {}
		while t < 60000.0 and m.phase == "fight":
			_adv(m, 100)
			t += 100.0
			for f in m.fx:
				if f.k == "cast" and f.id == m.units[0].id:
					ids[f.ability] = true
			m.fx.clear()
		var expect: Array = ["fireball"] if spec == "fire" else ["frostbolt"]
		for id in expect:
			check(ids.has(id), "%s: el bot usa %s (usó %s)" % [spec, id, str(ids.keys())])
		var wrong: Array = ["frostbolt", "icelance", "blizzard"] if spec == "fire" else ["fireball", "pyro", "dragonbreath"]
		for id in wrong:
			check(not ids.has(id), "%s: el bot no usa %s del otro kit" % [spec, id])


func test_spec_survives_the_network_round_trip() -> void:
	var server := GameServer.new({"map": "test"})
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var client := GameClient.new()
	client.attach(link[1], {"name": "Ana", "cls": "mage", "spec": "frost", "pref": "red"})
	for i in 5:
		server.process(50.0)
		client.poll(50.0)
	eq(server.players[client.peer_id].spec, "frost", "el servidor recibió la especialización")
	check(client.lobby.get("members", []).any(func(mm): return mm.spec == "frost"), "el lobby la anuncia")
	client.send_set({"spec": "fire"})
	for i in 5:
		server.process(50.0)
		client.poll(50.0)
	eq(server.players[client.peer_id].spec, "fire", "se puede cambiar en la sala")
	client.send_set({"cls": "rogue", "spec": "fire"})
	for i in 5:
		server.process(50.0)
		client.poll(50.0)
	eq(server.players[client.peer_id].spec, "", "al cambiar a una clase sin especialización se limpia")
	client.send_set({"cls": "mage", "spec": "frost"})
	client.send_start()
	for i in 12:
		server.process(50.0)
		client.poll(50.0)
	check(client.in_match, "arrancó la partida")
	var mine: Dictionary = client.roster.filter(func(r): return r.id == client.unit_id)[0]
	eq(mine.spec, "frost", "el roster del cliente trae la especialización")
	var others := client.roster.filter(func(r): return r.cls == "mage" and r.id != client.unit_id)
	for r in others:
		check(GameData.spec_ids("mage").has(r.spec), "los magos bot traen una especialización válida")


func test_blizzard_and_cast_kinds_survive_the_snapshot_codec() -> void:
	var m := _duel("frost")
	var a: ArenaUnit = m.units[0]
	a.ult = 100.0
	m.cast_ability(a, 6, a.x, a.z - 8.0, now, -1)
	_adv(m, 100)
	var snap := m.snapshot_for(a, now)
	var packed := SnapshotCodec.pack(snap)
	check(SnapshotCodec.is_valid(packed), "el paquete es válido")
	var back := SnapshotCodec.unpack(packed)
	eq(back.aoes.size(), 1, "una zona")
	eq(back.aoes[0].kind, "blizzard", "conserva el tipo (ventisca)")
	check(back.aoes[0].left > 3000.0, "con su tiempo restante")
