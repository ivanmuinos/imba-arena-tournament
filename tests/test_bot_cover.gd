extends TestBase
## Bots usan las columnas: si un enemigo les está casteando algo y hay cobertura a tiempo, se meten detrás para que el
## hechizo falle (la mecánica de cortar línea de visión que usan los jugadores).

const NOW := 10000.0


## Mago rojo pegado al costado oeste de la columna de (10, 8); mago azul casteándole desde (14, -8), a la vista.
func _match(map_id: String) -> ArenaMatch:
	var m := ArenaMatch.new(2, [
		{"name": "V", "cls": "mage", "team": "red", "peer": 1},
		{"name": "C", "cls": "mage", "team": "blue", "peer": 2}], 0, "hard", map_id)
	m.phase = "fight"
	m.fight_start = 0.0
	m.map.apply_state(true, 0)
	m.units[0].x = 7.0
	m.units[0].z = 7.5
	m.units[1].x = 14.0
	m.units[1].z = -8.0
	for u in m.units:
		u.y = m.map.height_at(u.x, u.z)
		u.brain = BotBrain.new("hard")
		u.brain.skill = 1.0
	return m


func _hard_cast_slot(u: ArenaUnit) -> int:
	var ab: Array = u.spec().abilities
	for i in ab.size():
		if float(ab[i].get("cast", 0)) >= 1200.0 and not ab[i].get("friendly", false) and not ab[i].get("ult", false):
			return i
	return -1


func test_bot_steps_behind_a_pillar_when_an_enemy_casts_at_it() -> void:
	var m := _match("pillars")
	var victim: ArenaUnit = m.units[0]
	var caster: ArenaUnit = m.units[1]
	check(Rules.has_los(m.map, caster, victim), "arranca a la vista del que castea")
	var slot := _hard_cast_slot(caster)
	check(slot >= 0 and m.cast_ability(caster, slot, victim.x, victim.z, NOW, victim.id), "el enemigo empieza a castear")
	victim.brain.think(m, victim, NOW + 400.0)
	var spot: Vector2 = victim.brain.juke
	check(spot != Vector2.INF, "elige un punto de cobertura")
	check(not Rules.has_los(m.map, caster, {"x": spot.x, "z": spot.y}), "desde ahí el que castea no lo ve")
	check(victim.cast.is_empty(), "no se queda parado casteando")
	check(victim.input.dot((spot - Vector2(victim.x, victim.z)).normalized()) > 0.3, "camina hacia la cobertura")


func test_bot_does_not_run_when_no_cover_is_in_reach() -> void:
	var m := _match("test")
	var victim: ArenaUnit = m.units[0]
	var caster: ArenaUnit = m.units[1]
	m.cast_ability(caster, _hard_cast_slot(caster), victim.x, victim.z, NOW, victim.id)
	victim.brain.think(m, victim, NOW + 400.0)
	check(victim.brain.juke == Vector2.INF, "en campo abierto no hay dónde esconderse: sigue peleando")


func test_bot_ignores_a_cast_that_is_not_aimed_at_it() -> void:
	var m := _match("pillars")
	var victim: ArenaUnit = m.units[0]
	var caster: ArenaUnit = m.units[1]
	m.cast_ability(caster, _hard_cast_slot(caster), -20.0, -20.0, NOW, -1)
	victim.brain.think(m, victim, NOW + 400.0)
	check(victim.brain.juke == Vector2.INF, "un casteo apuntado a otro lado no lo mueve")
