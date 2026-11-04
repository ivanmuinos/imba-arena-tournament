extends TestBase
## Talents (data/talents.json, core/talents.gd): data, kit changes, match entries, saving.

const KITS := ["mage/fire", "mage/frost", "warlock", "hunter", "warrior", "priest", "rogue", "druid", "paladin"]
const FIELDS := ["dmg", "heal", "cd", "cast", "range", "burnDps", "dotDps", "slowPct", "shatter", "ccMs"]
const STEP := 1000.0 / 60.0
## Fields a "set" talent can give an ability (what ArenaMatch reads).
const MECHANICS := ["bounce", "nth", "instantAfterCrits", "noPushback", "curseHaste", "castMove", "leech", "allyHeal",
	"drainHeal", "hotHps", "curseMark", "spread", "poison", "slowStack", "stillCd", "critVsSlowed", "vsSlowed", "behind",
	"ultGain", "healCut", "killReset", "cdOf", "charges"]


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
						"set":
							check(kit_ids.has(e.ability) or swapped_in.has(e.ability), "%s: %s no está en el kit" % [t.id, e.ability])
							check(MECHANICS.has(e.field), "%s: mecánica %s desconocida" % [t.id, e.field])
							check(not Talents.describe(cs[0], cs[1], t).contains(": " + str(e.field)), "%s: falta el texto de %s" % [t.id, e.field])
						"mul", "add":
							check(FIELDS.has(e.field) or (not e.has("ability") and e.field in ["crit", "block"]), "%s: campo %s" % [t.id, e.field])
							if e.has("ability"):
								check(kit_ids.has(e.ability) or swapped_in.has(e.ability), "%s: %s no está en el kit" % [t.id, e.ability])
								check(GameData.find_ability(cs[0], e.ability, cs[1]).has(e.field), "%s: %s no tiene %s" % [t.id, e.ability, e.field])
						_:
							check(false, "%s: operación %s" % [t.id, e.op])


# ---------------------------------------------------------------- applying

func test_apply_changes_numbers_and_never_the_data() -> void:
	var base: float = GameData.find_ability("mage", "fireball", "fire").burnDps
	var k := Talents.kit("mage", "fire", [2, -1])
	near(float(k.abilities[0].burnDps), base * _val("mage", "fire", 0, 2), 0.001, "Brasas: más quemadura")
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


func test_kit_level_talent_adds_block() -> void:
	var k := Talents.kit("warrior", "", [2, -1])
	near(float(k.get("block", 0.0)), _val("warrior", "", 0, 2), 0.0001, "más bloqueo")


func test_set_gives_the_mechanic_and_its_companions() -> void:
	var k := Talents.kit("mage", "frost", [0, -1])
	eq(int(k.abilities[0].nth), 3, "cada 3")
	eq(str(k.abilities[0].nthEffect), "freeze", "congela")
	check(not GameData.find_ability("mage", "frostbolt", "frost").has("nth"), "GameData queda igual")
	check(Talents.describe("mage", "frost", Talents.talent("mage", "frost", 0, 0)).contains("congela"), "el texto lo dice")


func test_normalize_drops_anything_invalid() -> void:
	eq(Talents.normalize("priest", "", [1, 2]), [1, 2], "válido")
	eq(Talents.normalize("priest", "", [7, -3]), [-1, -1], "fuera de rango")
	eq(Talents.normalize("priest", "", ["x", null]), [-1, -1], "tipos raros")
	eq(Talents.normalize("priest", "", "hola"), [-1, -1], "no es una lista")
	eq(Talents.normalize("priest", "", [1, 2], 1), [1, -1], "fila bloqueada por nivel")
	eq(Talents.normalize("ct", "", [1, 1]), [-1, -1], "clase sin talentos")


# ---------------------------------------------------------------- match

func _match(entries: Array) -> ArenaMatch:
	return ArenaMatch.new(2, entries, 1000.0, "normal", "test")


func test_match_units_get_their_talents() -> void:
	var m := _match([{"name": "A", "cls": "mage", "spec": "fire", "team": "red", "peer": 1, "talents": [1, 2]},
		{"name": "B", "cls": "warrior", "spec": "", "team": "blue", "peer": 2}])
	var a: ArenaUnit = m.units[0]
	eq(int(a.ability(0).get("nth", 0)), int(_val("mage", "fire", 0, 1)), "Tercera llama en la Bola de fuego")
	eq(str(a.ability(1).id), "counter", "Contrahechizo en el casillero 1")
	eq(m.roster()[0].get("talents", []), [1, 2], "el roster lleva los talentos")
	check(not m.roster()[1].has("talents"), "sin talentos no se manda nada")


func test_talented_cooldown_is_what_the_server_uses() -> void:
	var m := _match([{"name": "A", "cls": "mage", "spec": "frost", "team": "red", "peer": 1, "talents": [2, -1]},
		{"name": "B", "cls": "warrior", "spec": "", "team": "blue", "peer": 2}])
	var a: ArenaUnit = m.units[0]
	near(float(a.ability(0).cast), float(GameData.find_ability("mage", "frostbolt", "frost").cast) + _val("mage", "frost", 0, 2), 0.001, "Escarcha veloz")


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
	eq(TalentMark.kind_of(k.abilities[0]), "bounce", "Bola rebotadora: sello de rebote")
	eq(TalentMark.kind_of(k.abilities[1]), "swap", "Rompehechizos: sello de cambio (aunque después le cambie la recarga)")
	eq(str(k.abilities[1].talent.name), "Rompehechizos", "el talento queda en la habilidad")
	eq(TalentMark.kind_of(k.abilities[2]), "", "lo que no cambia no lleva sello")
	eq(TalentMark.kind_of(GameData.find_ability("mage", "fireball", "fire")), "", "GameData sin sello")
	eq(TalentMark.kind_of(Talents.kit("warrior", "", [2, -1]).abilities[0]), "dmg", "el bloqueo del kit se marca en el Golpe")
	eq(TalentMark.kind_of(Talents.kit("rogue", "", [2, -1]).abilities[0]), "nth", "Cuarta herida: sello de cada N")


func test_every_talent_has_a_mark_kind() -> void:
	for k in KITS:
		var cs := _split(k)
		for row in Talents.rows(cs[0], cs[1]):
			for t in row:
				check(Talents.mark_kind(t) in ["dmg", "heal", "cd", "cast", "range", "burn", "frost", "crit", "swap", "bounce", "nth"], "%s: sello %s" % [t.id, Talents.mark_kind(t)])


# ---------------------------------------------------------------- mechanics (ArenaMatch)

var now := 0.0


## A fight already started: `a` (talented) at z=20 facing -z, enemies in a row in front.
func _fight(cls: String, spec: String, talents: Array, enemies := ["warrior"]) -> ArenaMatch:
	now = 1_000_000.0
	var e := [{"name": "A", "cls": cls, "spec": spec, "team": "red", "peer": 1, "talents": talents}]
	for i in enemies.size():
		e.append({"name": "E%d" % i, "cls": enemies[i], "spec": "", "team": "blue", "peer": 2 + i})
	var m := ArenaMatch.new(2, e, now, "normal", "test")
	_adv(m, 20100)
	var a: ArenaUnit = m.units[0]
	a.x = 0.0
	a.z = 20.0
	a.rot = PI
	for i in range(1, m.units.size()):
		m.units[i].x = (i - 1) * 3.0
		m.units[i].z = 8.0
	return m


func _adv(m: ArenaMatch, ms: float) -> void:
	var t := 0.0
	while t < ms:
		now += STEP
		t += STEP
		m.tick(now)


func _hit(m: ArenaMatch, a: ArenaUnit, id: String, t: ArenaUnit) -> void:
	m._on_proj_hit({"spec": a.ability_by_id(id), "owner": a, "hits": []}, t, now)


func test_bounce_jumps_to_a_second_enemy() -> void:
	var m := _fight("mage", "fire", [0, -1], ["warrior", "priest"])
	var a: ArenaUnit = m.units[0]
	_hit(m, a, "fireball", m.units[1])
	eq(m.projs.size(), 1, "sale un rebote")
	eq(m.projs[0].target, m.units[2], "hacia el otro enemigo")
	near(float(m.projs[0].spec.dmg), float(a.ability(0).dmg) * 0.5, 0.01, "con la mitad del daño")
	_adv(m, 600)
	check(m.units[2].hp < m.units[2].max_hp, "el segundo recibe daño")
	eq(m.projs.size(), 0, "rebota una sola vez")


func test_nth_cast_is_empowered_and_counted() -> void:
	var m := _fight("rogue", "", [2, -1])
	var a: ArenaUnit = m.units[0]
	for i in 3:
		m._count_nth(a, a.ability(0))
	eq(m.stacks_shown(a)[0], 3, "el contador llega a 3")
	check(m._count_nth(a, a.ability(0)), "la 4.ª está potenciada")
	eq(m.stacks_shown(a)[0], 0, "y el contador vuelve a 0")
	eq(m.stacks_shown(a)[1], -1, "lo demás sin contador")
	check(m.snapshot_for(a, now).you.has("st"), "el snapshot lleva los contadores")
	var plain := _fight("warrior", "", [])
	check(not plain.snapshot_for(plain.units[0], now).you.has("st"), "sin talentos con contador no se manda")


func test_every_third_frostbolt_freezes() -> void:
	var m := _fight("mage", "frost", [0, -1])
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	m.proc_rng.seed = 1
	var frozen := 0
	for i in 6:
		b.hp = b.max_hp
		b.incap_until = 0.0
		b.root_until = 0.0
		b.dr = {}
		m._hit_emp = m._count_nth(a, a.ability(0))
		m._on_proj_hit({"spec": a.ability(0), "owner": a, "hits": []}, b, now)
		m._hit_emp = false
		if b.incap_until > now and b.incap_kind == "freeze":
			frozen += 1
	eq(frozen, 2, "congela 2 de 6")


func test_pyroblast_is_instant_after_two_crits() -> void:
	var m := _fight("mage", "fire", [-1, 0])
	var a: ArenaUnit = m.units[0]
	var slot := slot_of(a, "pyro")
	a.crit_streak = 2
	eq(m.stacks_shown(a)[slot], 2, "el ícono muestra los críticos")
	check(m.cast_ability(a, slot, 0.0, 8.0, now, m.units[1].id), "se lanza")
	check(a.cast.is_empty(), "instantánea")
	eq(a.crit_streak, 0, "gasta la racha")


func test_shadowbolt_leech_heals_the_warlock() -> void:
	var m := _fight("warlock", "", [0, -1])
	var a: ArenaUnit = m.units[0]
	a.hp = a.max_hp - 50.0
	_hit(m, a, "shadowbolt", m.units[1])
	check(a.hp > a.max_hp - 50.0, "se cura")


func test_shadowbolt_casts_faster_on_a_cursed_target() -> void:
	var m := _fight("warlock", "", [1, -1])
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	var base := float(a.ability(0).cast)
	near(m._cast_ms(a, a.ability(0), b.id, b.x, b.z, now), base, 0.01, "sin maldición, normal")
	m._apply_curse(b, a, a.ability_by_id("corruption"), now)
	check(m._cast_ms(a, a.ability(0), b.id, b.x, b.z, now) < base, "con Corrupción, más rápida")


func test_mark_makes_curses_hit_harder() -> void:
	var m := _fight("warlock", "", [2, -1])
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	_hit(m, a, "shadowbolt", b)
	check(b.curse_mark > 0.0 and b.curse_mark_until > now, "queda marcado")


func test_corruption_spreads_to_a_nearby_enemy() -> void:
	var m := _fight("warlock", "", [-1, 0], ["warrior", "priest"])
	var a: ArenaUnit = m.units[0]
	check(m.cast_ability(a, slot_of(a, "corruption"), 0.0, 8.0, now, m.units[1].id), "se lanza")
	check(not m.units[1].curses.is_empty(), "el objetivo queda maldito")
	check(not m.units[2].curses.is_empty(), "y el de al lado también")


func test_hunter_shots_stack_a_slow() -> void:
	var m := _fight("hunter", "", [0, -1], ["priest"])
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	for i in 5:
		b.hp = b.max_hp
		_hit(m, a, "shot", b)
	check(b.slow_until > now, "ralentizado")
	near(b.slow_pct, 0.3, 0.001, "hasta 30%")


func test_piercing_shot_goes_through() -> void:
	var m := _fight("hunter", "", [1, -1], ["priest", "priest"])  # priests never block
	var a: ArenaUnit = m.units[0]
	m.units[2].x = 0.0
	m.units[2].z = 2.0  # right behind the first one
	m._cast_emp = true
	m._spawn_proj(a, a.ability(0), Vector2(0, -1))
	m._cast_emp = false
	_adv(m, 800)
	check(m.units[1].hp < m.units[1].max_hp, "pega al primero")
	check(m.units[2].hp < m.units[2].max_hp, "y atraviesa al segundo")


func test_still_hunter_shoots_faster() -> void:
	var m := _fight("hunter", "", [2, -1])
	var a: ArenaUnit = m.units[0]
	a.input = Vector2.ZERO
	m._execute(a, 0, 0.0, 8.0, -1, now)
	check(a.cds[0] - now < float(a.ability(0).cd) - 1.0, "quieto, menos recarga")


func test_aimed_shot_can_be_cast_moving() -> void:
	var m := _fight("hunter", "", [-1, 0])
	var a: ArenaUnit = m.units[0]
	check(m.cast_ability(a, 1, 0.0, 8.0, now, m.units[1].id), "empieza")
	a.input = Vector2(1, 0)
	_adv(m, 100)
	check(not a.cast.is_empty(), "moverse no lo corta")


func test_aimed_shot_crits_slowed_targets() -> void:
	var m := _fight("hunter", "", [-1, 1], ["priest"])
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	b.slow_until = now + 3000
	b.slow_pct = 0.3
	b.rot = PI  # facing away: no shield block
	m.fx.clear()
	_hit(m, a, "aimed", b)
	var hits := m.fx.filter(func(f): return f.k == "hit" and f.id == b.id)
	check(not hits.is_empty() and hits[0].crit, "crítico seguro")


func test_warrior_strike_hits_slowed_harder() -> void:
	var m := _fight("warrior", "", [0, -1])
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	near(m._talent_bonus(a.ability(0), a, b, now), 1.0, 0.001, "sin ralentizar, normal")
	b.slow_until = now + 1000
	near(m._talent_bonus(a.ability(0), a, b, now), 1.0 + _val("warrior", "", 0, 0), 0.001, "ralentizado, más daño")


func test_mortal_reset_on_kill_and_deeper_wound() -> void:
	var m := _fight("warrior", "", [-1, 0], ["priest", "warrior"])
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	var slot := slot_of(a, "mortal")
	a.cds[slot] = now + 6000
	b.hp = 1.0
	b.rot = PI
	m._damage(b, 50.0, a, now, "mortal")
	check(not b.alive, "muere")
	check(a.cds[slot] <= now, "Golpe mortal listo otra vez")
	var m2 := _fight("warrior", "", [-1, 1])
	var w: ArenaUnit = m2.units[0]
	var t: ArenaUnit = m2.units[1]
	t.x = 0.0
	t.z = 18.0
	check(m2.cast_ability(w, slot_of(w, "mortal"), t.x, t.z, now, t.id), "golpe mortal")
	near(t.mortal_pct, 0.7, 0.001, "corta 70% la curación")


func test_smite_heals_the_most_hurt_ally_and_cuts_the_shield() -> void:
	var m := _fight("priest", "", [0, -1])
	var a: ArenaUnit = m.units[0]
	a.hp = a.max_hp - 100.0
	_hit(m, a, "smite", m.units[1])
	check(a.hp > a.max_hp - 100.0, "Expiación cura")
	var m2 := _fight("priest", "", [1, -1])
	var p: ArenaUnit = m2.units[0]
	var s := slot_of(p, "pwshield")
	p.cds[s] = now + 5000
	_hit(m2, p, "smite", m2.units[1])
	near(p.cds[s], now + 4000, 0.01, "el Escudo recarga 1 s antes")


func test_heal_leaves_a_heal_over_time() -> void:
	var m := _fight("priest", "", [-1, 0])
	var a: ArenaUnit = m.units[0]
	a.hp = a.max_hp - 200.0
	m._execute(a, 1, a.x, a.z, a.id, now)
	check(a.hot_until > now and a.hot_hps > 0.0, "queda una curación en el tiempo")


func test_rogue_poison_and_backstab() -> void:
	var m := _fight("rogue", "", [0, -1], ["priest"])  # a priest never blocks
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	b.x = 0.0
	b.z = 18.0
	b.rot = PI
	m._damage(b, 10.0, a, now, "stab")
	check(b.curses.has("%d:poison" % a.id), "envenenado")
	check(m.snapshot_for(a, now).units.any(func(u): return u.id == b.id and u.cc.has("poison")), "el veneno se ve")
	var m2 := _fight("rogue", "", [1, -1])
	var r: ArenaUnit = m2.units[0]
	var t: ArenaUnit = m2.units[1]
	t.x = 0.0
	t.z = 18.0
	t.rot = PI  # looking away from the rogue (who is at z=20)
	near(m2._talent_bonus(r.ability(0), r, t, now), 1.2, 0.001, "por la espalda +20%")
	t.rot = 0.0
	near(m2._talent_bonus(r.ability(0), r, t, now), 1.0, 0.001, "de frente, normal")


func test_eviscerate_kill_resets_cheap_shot() -> void:
	var m := _fight("rogue", "", [-1, 0], ["priest", "warrior"])
	var a: ArenaUnit = m.units[0]
	var b: ArenaUnit = m.units[1]
	var cs := slot_of(a, "cheapshot")
	a.cds[cs] = now + 20000
	b.hp = 1.0
	b.rot = PI
	m._damage(b, 50.0, a, now, "eviscerate")
	check(a.cds[cs] <= now, "Golpe bajo listo")


func test_icelance_with_two_charges() -> void:
	var m := _fight("mage", "frost", [-1, 0])
	var a: ArenaUnit = m.units[0]
	check(m.cast_ability(a, 1, 0.0, 8.0, now, m.units[1].id), "primera")
	eq(m.charges_left(a)[1], 1, "queda una")


func test_pyro_focus_ignores_pushback() -> void:
	var m := _fight("mage", "fire", [-1, 1])
	var a: ArenaUnit = m.units[0]
	check(m.cast_ability(a, 1, 0.0, 8.0, now, m.units[1].id), "empieza la Piroexplosión")
	var ends: float = a.cast.ends_at
	m._damage(a, 10.0, m.units[1], now, "strike")
	eq(a.cast.ends_at, ends, "no se retrasa")
