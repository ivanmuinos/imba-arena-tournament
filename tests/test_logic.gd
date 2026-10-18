extends TestBase
## Non-visual client logic: effects, targeting, input mapping, match config, wire format.


# ---------------------------------------------------------------- effects

func test_debuffs_are_ordered_by_severity_and_flag_loss_of_control() -> void:
	var list := Effects.debuffs_of({"slow": 3000, "stun": 1200, "incap": 4000, "incapKind": "poly"})
	eq(list.map(func(e): return e.key), ["incap", "stun", "slow"], "orden de severidad")
	check(list[0].loc and list[1].loc and not list[2].loc, "la ralentización no es pérdida de control")
	eq(list[0].icon, "fx_poly", "polimorfia = oveja")


func test_buffs_use_power_and_class_specs() -> void:
	var list := Effects.buffs_of({"haste": 5000, "wall": 2000})
	eq(list.size(), 2, "dos buffs")
	var names: Array = list.map(func(e): return e.name)
	check(names.has("Pies de fuego"), "power-up")
	check(names.any(func(n): return n.begins_with("Muro de escudo")), "habilidad de clase")
	check(list.all(func(e): return e.good), "son positivos")


func test_secs_formatting() -> void:
	eq(Effects.secs(12500), "13", "más de 10 s: entero")
	eq(Effects.secs(2340), "2.3", "menos de 10 s: un decimal")


# ---------------------------------------------------------------- targeting

func _units() -> Array:
	return [
		{"id": 1, "team": "red", "x": 0.0, "z": 0.0, "alive": true, "visible": true},
		{"id": 2, "team": "blue", "x": 0.0, "z": 10.0, "alive": true, "visible": true},   # delante
		{"id": 3, "team": "blue", "x": 8.0, "z": 0.0, "alive": true, "visible": true},    # al costado, más cerca
		{"id": 4, "team": "blue", "x": 0.0, "z": -5.0, "alive": true, "visible": false},  # oculto
		{"id": 5, "team": "blue", "x": 0.0, "z": 6.0, "alive": false, "visible": true},   # muerto
	]


func test_tab_cycles_visible_living_enemies_starting_at_the_crosshair() -> void:
	var u := _units()
	var first := TargetLogic.cycle(u, "red", Vector2(0, 0), Vector2(0, 1), -1)
	eq(first, 2, "primero el que está bajo la mira")
	var second := TargetLogic.cycle(u, "red", Vector2(0, 0), Vector2(0, 1), first)
	eq(second, 3, "después el siguiente")
	eq(TargetLogic.cycle(u, "red", Vector2(0, 0), Vector2(0, 1), second), 2, "y vuelve al primero")


func test_tab_without_enemies_returns_none() -> void:
	var u := _units().filter(func(x): return x.team == "red")
	eq(TargetLogic.cycle(u, "red", Vector2.ZERO, Vector2(0, 1), -1), -1, "sin enemigos")


func test_acquire_prefers_close_and_facing_and_respects_range() -> void:
	var u := _units()
	eq(TargetLogic.acquire(u, "red", Vector2.ZERO, Vector2(0, 1), 40.0), 2, "elige al que mira")
	eq(TargetLogic.acquire(u, "red", Vector2.ZERO, Vector2(0, 1), 5.0), -1, "nadie dentro de 5 m")


func test_melee_swap_to_adjacent_enemy_not_incapacitated() -> void:
	var u := [
		{"id": 1, "team": "red", "x": 0.0, "z": 0.0, "alive": true, "visible": true},
		{"id": 2, "team": "blue", "x": 0.0, "z": 12.0, "alive": true, "visible": true},
		{"id": 3, "team": "blue", "x": 1.5, "z": 0.0, "alive": true, "visible": true, "incap": false},
		{"id": 4, "team": "blue", "x": -1.0, "z": 0.0, "alive": true, "visible": true, "incap": true},
	]
	eq(TargetLogic.melee_swap(u, "red", Vector2.ZERO, 3.2, 2), 3, "cambia al que está al lado")
	eq(TargetLogic.melee_swap(u, "red", Vector2.ZERO, 3.2, 3), -1, "si el objetivo ya está en alcance no cambia")


# ---------------------------------------------------------------- input

func test_move_vector_is_relative_to_camera() -> void:
	var f := InputLogic.move_vector(1, 0, 0.0)
	near(f.x, 0.0, 1e-6, "adelante, yaw 0: dx")
	near(f.y, 1.0, 1e-6, "adelante, yaw 0: dz")
	var r := InputLogic.move_vector(0, 1, 0.0)
	near(r.x, -1.0, 1e-6, "derecha mirando +z es -x")
	var diag := InputLogic.move_vector(1, 1, 0.0)
	near(diag.length(), 1.0, 1e-6, "la diagonal se normaliza")
	var turned := InputLogic.move_vector(1, 0, PI / 2)
	near(turned.x, 1.0, 1e-6, "con yaw 90° adelante es +x")


func test_slot_keys_match_the_wow_style_bar() -> void:
	eq(InputLogic.slot_for_key(KEY_1), 0, "1 = ataque automático / primer hechizo")
	eq(InputLogic.slot_for_key(KEY_2), 1, "2")
	eq(InputLogic.slot_for_key(KEY_Q), 2, "Q")
	eq(InputLogic.slot_for_key(KEY_E), 3, "E")
	eq(InputLogic.slot_for_key(KEY_SHIFT), 4, "Shift")
	eq(InputLogic.slot_for_key(KEY_F), 5, "F")
	eq(InputLogic.slot_for_key(KEY_R), 6, "R = ultimate")
	eq(InputLogic.slot_for_key(KEY_Z), -1, "otra tecla")
	eq(GameData.C.SLOT_KEYS, ["1", "2", "Q", "E", "Shift", "F", "R"], "etiquetas de la barra")


# ---------------------------------------------------------------- match config

func test_config_normalization() -> void:
	var c := MatchConfig.normalize({"mode": 7, "diff": "brutal", "map": "venus", "cls": "dragon", "name": "  \u0007Ana\n  "})
	eq(c.mode, 2, "modo inválido -> 2v2")
	eq(c.diff, "normal", "dificultad inválida")
	eq(c.map, "random", "mapa inválido -> aleatorio")
	eq(c.cls, "mage", "clase inválida")
	eq(c.name, "Ana", "nombre limpio")
	eq(MatchConfig.normalize({"mode": 3}).mode, 3, "3v3")
	eq(MatchConfig.sanitize_name("").length() > 0, true, "nombre por defecto")
	eq(MatchConfig.sanitize_name("x".repeat(40)).length(), 16, "máximo 16")


func test_entries_fill_bots_and_balance_teams() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var humans := [
		{"peer": 7, "name": "Ana", "cls": "mage", "pref": "red"},
		{"peer": 9, "name": "Beto", "cls": "rogue", "pref": "any"},
	]
	var e := MatchConfig.build_entries(2, humans, rng)
	eq(e.size(), 4, "2v2 = 4 lugares")
	eq(e.filter(func(x): return x.team == "red").size(), 2, "2 rojos")
	eq(e.filter(func(x): return x.team == "blue").size(), 2, "2 azules")
	eq(e.filter(func(x): return x.peer != 0).size(), 2, "dos humanos")
	var ana: Dictionary = e.filter(func(x): return x.peer == 7)[0]
	var beto: Dictionary = e.filter(func(x): return x.peer == 9)[0]
	eq(ana.team, "red", "respeta la preferencia")
	eq(beto.team, "blue", "'cualquiera' enfrenta a los humanos")
	check(e.filter(func(x): return x.peer == 0).all(func(x): return MatchConfig.BOT_NAMES.has(x.name)), "bots con nombre")


func test_entries_overflowing_team_goes_to_the_other() -> void:
	var humans := [
		{"peer": 2, "name": "A", "cls": "mage", "pref": "red"},
		{"peer": 3, "name": "B", "cls": "mage", "pref": "red"},
		{"peer": 4, "name": "C", "cls": "mage", "pref": "red"},
	]
	var e := MatchConfig.build_entries(2, humans)
	eq(e.filter(func(x): return x.team == "red").size(), 2, "tope de 2 por equipo")
	eq(e.filter(func(x): return x.peer == 4)[0].team, "blue", "el tercero pasa al otro equipo")


# ---------------------------------------------------------------- wire

func test_wire_roundtrip_and_rejects_garbage() -> void:
	var msg := {"t": "state", "units": [{"id": 1, "x": 1.5, "cc": {"stun": 300}}], "cast": null}
	var back = Wire.decode(Wire.encode(msg))
	eq(back, msg, "ida y vuelta")
	eq(Wire.decode(PackedByteArray([1, 2, 3])), null, "basura")
	eq(Wire.decode(var_to_bytes([1, 2])), null, "no es diccionario")
	eq(Wire.decode(var_to_bytes({"x": 1})), null, "sin tipo")
	eq(Wire.decode(var_to_bytes({"t": 5})), null, "tipo no es texto")


func test_wire_rejects_objects() -> void:
	var n := Node.new()
	var bytes := var_to_bytes_with_objects({"t": "x", "o": n})
	n.free()
	eq(Wire.decode(bytes), null, "no deserializa objetos")


func test_clean_input_clamps_and_rejects_nan() -> void:
	var ok := Wire.clean_input({"dx": 5.0, "dz": -9.0, "ax": 12.5, "az": -3.0})
	eq(ok.dx, 1.0, "dx acotado")
	eq(ok.dz, -1.0, "dz acotado")
	eq(Wire.clean_input({"dx": NAN, "dz": 0, "ax": 0, "az": 0}), {}, "NaN rechazado")
	eq(Wire.clean_input({"dx": "hola", "dz": 0, "ax": 0, "az": 0}), {}, "tipos inválidos")
	eq(Wire.clean_input({"dx": INF, "dz": 0, "ax": 0, "az": 0}), {}, "infinito rechazado")


func test_clean_cast() -> void:
	var c := Wire.clean_cast({"slot": 3, "ax": 1.0, "az": 2.0, "target": 4})
	eq(c.slot, 3, "slot")
	eq(c.target, 4, "target")
	eq(Wire.clean_cast({"slot": 3, "ax": 1.0, "az": 2.0, "target": null}).target, -1, "sin objetivo = -1")
	eq(Wire.clean_cast({"slot": 99, "ax": 1.0, "az": 2.0}), {}, "slot fuera de rango")
	eq(Wire.clean_cast({"slot": 1, "ax": NAN, "az": 2.0}), {}, "NaN")


func test_dampening_debuff_entry() -> void:
	eq(Effects.damp_effect(0.0).size(), 0, "sin amortiguación no hay ícono")
	var e: Dictionary = Effects.damp_effect(0.234)[0]
	eq(e.text, "23%", "el porcentaje se redondea")
	check(e.name.contains("Amortiguación") and e.name.contains("23%"), "nombre en español con el valor")
	check(ResourceLoader.exists("res://assets/icons/%s.svg" % e.icon), "tiene ícono")
