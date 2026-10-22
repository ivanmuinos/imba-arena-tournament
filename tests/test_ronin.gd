extends TestBase
## Ronin: steel tempest (third cast throws a tornado), wind wall, sweeping dash, wind shield, up-cut and last breath.

func _match() -> ArenaMatch:
	var m := ArenaMatch.new(2, [
		{"name": "R", "cls": "ronin", "team": "red", "peer": 1},
		{"name": "M", "cls": "mage", "team": "blue", "peer": 2},
		{"name": "H", "cls": "hunter", "team": "blue", "peer": 3}], 0, "hard", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	var r: ArenaUnit = m.units[0]
	r.x = 6
	r.z = 0
	r.rot = 0.0
	m.units[1].x = 6  # off the test map's bushes
	m.units[1].z = 4
	m.units[2].x = 14
	m.units[2].z = 4
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.block_front = 0.0
	m.block_rear = 0.0
	for u in m.units:
		u.crit_until = 0.0
	return m


## The ronin crits on its own (class crit chance): a hit lands for its value or its critical value.
func _hit(dealt: float, base: float, m: ArenaMatch) -> bool:
	return is_equal_approx(dealt, base) or is_equal_approx(dealt, base * float(m.C.CRIT_MULT))


func _slot(id: String) -> int:
	return GameData.abilities("ronin").map(func(a): return a.id).find(id)


func test_ronin_is_complete() -> void:
	check(GameData.classes.has("ronin"), "Ronin registrado")
	var kit := GameData.kit("ronin")
	eq(kit.abilities.size(), 7, "siete habilidades")
	check(ResourceLoader.exists("res://assets/icons/%s.svg" % kit.icon), "icono de clase")
	for a in kit.abilities:
		check(SpellKinds.TABLE.has(a.id), "objetivo explícito: " + a.id)
		check(SpellSchools.explicit(a.id), "escuela: " + a.id)
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "icono: " + a.id)
		check(MatchView.CAST_SOUND.has(a.id), "sonido: " + a.id)
	check(CharacterRig.available("ronin"), "modelo disponible")
	check(BotBrain.PREF_RANGE.has("ronin"), "los bots saben a qué distancia jugarlo")


func test_third_tempest_in_a_row_throws_a_tornado_that_knocks_up() -> void:
	var m := _match()
	var r: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[1]
	t.max_hp = 10000
	t.hp = 10000
	var hp := t.hp
	m._execute(r, _slot("tempest"), t.x, t.z, t.id, 1000)
	check(_hit(hp - t.hp, 26.0, m), "estocada: 26 (o su crítico): %s" % (hp - t.hp))
	eq(m.projs.size(), 0, "la primera no tira tornado")
	m._execute(r, _slot("tempest"), t.x, t.z, t.id, 2000)
	eq(m.projs.size(), 0, "la segunda tampoco")
	m._execute(r, _slot("tempest"), t.x, t.z, t.id, 3000)
	eq(m.projs.size(), 1, "la tercera seguida lanza el tornado")
	for i in 60:
		m._step_projectiles(3000 + i * (1000.0 / 60.0))
	check(t.stun_until > 3500, "el tornado lo deja en el aire")
	m._execute(r, _slot("tempest"), t.x, t.z, t.id, 20000)
	eq(r.tempest_stacks, 1, "las cargas se pierden si pasan más de 6 s")


func test_wind_wall_eats_enemy_projectiles_but_not_its_own_team() -> void:
	var m := _match()
	var r: ArenaUnit = m.units[0]
	var mage: ArenaUnit = m.units[1]
	mage.z = 14.0
	m._execute(r, _slot("windwall"), r.x, r.z + 5.0, -1, 1000)  # wall 2.5 m in front (towards +z)
	eq(m.windwalls.size(), 1, "muro levantado")
	var hp := r.hp
	m._spawn_proj(mage, GameData.ability("mage", 0), Vector2(0, -1), r)
	for i in 60:
		m._step_projectiles(1100 + i * (1000.0 / 60.0))
	eq(r.hp, hp, "la bola de fuego se deshace en el muro")
	m._spawn_proj(mage, GameData.ability("mage", 0), Vector2(0, -1), r)
	for i in 60:
		m._step_projectiles(6000 + i * (1000.0 / 60.0))
	check(r.hp < hp, "a los 4 s el muro ya no está")


func test_sweep_dashes_through_and_last_breath_teleports_and_knocks_up() -> void:
	var m := _match()
	var r: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[1]
	var hp := t.hp
	m._execute(r, _slot("sweep"), t.x, t.z, t.id, 1000)
	check(_hit(hp - t.hp, 20.0, m), "corte de 20 (o su crítico): %s" % (hp - t.hp))
	check(r.dash_left > 0.0 and r.dash_vz > 0.0, "sale disparado hacia el objetivo")
	var far: ArenaUnit = m.units[2]
	far.z = 14.0
	hp = far.hp
	r.ult = 100.0
	m._execute(r, _slot("lastbreath"), far.x, far.z, far.id, 2000)
	check(Vector2(r.x - far.x, r.z - far.z).length() < 2.0, "aparece junto al objetivo")
	check(_hit(hp - far.hp, 90.0, m), "90 de daño (o su crítico): %s" % (hp - far.hp))
	check(far.stun_until > 3000, "lo deja en el aire")


func test_ronin_bot_closes_in_and_uses_its_kit() -> void:
	seed(3)
	var m := _match()
	var r: ArenaUnit = m.units[0]
	r.brain = BotBrain.new("hard")
	m.units[2].alive = false
	var t: ArenaUnit = m.units[1]
	t.z = 12.0
	t.max_hp = 100000
	t.hp = 100000
	var seen := {}
	for i in 2400:
		var now := 100 + i * (1000.0 / 60.0)
		if i % 400 == 0:
			r.ult = 100.0
			t.hp = 30000
		if i % 300 == 150:  # the target backs off: the ronin has to dash back in
			t.x = r.x
			t.z = r.z + 5.5 if r.z < 10.0 else r.z - 5.5
		m.tick(now)
		for f in m.fx:
			if f.k == "cast" and f.id == r.id: seen[f.ability] = true
		m.fx.clear()
	for id in ["slash", "tempest", "sweep", "lastbreath"]:
		check(seen.has(id), "el bot usa " + id + " (" + str(seen.keys()) + ")")
