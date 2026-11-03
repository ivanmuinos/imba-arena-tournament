extends TestBase
## Sacerdote bot: en duelo (sin aliados vivos) prioriza el daño; en equipo sigue curando como antes.

func _match(with_ally: bool, cls := "priest") -> ArenaMatch:
	var entries := [
		{"name": "P", "cls": cls, "team": "red", "peer": 1},
		{"name": "E", "cls": "warrior", "team": "blue", "peer": 3}]
	if with_ally:
		entries.insert(1, {"name": "A", "cls": "warrior", "team": "red", "peer": 2})
	var m := ArenaMatch.new(2, entries, 0, "hard", "test")
	m.phase = "fight"
	m.fight_start = 0.0
	m.map.apply_state(true, 0)
	m.units[0].x = 0.0
	m.units[0].z = 0.0
	if with_ally:
		m.units[1].x = 0.0
		m.units[1].z = 3.0
	m.units[m.units.size() - 1].x = 14.0   # 14 m away, in the open: no scream, in smite range, in sight
	m.units[m.units.size() - 1].z = 0.0
	return m


## Abilities the priest starts (cast effects) during one think at the given health fraction.
func _first_cast(m: ArenaMatch, hp_frac: float) -> Array:
	var p: ArenaUnit = m.units[0]
	p.hp = p.max_hp * hp_frac
	p.brain = BotBrain.new("hard")
	var seen := []
	p.brain.think(m, p, 1000.0)
	for f in m.fx:
		if f.k == "cast" and f.id == p.id:
			seen.append(f.ability)
	return seen


func test_duel_priest_smites_instead_of_spending_the_gcd_on_a_light_wound() -> void:
	seed(3)
	var m := _match(false)
	check(Rules.has_los(m.map, m.units[0], m.units[1]), "hay línea de visión")
	for i in 5:   # the smite no longer depends on a dice roll
		var m2 := _match(false)
		eq(_first_cast(m2, 0.58), ["smite"], "a 58% de vida, solo, castiga")


func test_duel_priest_still_defends_when_badly_hurt() -> void:
	seed(3)
	var m := _match(false)
	eq(_first_cast(m, 0.3), ["pwshield"], "a 30% de vida, solo, se pone el escudo")


func test_team_priest_still_shields_the_hurt_ally_like_before() -> void:
	seed(3)
	var m := _match(true)
	eq(_first_cast(m, 0.58), ["pwshield"], "con un aliado vivo, a 58% cura igual que antes")


func test_lone_druid_keeps_its_healer_thresholds() -> void:
	seed(3)
	var m := _match(false, "druid")
	var p: ArenaUnit = m.units[0]
	p.hp = p.max_hp * 0.58
	p.brain = BotBrain.new("hard")
	p.brain.think(m, p, 1000.0)
	var seen := m.fx.filter(func(f): return f.k == "cast" and f.id == p.id).map(func(f): return f.ability)
	check(not seen.has("wrath"), "el druida solo no pasa a castigar a 58 por ciento (%s)" % str(seen))
