extends TestBase
## Aprendiz (young duelist): wand sparks, stunning bolt, disarm, ward, broom dash, confusion and the guardian ultimate.

func _match() -> ArenaMatch:
	var m := ArenaMatch.new(2, [
		{"name": "Z", "cls": "wizard", "team": "red", "peer": 1},
		{"name": "A", "cls": "warrior", "team": "red", "peer": 4},
		{"name": "R", "cls": "rogue", "team": "blue", "peer": 2},
		{"name": "M", "cls": "mage", "team": "blue", "peer": 3}], 0, "hard", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	var z: ArenaUnit = m.units[0]
	z.x = 6
	z.z = 0
	z.rot = 0.0
	m.units[1].x = 4
	m.units[1].z = -2
	m.units[2].x = 6  # off the test map's bushes
	m.units[2].z = 3
	m.units[3].x = 10
	m.units[3].z = 10
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.block_front = 0.0
	m.block_rear = 0.0
	return m


func _slot(id: String) -> int:
	return GameData.abilities("wizard").map(func(a): return a.id).find(id)


func _fly(m: ArenaMatch, from: float, ms: float) -> void:
	for i in int(ms / (1000.0 / 60.0)):
		m._step_projectiles(from + i * (1000.0 / 60.0))


func test_wizard_is_complete() -> void:
	check(GameData.classes.has("wizard"), "Aprendiz registrado")
	var kit := GameData.kit("wizard")
	eq(kit.abilities.size(), 7, "siete habilidades")
	check(ResourceLoader.exists("res://assets/icons/%s.svg" % kit.icon), "icono de clase")
	for a in kit.abilities:
		check(SpellKinds.TABLE.has(a.id), "objetivo explícito: " + a.id)
		check(SpellSchools.explicit(a.id), "escuela: " + a.id)
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "icono: " + a.id)
		check(MatchView.CAST_SOUND.has(a.id), "sonido: " + a.id)
	check(CharacterRig.available("wizard"), "modelo disponible")
	check(BotBrain.PREF_RANGE.has("wizard"), "los bots saben a qué distancia jugarlo")


func test_stunning_bolt_and_disarm_land_their_effects() -> void:
	var m := _match()
	var z: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[3]
	m._spawn_proj(z, GameData.ability("wizard", _slot("stunbolt")), Vector2(t.x - z.x, t.z - z.z).normalized(), t)
	_fly(m, 1000, 600)
	check(t.stun_until > 2000, "el rayo aturde")
	t.stun_until = 0.0
	t.cast = {"slot": 1, "start_at": 2000, "ends_at": 4000, "ax": 0, "az": 0, "target_id": -1, "lock": -1, "pushes": 0}
	m._spawn_proj(z, GameData.ability("wizard", _slot("disarm")), Vector2(t.x - z.x, t.z - z.z).normalized(), t)
	_fly(m, 2100, 600)
	check(t.cast.is_empty(), "el desarme interrumpe")
	check(t.silence_until > 3500, "y silencia")


func test_confusion_cast_keeps_its_target() -> void:
	var m := _match()
	var z: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[3]
	check(m.cast_ability(z, _slot("confuse"), t.x, t.z, 1000, t.id), "empieza a lanzar")
	for i in 90:
		m.tick(1000 + i * (1000.0 / 60.0))
	eq(t.incap_kind, "disorient", "queda desorientado")


func test_broom_ward_and_guardian() -> void:
	var m := _match()
	var z: ArenaUnit = m.units[0]
	var ally: ArenaUnit = m.units[1]
	var rogue: ArenaUnit = m.units[2]
	m._execute(z, _slot("broom"), z.x, z.z + 5, -1, 1000)
	check(z.dash_left > 0.0 and z.dash_vz > 0.0, "sale volando hacia adelante")
	check(z.haste_until >= 3000, "y corre más rápido")
	z.dash_left = 0.0
	m._execute(z, _slot("wardshield"), z.x, z.z, -1, 1000)
	eq(z.absorb, 75.0, "el escudo absorbe 75")
	ally.hp = 100.0
	z.ult = 100.0
	m._execute(z, _slot("guardian"), z.x, z.z, -1, 2000)
	check(rogue.fear_until > 3000, "el enemigo cercano huye")
	near(ally.hp, 145.0, 0.01, "el aliado se cura 45")


func test_wizard_bot_duels() -> void:
	seed(4)
	var m := _match()
	var z: ArenaUnit = m.units[0]
	z.brain = BotBrain.new("hard")
	m.units[2].alive = false
	var t: ArenaUnit = m.units[3]
	t.max_hp = 100000
	t.hp = 100000
	var seen := {}
	for i in 2400:
		var now := 100 + i * (1000.0 / 60.0)
		if i % 300 == 0:
			t.cast = {"slot": 1, "start_at": now - 1500, "ends_at": now + 1500, "ax": z.x, "az": z.z, "target_id": z.id, "lock": -1, "pushes": 0}
		m.tick(now)
		for f in m.fx:
			if f.k == "cast" and f.id == z.id: seen[f.ability] = true
		m.fx.clear()
	for id in ["spark", "stunbolt", "disarm"]:
		check(seen.has(id), "el bot usa " + id + " (" + str(seen.keys()) + ")")
