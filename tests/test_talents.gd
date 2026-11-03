extends TestBase
## Talents (data/talents.json, core/talents.gd): data, kit changes, match entries, saving.

const KITS := ["mage/fire", "mage/frost", "warlock", "hunter", "warrior", "priest", "rogue"]
const FIELDS := ["dmg", "heal", "cd", "cast", "range", "burnDps", "dotDps", "slowPct", "shatter"]
const STEP := 1000.0 / 60.0


func _split(k: String) -> Array:
	var p := k.split("/")
	return [p[0], p[1] if p.size() > 1 else ""]


## Value of the first effect of a talent (the numbers live in data/talents.json and get tuned).
func _val(cls: String, spec: String, row: int, i: int) -> float:
	return float(Talents.talent(cls, spec, row, i).effects[0].value)


# ---------------------------------------------------------------- data

func test_every_playable_kit_has_two_rows_of_three() -> void:
	for k in KITS:
		var cs := _split(k)
		var r := Talents.rows(cs[0], cs[1])
		eq(r.size(), Talents.ROWS, "%s: filas" % k)
		for row in r:
			eq((row as Array).size(), 3, "%s: opciones por fila" % k)
	for cls in GameData.playable_ids():
		for sid in (GameData.spec_ids(cls) if not GameData.spec_ids(cls).is_empty() else [""]):
			check(KITS.has(Talents.key(cls, sid)), "kit sin talentos: %s" % Talents.key(cls, sid))


func test_every_effect_points_at_something_real() -> void:
	var ids := {}
	for k in KITS:
		var cs := _split(k)
		var kit_ids: Array = GameData.abilities(cs[0], cs[1]).map(func(a): return a.id)
		var res_ids: Array = GameData.reserve(cs[0], cs[1]).map(func(a): return a.id)
		for row in Talents.rows(cs[0], cs[1]):
			for t in row:
				check(not ids.has(t.id), "id repetido: %s" % t.id)
				ids[t.id] = true
				check(str(t.get("name", "")) != "", "%s sin nombre" % t.id)
				check(Talents.icon(cs[0], cs[1], t) != "", "%s sin ícono" % t.id)
				check(Talents.describe(cs[0], cs[1], t) != "", "%s sin descripción" % t.id)
				var swapped_in: Array = t.effects.filter(func(x): return x.op == "swap").map(func(x): return x.to)
				for e in t.effects:
					match str(e.op):
						"swap":
							check(kit_ids.has(e.ability), "%s: cambia una habilidad que no está en el kit" % t.id)
							check(res_ids.has(e.to), "%s: %s no está en la reserva" % [t.id, e.to])
						"mul", "add":
							check(FIELDS.has(e.field) or (not e.has("ability") and e.field == "crit"), "%s: campo %s" % [t.id, e.field])
							if e.has("ability"):
								check(kit_ids.has(e.ability) or swapped_in.has(e.ability), "%s: %s no está en el kit" % [t.id, e.ability])
								check(GameData.find_ability(cs[0], e.ability, cs[1]).has(e.field), "%s: %s no tiene %s" % [t.id, e.ability, e.field])
						_:
							check(false, "%s: operación %s" % [t.id, e.op])


# ---------------------------------------------------------------- applying

func test_apply_changes_numbers_and_never_the_data() -> void:
	var base: float = GameData.find_ability("mage", "fireball", "fire").burnDps
	var k := Talents.kit("mage", "fire", [0, -1])
	near(float(k.abilities[0].burnDps), base * _val("mage", "fire", 0, 0), 0.001, "Brasas: más quemadura")
	eq(float(GameData.find_ability("mage", "fireball", "fire").burnDps), base, "GameData queda igual")
	eq(float(GameData.kit("mage", "fire").abilities[0].burnDps), base, "un kit nuevo no trae el talento")
	eq(Talents.kit("mage", "fire", []).abilities[0].burnDps, base, "sin talentos, el kit base")


func test_swap_puts_the_reserve_ability_on_the_same_slot() -> void:
	var k := Talents.kit("mage", "fire", [-1, 2])
	eq(str(k.abilities[1].id), "counter", "Piroexplosión → Contrahechizo")
	var p := Talents.kit("priest", "", [-1, 2])
	eq(str(p.abilities[3].id), "renew", "Escudo divino → Renovar")
	eq(str(GameData.ability("priest", 3).id), "pwshield", "el kit base no cambia")
	near(float(p.abilities[3].heal), float(GameData.find_ability("priest", "renew").heal) * float(Talents.talent("priest", "", 1, 2).effects[1].value), 0.001, "el número se aplica a la habilidad que entró")


func test_kit_level_talent_adds_crit() -> void:
	var k := Talents.kit("rogue", "", [2, -1])
	near(float(k.get("crit", 0.0)), float(GameData.kit("rogue").get("crit", 0.0)) + _val("rogue", "", 0, 2), 0.0001, "más crítico")


func test_normalize_drops_anything_invalid() -> void:
	eq(Talents.normalize("priest", "", [1, 2]), [1, 2], "válido")
	eq(Talents.normalize("priest", "", [7, -3]), [-1, -1], "fuera de rango")
	eq(Talents.normalize("priest", "", ["x", null]), [-1, -1], "tipos raros")
	eq(Talents.normalize("priest", "", "hola"), [-1, -1], "no es una lista")
	eq(Talents.normalize("priest", "", [1, 2], 1), [1, -1], "fila bloqueada por nivel")
	eq(Talents.normalize("druid", "", [1, 1]), [-1, -1], "clase sin talentos")


# ---------------------------------------------------------------- match

func _match(entries: Array) -> ArenaMatch:
	return ArenaMatch.new(2, entries, 1000.0, "normal", "test")


func test_match_units_get_their_talents() -> void:
	var m := _match([{"name": "A", "cls": "mage", "spec": "fire", "team": "red", "peer": 1, "talents": [1, 2]},
		{"name": "B", "cls": "warrior", "spec": "", "team": "blue", "peer": 2}])
	var a: ArenaUnit = m.units[0]
	near(float(a.ability(0).dmg), float(GameData.find_ability("mage", "fireball", "fire").dmg) * _val("mage", "fire", 0, 1), 0.001, "daño de la Bola de fuego")
	eq(str(a.ability(1).id), "counter", "Contrahechizo en el casillero 1")
	eq(m.roster()[0].get("talents", []), [1, 2], "el roster lleva los talentos")
	check(not m.roster()[1].has("talents"), "sin talentos no se manda nada")


func test_talented_cooldown_is_what_the_server_uses() -> void:
	var m := _match([{"name": "A", "cls": "hunter", "spec": "", "team": "red", "peer": 1, "talents": [1, -1]},
		{"name": "B", "cls": "warrior", "spec": "", "team": "blue", "peer": 2}])
	var a: ArenaUnit = m.units[0]
	near(float(a.ability(0).cd), float(GameData.ability("hunter", 0).cd) * _val("hunter", "", 0, 1), 0.001, "Tiro rápido")


func test_trap_freeze_comes_from_the_owner_kit() -> void:
	var m := _match([{"name": "A", "cls": "hunter", "spec": "", "team": "red", "peer": 1},
		{"name": "B", "cls": "warrior", "spec": "", "team": "blue", "peer": 2}])
	var h: ArenaUnit = m.units[0]
	var w: ArenaUnit = m.units[1]
	var kit := h.spec().duplicate()
	kit.abilities = (kit.abilities as Array).duplicate()
	var trap: Dictionary = (kit.abilities[2] as Dictionary).duplicate()
	trap.ccMs = 500.0
	kit.abilities[2] = trap
	h._kit = kit
	var now := 2000.0
	w.x = 5.0
	w.z = 5.0
	m.traps.append({"id": 999, "owner": h, "x": 5.0, "z": 5.0, "armed_at": 0.0, "expires_at": now + 60000})
	m._step_traps(now)
	check(w.incap_until > now, "queda congelado")
	check(w.incap_until - now <= 600.0, "con la duración del kit del dueño (%s ms)" % (w.incap_until - now))


func test_bots_get_random_talents_and_humans_keep_theirs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var e := MatchConfig.build_entries(2, [{"peer": 1, "name": "Ana", "cls": "priest", "spec": "", "pref": "red", "talents": [0, 1]}], rng)
	eq(e[0].talents, [0, 1], "el humano conserva los suyos")
	for x in e:
		if int(x.peer) == 0:
			check(x.talents is Array and (x.talents as Array).size() == Talents.ROWS, "el bot %s tiene talentos" % x.name)
			check((x.talents as Array).all(func(v): return v >= 0), "el bot elige en todas las filas")


func test_bot_classes_do_not_change_with_talents() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 42
	var e := MatchConfig.build_entries(3, [{"peer": 1, "name": "Ana", "cls": "mage", "spec": "fire", "pref": "red"}], a)
	var b := RandomNumberGenerator.new()
	b.seed = 42
	var e2 := MatchConfig.build_entries(3, [{"peer": 1, "name": "Ana", "cls": "mage", "spec": "fire", "pref": "red"}], b)
	eq(e.map(func(x): return x.cls), e2.map(func(x): return x.cls), "misma semilla, mismas clases")


func test_network_config_normalizes_talents() -> void:
	eq(MatchConfig.normalize({"cls": "priest", "talents": [2, 9]}).talents, [2, -1], "índice inválido descartado")
	eq(MatchConfig.normalize({"cls": "priest"}).talents, [-1, -1], "sin talentos")


func test_codec_knows_reserve_abilities() -> void:
	SnapshotCodec._tables()
	for id in ["counter", "agony", "silence", "pummel", "renew", "kick"]:
		check(SnapshotCodec._ability_ids.has(id), "%s en la tabla de ids" % id)


func test_player_controller_uses_talented_kit() -> void:
	var pc := PlayerController.new()
	pc.setup("mage", "red", "fire", [-1, 2])
	eq(str(pc.ability(1).id), "counter", "el cliente ve el Contrahechizo")


# ---------------------------------------------------------------- saving

func _store(path: String) -> ProgressStore:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return ProgressStore.new(path)


func test_store_locks_rows_by_level_and_saves() -> void:
	var path := "user://test_talents_progress.json"
	var st := _store(path)
	check(not st.set_talent("priest", "", 0, 1), "nivel 1: fila 1 bloqueada")
	st.champions["priest"] = {"level": 5, "xp": 0}
	check(st.set_talent("priest", "", 0, 1), "nivel 5: fila 1 abierta")
	check(not st.set_talent("priest", "", 1, 1), "nivel 5: fila 2 bloqueada")
	check(not st.set_talent("priest", "", 0, 5), "opción inexistente")
	eq(st.talents("priest"), [1, -1], "lo elegido")
	var again := ProgressStore.new(path)
	again.champions["priest"] = {"level": 5, "xp": 0}
	eq(again.talents("priest"), [1, -1], "se guarda")
	again.champions["priest"] = {"level": 1, "xp": 0}
	eq(again.talents("priest"), [-1, -1], "por debajo del nivel no cuenta")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_award_keeps_talents_and_v1_file_loads() -> void:
	var path := "user://test_talents_v1.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"champions": {"mage": {"level": 10, "xp": 0}}, "last_win_day": ""}))
	f.close()
	var st := ProgressStore.new(path)
	eq(st.level("mage"), 10, "lee el archivo viejo")
	eq(st.talents("mage", "fire"), [-1, -1], "sin talentos todavía")
	check(st.set_talent("mage", "fire", 1, 2), "elige en la fila 2")
	st.award("mage", true, 100.0, 0.0, false, "2026-11-03")
	eq(ProgressStore.new(path).talents("mage", "fire"), [-1, 2], "ganar XP no borra los talentos")
	eq(ProgressStore.new(path).talents("mage", "frost"), [-1, -1], "cada especialización tiene los suyos")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- marks (TalentMark)

func test_talented_abilities_carry_their_mark() -> void:
	var k := Talents.kit("mage", "fire", [0, 2])
	eq(TalentMark.kind_of(k.abilities[0]), "burn", "Brasas: sello de quemadura")
	eq(TalentMark.kind_of(k.abilities[1]), "swap", "Rompehechizos: sello de cambio (aunque después le cambie la recarga)")
	eq(str(k.abilities[1].talent.name), "Rompehechizos", "el talento queda en la habilidad")
	eq(TalentMark.kind_of(k.abilities[2]), "", "lo que no cambia no lleva sello")
	eq(TalentMark.kind_of(GameData.find_ability("mage", "fireball", "fire")), "", "GameData sin sello")
	eq(TalentMark.kind_of(Talents.kit("rogue", "", [2, -1]).abilities[0]), "crit", "el crítico del kit se marca en la Puñalada")


func test_every_talent_has_a_mark_kind() -> void:
	for k in KITS:
		var cs := _split(k)
		for row in Talents.rows(cs[0], cs[1]):
			for t in row:
				check(Talents.mark_kind(t) in ["dmg", "heal", "cd", "cast", "range", "burn", "frost", "crit", "swap"], "%s: sello %s" % [t.id, Talents.mark_kind(t)])
