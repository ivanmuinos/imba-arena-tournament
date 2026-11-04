extends TestBase
## Paladín (plate healer): crusader strike, Holy Light, Hammer of Justice, Blessing of Protection and Lay on Hands.

func _match() -> ArenaMatch:
	var m := ArenaMatch.new(2, [
		{"name": "P", "cls": "paladin", "team": "red", "peer": 1},
		{"name": "A", "cls": "warrior", "team": "red", "peer": 4},
		{"name": "R", "cls": "rogue", "team": "blue", "peer": 2},
		{"name": "M", "cls": "mage", "team": "blue", "peer": 3}], 0, "hard", "test")
	m.phase = "fight"
	m.map.apply_state(true, 0)
	var p: ArenaUnit = m.units[0]
	p.x = 6
	p.z = 0
	p.rot = 0.0
	m.units[1].x = 4
	m.units[1].z = -2
	m.units[2].x = 6
	m.units[2].z = 2.5
	m.units[3].x = 10
	m.units[3].z = 8
	m.C = m.C.duplicate()
	m.C.CRIT_CHANCE = 0.0
	m.block_front = 0.0
	m.block_rear = 0.0
	return m


func _slot(id: String) -> int:
	return GameData.abilities("paladin").map(func(a): return a.id).find(id)


func _fly(m: ArenaMatch, from: float, ms: float) -> void:
	for i in int(ms / (1000.0 / 60.0)):
		m._step_projectiles(from + i * (1000.0 / 60.0))


func test_paladin_is_complete() -> void:
	check(GameData.playable("paladin"), "Paladín jugable")
	var kit := GameData.kit("paladin")
	eq(kit.abilities.size(), int(GameData.C.SLOT_COUNT), "básico, 3 habilidades y definitiva")
	check(float(kit.get("armor", 0.0)) > 0.0, "pasiva: armadura de placas")
	check(ResourceLoader.exists("res://assets/icons/%s.svg" % kit.icon), "icono de clase")
	for a in kit.abilities + GameData.reserve("paladin"):
		check(SpellKinds.TABLE.has(a.id), "objetivo explícito: " + a.id)
		check(SpellSchools.explicit(a.id), "escuela: " + a.id)
		check(ResourceLoader.exists("res://assets/icons/%s.svg" % a.icon), "icono: " + a.id)
		check(MatchView.CAST_SOUND.has(a.id), "sonido: " + a.id)
	check(CharacterRig.available("paladin"), "modelo disponible")
	check(BotBrain.PREF_RANGE.has("paladin") and BotBrain.HEALERS.has("paladin"), "los bots lo juegan de sanador")
	check(Talents.rows("paladin").size() == Talents.ROWS, "tiene talentos")


func test_holy_light_heals_and_lay_on_hands_heals_big() -> void:
	var m := _match()
	var p: ArenaUnit = m.units[0]
	var ally: ArenaUnit = m.units[1]
	ally.hp = 100.0
	check(m.cast_ability(p, _slot("holylight"), ally.x, ally.z, 1000, ally.id), "empieza Luz sagrada")
	for i in 150:
		m.tick(1000 + i * (1000.0 / 60.0))
	near(ally.hp, 100.0 + float(GameData.ability("paladin", _slot("holylight")).heal), 1.0, "Luz sagrada cura")
	ally.hp = 50.0
	p.ult = 100.0
	check(m.cast_ability(p, _slot("layhands"), ally.x, ally.z, 4000, ally.id), "Imposición de manos")
	var big := float(GameData.ability("paladin", _slot("layhands")).heal)
	near(ally.hp, minf(50.0 + big, ally.max_hp), 1.0, "cura mucho de una (%.0f)" % ally.hp)


func test_hammer_stuns_and_blessing_blocks_all_damage() -> void:
	var m := _match()
	var p: ArenaUnit = m.units[0]
	var t: ArenaUnit = m.units[2]
	m._spawn_proj(p, GameData.ability("paladin", _slot("hammer")), Vector2(t.x - p.x, t.z - p.z).normalized(), t)
	_fly(m, 1000, 500)
	check(t.stun_until > 2500, "el martillo aturde")
	var ally: ArenaUnit = m.units[1]
	check(m.cast_ability(p, _slot("blessing"), ally.x, ally.z, 2000, ally.id), "Bendición de protección")
	var hp := ally.hp
	m._damage(ally, 200.0, t, 2100, "stab")
	eq(ally.hp, hp, "no recibe daño")
	var lasts := float(GameData.ability("paladin", _slot("blessing")).durationMs)
	m._damage(ally, 50.0, t, 2000 + lasts + 100, "stab")
	check(ally.hp < hp, "a los %d s se termina" % int(lasts / 1000))


func test_plate_armor_cuts_physical_damage() -> void:
	var m := _match()
	var p: ArenaUnit = m.units[0]
	var hp := p.hp
	m._damage(p, 100.0, m.units[2], 1000, "stab")
	near(hp - p.hp, 100.0 * (1.0 - float(GameData.kit("paladin").armor)), 0.5, "15% menos de daño físico")


func test_paladin_bot_heals_and_fights() -> void:
	seed(4)
	var m := _match()
	var p: ArenaUnit = m.units[0]
	p.brain = BotBrain.new("hard")
	var ally: ArenaUnit = m.units[1]
	var t: ArenaUnit = m.units[2]
	t.max_hp = 100000
	t.hp = 100000
	m.units[3].alive = false
	var seen := {}
	for i in 2400:
		var now := 100 + i * (1000.0 / 60.0)
		if i % 400 == 0:
			ally.hp = ally.max_hp * 0.4
		m.tick(now)
		for f in m.fx:
			if f.k == "cast" and f.id == p.id: seen[f.ability] = true
		m.fx.clear()
	for id in ["crusader", "holylight"]:
		check(seen.has(id), "el bot usa " + id + " (" + str(seen.keys()) + ")")
