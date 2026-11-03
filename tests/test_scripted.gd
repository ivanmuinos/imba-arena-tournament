extends TestBase
## Scripted matches (S4): per-unit diff / skill / hp_mult / dmg_mult. Entries without those fields behave as before.

const STEP := 1000.0 / 60.0


func _match(entries: Array, diff := "normal") -> ArenaMatch:
	return ArenaMatch.new(1, entries, 0.0, diff, "bridge")


func _fight(m: ArenaMatch) -> void:
	var now := 0.0
	while m.phase != "fight" and now < 30000.0:
		now += STEP
		m.tick(now)
	m.block_front = 0.0
	m.block_rear = 0.0
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0  # deterministic damage


func test_unscripted_entries_behave_as_before() -> void:
	var m := _match([{"name": "A", "cls": "mage", "team": "red", "peer": 1}, {"name": "B", "cls": "warrior", "team": "blue"}], "hard")
	var b: ArenaUnit = m.units[1]
	eq(b.max_hp, float(GameData.kit("warrior").hp), "vida de la clase")
	eq(b.dmg_mult, 1.0, "daño sin cambios")
	eq(b.brain.diff, "hard", "dificultad de la partida")
	check(b.brain.skill >= 0.75 and b.brain.skill <= 0.95, "skill dentro del rango hard")
	var r: Dictionary = m.roster()[1]
	check(not r.has("hp"), "el roster no lleva vida si no hay hp_mult")


func test_per_unit_diff_and_skill_override_the_match_defaults() -> void:
	var m := _match([{"name": "A", "cls": "mage", "team": "red", "peer": 1}, {"name": "B", "cls": "warrior", "team": "blue", "diff": "easy", "skill": 0.42}])
	var b: ArenaUnit = m.units[1]
	eq(b.brain.diff, "easy", "dificultad por unidad")
	eq(b.brain.skill, 0.42, "skill fijo")
	var e := _match([{"name": "A", "cls": "mage", "team": "red", "peer": 1}, {"name": "B", "cls": "warrior", "team": "blue", "diff": "easy"}], "hard")
	check(e.units[1].brain.skill <= 0.3, "solo diff: skill dentro del rango easy")
	m.leave(m.units[0])
	eq(m.units[0].brain.diff, "normal", "el bot sustituto usa la dificultad de la partida")
	m.leave(b)
	eq(b.brain.skill, 0.42, "un bot que vuelve a tomar el control conserva su skill")


func test_hp_mult_scales_max_hp_and_travels_in_the_roster() -> void:
	var m := _match([{"name": "A", "cls": "mage", "team": "red", "peer": 1}, {"name": "B", "cls": "warrior", "team": "blue", "hp_mult": 1.2}])
	var base := float(GameData.kit("warrior").hp)
	near(m.units[1].max_hp, base * 1.2, 0.01, "vida +20%")
	near(m.units[1].hp, base * 1.2, 0.01, "arranca llena")
	var r: Dictionary = m.roster()[1]
	near(GameData.entry_max_hp(r), base * 1.2, 0.01, "el HUD ve la vida escalada")
	check(not r.has("dummy"), "no es un muñeco")
	var a: Dictionary = m.roster()[0]
	eq(GameData.entry_max_hp(a), float(GameData.kit("mage", m.units[0].spec_id).hp), "el resto igual")


func test_dmg_mult_scales_damage_dealt_not_received() -> void:
	var m := _match([{"name": "A", "cls": "mage", "team": "red", "peer": 1, "dmg_mult": 1.5}, {"name": "B", "cls": "warrior", "team": "blue", "peer": 2}])
	_fight(m)
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	var hp := b.hp
	m._damage(b, 100.0, a, 20000.0, "fireball")
	near(hp - b.hp, 150.0, 0.01, "pega 50% más")
	var a_hp := a.hp
	m._damage(a, 100.0, b, 20000.0, "stab")
	near(a_hp - a.hp, 100.0 * (1.0 - float(a.spec().get("armor", 0.0))), 0.01, "recibir daño no cambia")


func test_dmg_mult_does_not_touch_heals() -> void:
	var m := _match([{"name": "A", "cls": "priest", "team": "red", "peer": 1, "dmg_mult": 2.0}, {"name": "B", "cls": "warrior", "team": "blue", "peer": 2}])
	_fight(m)
	var a: ArenaUnit = m.units[0]
	a.hp = 100.0
	m._heal(a, 50.0, a, 20000.0)
	near(a.hp, 150.0, 0.01, "la cura no escala")


func test_matchconfig_scripted_entries_are_sanitized_and_humans_slot_in() -> void:
	var script := [
		{"human": true, "team": "red", "hp_mult": 99, "dmg_mult": -3},
		{"name": "Rival con un nombre larguísimo", "cls": "druid", "team": "blue", "diff": "nope", "skill": 7, "hp_mult": 1.2, "dmg_mult": 1.15}]
	var out := MatchConfig.scripted_entries(script, [{"peer": 7, "name": "Ana", "cls": "rogue", "spec": "", "pref": "any"}])
	eq(out.size(), 2, "dos unidades")
	eq(out[0].peer, 7, "el humano ocupa su lugar")
	eq(out[0].name, "Ana", "nombre del humano")
	eq(out[0].cls, "rogue", "clase del humano")
	check(out[0].hp_mult <= 3.0 and out[0].hp_mult > 0.0, "hp_mult acotado")
	check(out[0].dmg_mult > 0.0, "dmg_mult positivo")
	eq(out[1].peer, 0, "el rival es un bot")
	check(out[1].name.length() <= 16, "nombre acotado")
	check(GameData.playable(out[1].cls), "clase no jugable pasa a una jugable")
	eq(out[1].diff, "normal", "diff inválido: normal")
	eq(out[1].skill, 1.0, "skill acotado a 1")
	near(out[1].hp_mult, 1.2, 0.0001, "hp_mult válido se conserva")


func test_server_scripted_cfg_builds_the_scripted_match_over_the_wire() -> void:
	var script := [
		{"human": true, "team": "red"},
		{"name": "Jefe", "cls": "warrior", "team": "blue", "diff": "hard", "skill": 0.95, "hp_mult": 1.2, "dmg_mult": 1.15}]
	var server := GameServer.new({"mode": 1, "map": "bridge", "scripted": script})
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var client := GameClient.new()
	client.attach(link[1], {"name": "Ana", "cls": "mage", "pref": "red"})
	for i in 4:
		server.process(16.0)
		client.poll(16.0)
	check(server.start_match(true), "arranca")
	for i in 4:
		server.process(16.0)
		client.poll(16.0)
	eq(server.game.units.size(), 2, "1v1 guionado")
	var boss: ArenaUnit = server.game.units[1]
	eq(boss.name, "Jefe", "el rival es el del guion")
	near(boss.dmg_mult, 1.15, 0.0001, "daño del jefe")
	var r: Dictionary = client.roster.filter(func(e): return e.name == "Jefe")[0]
	near(GameData.entry_max_hp(r), float(GameData.kit("warrior").hp) * 1.2, 0.01, "el cliente recibe la vida escalada")
	eq(GameServer.PROTO, 6, "PROTO 6 (los talentos viajan en las entradas)")
