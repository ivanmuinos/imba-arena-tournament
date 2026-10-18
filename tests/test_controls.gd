extends TestBase
## WoW-style controls: mouse modes, keyboard turn/strafe, click picking, off-screen indicator,
## spell kinds and the new target-based casting rules.


# ---------------------------------------------------------------- mouse / keyboard

func test_mouse_modes_follow_the_buttons() -> void:
	eq(InputLogic.mouse_mode(false, false), "none", "sin botones")
	eq(InputLogic.mouse_mode(true, false), "orbit", "izquierdo: sólo cámara")
	eq(InputLogic.mouse_mode(false, true), "mouselook", "derecho: cámara y personaje")
	eq(InputLogic.mouse_mode(true, true), "mouselook", "ambos: mouselook + avanzar")


func test_drag_threshold_distinguishes_click_from_drag() -> void:
	check(not InputLogic.is_drag(Vector2(100, 100), Vector2(102, 101)), "temblor = clic")
	check(InputLogic.is_drag(Vector2(100, 100), Vector2(110, 100)), "10 px = arrastre")


func test_keyboard_a_d_turn_without_buttons_and_strafe_with_right_button() -> void:
	var m := InputLogic.keyboard_move(true, false, true, false, false, false)
	eq([m.fwd, m.strafe, m.turn], [1, 0, 1], "A sin botón gira a la izquierda")
	m = InputLogic.keyboard_move(false, false, false, true, false, false)
	eq([m.fwd, m.strafe, m.turn], [0, 0, -1], "D gira a la derecha")
	m = InputLogic.keyboard_move(false, false, true, false, true, false)
	eq([m.fwd, m.strafe, m.turn], [0, -1, 0], "con clic derecho A es paso lateral")
	m = InputLogic.keyboard_move(false, false, false, true, true, false)
	eq(m.strafe, 1, "D paso lateral derecho")
	m = InputLogic.keyboard_move(false, true, false, false, false, false)
	eq(m.fwd, -1, "S retrocede")


func test_both_buttons_run_forward() -> void:
	var m := InputLogic.keyboard_move(false, false, false, false, true, true)
	eq(m.fwd, 1, "ambos botones = correr")
	m = InputLogic.keyboard_move(false, true, false, false, true, true)
	eq(m.fwd, 0, "S cancela")


func test_camera_eases_behind_character_only_when_moving_without_buttons() -> void:
	near(InputLogic.follow_yaw(1.0, 0.0, 0.1, true, false), 1.0 - (1.0 - exp(-4.0 * 0.1)), 1e-6, "se acerca")
	eq(InputLogic.follow_yaw(1.0, 0.0, 0.1, false, false), 1.0, "quieto: no se mueve")
	eq(InputLogic.follow_yaw(1.0, 0.0, 0.1, true, true), 1.0, "con un botón apretado: la cámara es libre")
	var wrap := InputLogic.follow_yaw(3.0, -3.0, 0.1, true, false)
	check(wrap > 3.0, "toma el camino corto a través de PI (%s)" % wrap)


func test_move_vector_uses_character_facing() -> void:
	var v := InputLogic.move_vector(1, 0, PI / 2)
	near(v.x, 1.0, 1e-6, "mirando a +x, adelante es +x")


# ---------------------------------------------------------------- picking

func test_click_picker_chooses_nearest_within_radius_and_prefers_closer_to_camera() -> void:
	var cands := [
		{"id": 1, "pos": Vector2(100, 100), "r": 30.0, "depth": 20.0},
		{"id": 2, "pos": Vector2(112, 100), "r": 30.0, "depth": 8.0},
		{"id": 3, "pos": Vector2(400, 300), "r": 30.0, "depth": 5.0},
	]
	eq(ClickPicker.pick(cands, Vector2(108, 100)), 2, "gana el más cercano a la cámara cuando se solapan")
	eq(ClickPicker.pick(cands, Vector2(300, 300)), -1, "suelo vacío: nada")
	eq(ClickPicker.pick(cands, Vector2(398, 310)), 3, "el tercero")


func test_click_picker_hits_the_whole_body_from_feet_to_head() -> void:
	# A unit standing on screen from feet (500, 400) up to head (500, 280): 120 px tall.
	var body := ClickPicker.body(1, Vector2(500, 400), Vector2(500, 280), 10.0)
	eq(ClickPicker.pick([body], Vector2(500, 395)), 1, "los pies")
	eq(ClickPicker.pick([body], Vector2(500, 285)), 1, "la cabeza")
	eq(ClickPicker.pick([body], Vector2(525, 340)), 1, "un costado del torso")
	eq(ClickPicker.pick([body], Vector2(580, 340)), -1, "lejos del cuerpo: nada")
	# Far away units are small on screen but keep a minimum clickable width.
	var tiny := ClickPicker.body(2, Vector2(100, 100), Vector2(100, 92), 40.0)
	eq(ClickPicker.pick([tiny], Vector2(112, 96)), 2, "un muñeco lejano sigue siendo clickeable")


# ---------------------------------------------------------------- off-screen indicator

func test_offscreen_indicator() -> void:
	var vp := Vector2(1280, 720)
	var on := OffscreenIndicator.edge_point(Vector2(600, 300), false, vp, 40.0)
	check(not on.visible, "en pantalla: no se muestra")
	var right := OffscreenIndicator.edge_point(Vector2(2000, 360), false, vp, 40.0)
	check(right.visible, "a la derecha: se muestra")
	near(right.pos.x, 1240.0, 0.01, "pegado al borde derecho")
	near(right.angle, 0.0, 0.01, "apunta a la derecha")
	var behind := OffscreenIndicator.edge_point(Vector2(640, 100), true, vp, 40.0)
	check(behind.visible, "detrás de la cámara: se muestra")
	check(behind.pos.y > 600.0, "detrás = abajo (hay que girar)")
	var top := OffscreenIndicator.edge_point(Vector2(640, -500), false, vp, 40.0)
	near(top.pos.y, 40.0, 0.01, "borde superior")


# ---------------------------------------------------------------- spell kinds

func test_every_ability_has_a_kind_consistent_with_its_flags() -> void:
	for cls in GameData.classes:
		var abilities: Array = GameData.classes[cls].abilities
		for i in abilities.size():
			var a: Dictionary = abilities[i]
			var k := SpellKinds.kind(a)
			check(k in ["auto", "self", "hostile", "friendly", "ground", "direction"], "%s/%s tiene tipo (%s)" % [cls, a.id, k])
			if a.get("friendly", false):
				eq(k, "friendly", "%s es amigable" % a.id)
			if a.get("melee", false) and i > 0:
				eq(k, "hostile", "%s cuerpo a cuerpo = objetivo hostil" % a.id)
			eq(k == "auto", a.get("auto", false), "%s: sólo el auto-ataque es 'auto'" % a.id)
	eq(SpellKinds.kind(GameData.ability("mage", 6)), "ground", "meteoros: suelo")
	eq(SpellKinds.kind(GameData.ability("hunter", 2)), "ground", "trampa: suelo")
	eq(SpellKinds.kind(GameData.ability("mage", 4)), "direction", "traslación: dirección")
	eq(SpellKinds.kind(GameData.ability("mage", 2)), "self", "nova: sobre vos")


# ---------------------------------------------------------------- casting rules

func _unit(id: int, team: String, x: float, z: float, alive := true, visible := true) -> Dictionary:
	return {"id": id, "team": team, "x": x, "z": z, "alive": alive, "visible": visible, "incap": false}


func _ctx(now: float, units: Array, extra := {}) -> Dictionary:
	var c := {"now": now, "alive": true, "phase": "fight", "units": [_unit(1, "red", 0, 0)] + units, "pos": Vector2(0, 0), "fwd": Vector2(0, 1),
		"my_id": 1, "mouse_ground": Vector2(0, 10), "auto_on": false}
	c.merge(extra, true)
	return c


func _pc(cls: String) -> PlayerController:
	var pc := PlayerController.new()
	pc.setup(cls, "red")
	return pc


func test_hostile_spell_needs_a_hostile_target_in_range_and_sight() -> void:
	var pc := _pc("mage")
	var enemy := _unit(2, "blue", 0, 12)
	var behind := _unit(2, "blue", 0, -12)
	var r := pc.try_cast(1, _ctx(1000.0, [behind]))
	eq(r.error, "No tenés objetivo", "sin objetivo y nadie adelante no dispara")
	eq(r.msg, {}, "no se envía nada")
	pc.select(2, _ctx(1000.0, [enemy]))
	r = pc.try_cast(1, _ctx(1000.0, [enemy]))
	eq(r.msg.target, 2, "va al objetivo")
	near(r.msg.az, 12.0, 0.01, "apunta a su posición")
	pc.cast_lock[1] = 0.0
	var far := _unit(2, "blue", 0, 60)
	r = pc.try_cast(1, _ctx(3000.0, [far]))
	check(r.error.contains("Fuera de alcance"), "fuera de alcance (%s)" % r.error)
	pc.cast_lock[1] = 0.0
	r = pc.try_cast(1, _ctx(5000.0, [enemy], {"los": func(_a, _b): return false}))
	eq(r.error, "No está a la vista", "sin línea de visión")


func test_hostile_spell_on_a_friendly_target_is_invalid() -> void:
	var pc := _pc("mage")
	var ally := _unit(3, "red", 3, 3)
	pc.select(3, _ctx(1000.0, [ally]))
	var r := pc.try_cast(1, _ctx(1000.0, [ally]))
	check(r.error.contains("aliado"), "no podés hechizar a un aliado (%s)" % r.error)
	eq(r.msg, {}, "no se envía")


func test_dead_or_hidden_target_counts_as_no_target() -> void:
	var pc := _pc("mage")
	var e := _unit(2, "blue", 0, 10)
	pc.select(2, _ctx(1000.0, [e]))
	e.alive = false
	eq(pc.try_cast(1, _ctx(1000.0, [e])).error, "No tenés objetivo", "muerto")
	e.alive = true
	e.visible = false
	pc.cast_lock[1] = 0.0
	eq(pc.try_cast(1, _ctx(2000.0, [e])).error, "No tenés objetivo", "fuera de vista")


func test_friendly_spells_go_to_selected_ally_else_self() -> void:
	var pc := _pc("priest")
	var ally := _unit(3, "red", 4, 0)
	var enemy := _unit(2, "blue", 0, 10)
	eq(pc.try_cast(1, _ctx(1000.0, [ally, enemy])).msg.target, 1, "sin selección: a vos")
	pc.select(3, _ctx(1000.0, [ally, enemy]))
	pc.cast_lock[1] = 0.0
	eq(pc.try_cast(1, _ctx(2000.0, [ally, enemy])).msg.target, 3, "aliado seleccionado")
	pc.select(2, _ctx(1000.0, [ally, enemy]))
	pc.cast_lock[1] = 0.0
	eq(pc.try_cast(1, _ctx(3000.0, [ally, enemy])).msg.target, 1, "con un enemigo seleccionado, curás a vos")
	var far_ally := _unit(3, "red", 0, 80)
	pc.select(3, _ctx(1000.0, [far_ally]))
	pc.cast_lock[1] = 0.0
	check(pc.try_cast(1, _ctx(4000.0, [far_ally])).error.contains("Fuera de alcance"), "aliado lejos")


func test_self_spells_need_no_target() -> void:
	var pc := _pc("mage")
	var r := pc.try_cast(2, _ctx(1000.0, []))  # nova
	eq(r.msg.target, -1, "sin objetivo")
	near(r.msg.ax, 0.0, 0.001, "centrada en vos")
	eq(r.error, "", "sin error")


func test_direction_spells_use_facing_or_the_target() -> void:
	var pc := _pc("mage")
	var r := pc.try_cast(4, _ctx(1000.0, [], {"fwd": Vector2(1, 0)}))  # blink
	check(r.msg.ax > 5.0 and absf(r.msg.az) < 0.01, "traslación hacia donde mirás")
	eq(r.aim_dir.normalized().is_equal_approx(Vector2(1, 0)), true, "dirección para la predicción")
	# Blink and Disengage follow your facing even with an enemy selected behind you (fleeing).
	var behind := _unit(2, "blue", -8, 0)
	var mage := _pc("mage")
	mage.select(2, _ctx(1000.0, [behind], {"fwd": Vector2(1, 0)}))
	var b := mage.try_cast(4, _ctx(1000.0, [behind], {"fwd": Vector2(1, 0)}))
	check(b.msg.ax > 5.0, "la traslación va hacia adelante aunque el objetivo esté atrás")
	check(b.aim_dir.x > 0.0, "la predicción también va hacia adelante")
	var hunter := _pc("hunter")
	var ahead := _unit(2, "blue", 8, 0)
	hunter.select(2, _ctx(1000.0, [ahead], {"fwd": Vector2(0, 1)}))
	var dis := hunter.try_cast(4, _ctx(1000.0, [ahead], {"fwd": Vector2(0, 1)}))  # disengage
	check(dis.msg.az > 5.0 and absf(dis.msg.ax) < 0.01, "retirada: salto hacia atrás según tu frente, no según el objetivo")
	hunter = _pc("hunter")
	var e := _unit(2, "blue", 0, 10)
	hunter.select(2, _ctx(1000.0, [e]))
	var v := hunter.try_cast(6, _ctx(1000.0, [e]))  # volley
	near(v.msg.az, 10.0, 0.5, "la andanada sale hacia el objetivo seleccionado")


func test_ground_spells_enter_placement_mode_and_confirm_with_the_cursor_point() -> void:
	var pc := _pc("mage")
	pc.ready_at[6] = 0.0
	var r := pc.try_cast(6, _ctx(1000.0, []))
	check(r.pending_ground, "meteoros: espera clic")
	eq(r.msg, {}, "todavía no lanza")
	eq(pc.pending_ground, 6, "modo colocar")
	var c := pc.confirm_ground(Vector2(0, 8), _ctx(1100.0, []))
	eq(c.msg.slot, 6, "lanza el slot")
	near(c.msg.az, 8.0, 0.01, "en el punto del cursor")
	eq(pc.pending_ground, -1, "sale del modo")
	pc.try_cast(6, _ctx(1500.0, []))
	pc.cancel_ground()
	eq(pc.pending_ground, -1, "cancelar")
	pc.cast_lock[6] = 0.0
	pc.try_cast(6, _ctx(2500.0, []))
	var far := pc.confirm_ground(Vector2(0, 80), _ctx(2600.0, []))
	check(far.msg.az <= GameData.ability("mage", 6).range + 0.01, "el punto se limita al alcance (%s)" % far.msg.az)


func test_auto_attack_toggle_for_melee_and_hunter_but_not_casters() -> void:
	var w := _pc("warrior")
	var e := _unit(2, "blue", 0, 2)
	eq(w.try_cast(0, _ctx(1000.0, [_unit(2, "blue", 0, -2)])).error, "No tenés objetivo", "sin objetivo (enemigo a la espalda)")
	w.select(2, _ctx(1000.0, [e]))
	var r := w.try_cast(0, _ctx(1000.0, [e]))
	eq(r.auto, "start", "enciende")
	r = w.try_cast(0, _ctx(1500.0, [e], {"auto_on": true}))
	eq(r.auto, "stop", "apaga")
	var m := _pc("mage")
	m.select(2, _ctx(1000.0, [e]))
	var mr := m.try_cast(0, _ctx(1000.0, [e]))  # fireball: a normal spell for casters
	eq(mr.auto, "", "el mago no tiene auto-ataque")
	eq(mr.msg.slot, 0, "es un hechizo común")


func test_right_click_on_enemy_selects_and_starts_auto_for_melee_only() -> void:
	var e := _unit(2, "blue", 0, 3)
	var w := _pc("warrior")
	var r := w.right_click_unit(2, _ctx(1000.0, [e]))
	eq(w.target, 2, "selecciona")
	eq(r.auto, "start", "inicia auto-ataque")
	var m := _pc("mage")
	r = m.right_click_unit(2, _ctx(1000.0, [e]))
	eq(m.target, 2, "el mago también selecciona")
	eq(r.auto, "", "pero no ataca solo")
	var ally := _unit(3, "red", 2, 0)
	r = w.right_click_unit(3, _ctx(1000.0, [ally]))
	eq(r.auto, "stop", "clic derecho en un aliado: lo selecciona y detiene el ataque")
	eq(w.target, 3, "aliado seleccionado")


func test_tab_cycles_hostiles_and_escape_clears() -> void:
	var pc := _pc("mage")
	var a := _unit(2, "blue", 0, 10)
	var b := _unit(3, "blue", 8, 0)
	var ctx := _ctx(1000.0, [a, b])
	check(pc.cycle_target(ctx), "tab elige")
	eq(pc.target, 2, "primero el de enfrente")
	pc.cycle_target(ctx)
	eq(pc.target, 3, "después el siguiente")
	pc.clear_target()
	eq(pc.target, -1, "Esc limpia")


func test_cooldown_and_queue_still_work() -> void:
	var pc := _pc("mage")
	var e := _unit(2, "blue", 0, 12)
	pc.select(2, _ctx(1000.0, [e]))
	pc.sync_cooldowns([0, 6000, 0, 0, 0, 0, 0], 1000.0)
	check(pc.try_cast(1, _ctx(1000.0, [e])).error.contains("faltan"), "avisa el tiempo")
	pc.sync_cooldowns([0, 300, 0, 0, 0, 0, 0], 1000.0)
	eq(pc.try_cast(1, _ctx(1000.0, [e])).msg, {}, "todavía no")
	eq(pc.poll_queue(1280.0), 1, "se lanza sola al estar lista")


func test_no_casting_outside_fight_or_when_dead() -> void:
	var pc := _pc("mage")
	var e := _unit(2, "blue", 0, 12)
	pc.select(2, _ctx(1000.0, [e]))
	eq(pc.try_cast(1, _ctx(1000.0, [e], {"phase": "between"})).msg, {}, "fuera de pelea")
	eq(pc.try_cast(1, _ctx(1000.0, [e], {"alive": false})).msg, {}, "muerto")


func test_buffs_can_be_cast_during_prep() -> void:
	var pc := _pc("priest")
	var r := pc.try_cast(2, _ctx(1000.0, [], {"phase": "prep"}))  # power word: shield
	eq(r.msg.slot, 2, "escudo en la sala de preparación")
	pc.cast_lock[1] = 0.0
	eq(pc.try_cast(1, _ctx(2000.0, [], {"phase": "prep"})).msg, {}, "una curación común no")


# ---------------------------------------------------------------- no target: auto-select like WoW

func test_hostile_spell_without_target_picks_nearest_enemy_in_front() -> void:
	var pc := _pc("mage")
	var near_e := _unit(2, "blue", 1, 8)
	var far_e := _unit(3, "blue", 0, 15)
	var behind := _unit(4, "blue", 0, -3)
	var r := pc.try_cast(0, _ctx(1000.0, [far_e, behind, near_e]))
	eq(r.msg.get("target", -1), 2, "dispara al más cercano de adelante")
	eq(pc.target, 2, "y lo deja seleccionado")


func test_melee_ability_without_target_selects_within_small_radius_and_starts_auto() -> void:
	var pc := _pc("rogue")
	var e := _unit(2, "blue", 0, 3)
	var r := pc.try_cast(1, _ctx(1000.0, [e]))   # eviscerate
	eq(r.msg.get("target", -1), 2, "eviscerar sin objetivo elige al enemigo cercano")
	eq(r.auto, "start", "y empieza el auto-ataque")
	var pc2 := _pc("rogue")
	var far_e := _unit(2, "blue", 0, 14)
	check(pc2.try_cast(1, _ctx(1000.0, [far_e])).msg.is_empty(), "lejos (fuera del radio chico) no elige")
	var pc3 := _pc("rogue")
	eq(pc3.try_cast(0, _ctx(1000.0, [e])).auto, "start", "el botón de auto-ataque sin objetivo también elige y empieza")
	eq(pc3.target, 2, "objetivo elegido")


func test_ability_on_a_target_starts_auto_attack_for_auto_classes() -> void:
	var pc := _pc("hunter")
	var e := _unit(2, "blue", 0, 12)
	pc.select(2, _ctx(1000.0, [e]))
	eq(pc.try_cast(1, _ctx(1000.0, [e])).auto, "start", "el disparo certero arranca el auto-ataque del cazador")
	var m := _pc("mage")
	m.select(2, _ctx(1000.0, [e]))
	eq(m.try_cast(1, _ctx(1000.0, [e])).auto, "", "el mago no tiene auto")


func test_heal_without_target_picks_most_injured_ally_in_range_else_self() -> void:
	var pc := _pc("priest")
	var a := _unit(3, "red", 4, 0)
	a["hp"] = 0.4
	var b := _unit(4, "red", -3, 0)
	b["hp"] = 0.8
	eq(pc.try_cast(1, _ctx(1000.0, [a, b])).msg.target, 3, "cura al aliado más herido")
	var pc2 := _pc("priest")
	var healthy := _unit(3, "red", 4, 0)
	healthy["hp"] = 1.0
	eq(pc2.try_cast(1, _ctx(1000.0, [healthy])).msg.target, 1, "nadie herido: a vos")


# ---------------------------------------------------------------- casting is never cancelled by key presses

func _casting(left: float, total := 1400.0, slot := 1) -> Dictionary:
	return {"slot": slot, "left": left, "total": total}


func test_repeating_the_spell_being_cast_is_ignored_silently() -> void:
	var pc := _pc("mage")
	var e := _unit(2, "blue", 0, 12)
	pc.select(2, _ctx(1000.0, [e]))
	for i in 10:
		var r := pc.try_cast(1, _ctx(1000.0 + i * 50.0, [e], {"cast": _casting(1200.0 - i * 50.0)}))
		check(r.msg.is_empty() and r.error == "", "pulsación %d ignorada sin error" % i)
	check(pc.queued.is_empty(), "no se encola la misma")


func test_other_spell_mid_cast_is_ignored_with_one_message_per_cast() -> void:
	var pc := _pc("mage")
	var e := _unit(2, "blue", 0, 12)
	pc.select(2, _ctx(1000.0, [e]))
	var first := pc.try_cast(0, _ctx(1000.0, [e], {"cast": _casting(1200.0)}))
	eq(first.error, "Ya estás lanzando", "primer aviso")
	check(first.msg.is_empty(), "no se manda")
	var second := pc.try_cast(0, _ctx(1100.0, [e], {"cast": _casting(1100.0)}))
	eq(second.error, "", "el aviso sale una sola vez por lanzamiento")
	var third := pc.try_cast(0, _ctx(5000.0, [e], {"cast": _casting(1200.0)}))
	check(third.msg.is_empty(), "otro lanzamiento posterior también se ignora")


func test_spell_in_the_queue_window_is_queued_and_fires_after_the_cast() -> void:
	var pc := _pc("mage")
	var e := _unit(2, "blue", 0, 12)
	pc.select(2, _ctx(1000.0, [e]))
	var r := pc.try_cast(0, _ctx(1000.0, [e], {"cast": _casting(300.0)}))
	check(r.msg.is_empty() and r.error == "", "dentro de la ventana: se encola sin error")
	eq(pc.queued.get("slot", -1), 0, "encolada")
	eq(pc.poll_queue(1100.0, true), -1, "mientras todavía lanza no sale")
	eq(pc.poll_queue(1320.0, false), 0, "al terminar el lanzamiento sale sola")


# ---------------------------------------------------------------- locomotion blend

func test_loco_blend_forward_back_and_strafe() -> void:
	var f := LocoBlend.blend_xy(Vector2(0, 7.0), 0.0, 7.0)   # facing +z, moving +z
	near(f.y, 1.0, 1e-6, "corre hacia adelante")
	near(f.x, 0.0, 1e-6, "sin paso lateral")
	var b := LocoBlend.blend_xy(Vector2(0, -7.0), 0.0, 7.0)
	near(b.y, -LocoBlend.BACK_SCALE, 1e-6, "retrocede (tope más bajo)")
	var r := LocoBlend.blend_xy(Vector2(7.0, 0), 0.0, 7.0)   # facing +z: +x is to the right
	check(r.x > 0.99 and absf(r.y) < 1e-6, "paso lateral derecho")
	var l := LocoBlend.blend_xy(Vector2(-7.0, 0), 0.0, 7.0)
	check(l.x < -0.99, "paso lateral izquierdo")
	var rot := LocoBlend.blend_xy(Vector2(7.0, 0), PI / 2, 7.0)  # facing +x: moving +x is forward
	near(rot.y, 1.0, 1e-5, "depende del rumbo")
	eq(LocoBlend.blend_xy(Vector2(0.1, 0.1), 0.0, 7.0), Vector2.ZERO, "quieto = reposo")


func test_foot_sync_scales_with_ground_speed() -> void:
	near(LocoBlend.foot_sync(7.0, 7.0), 1.25, 1e-6, "a velocidad de clase")
	check(LocoBlend.foot_sync(3.5, 7.0) < LocoBlend.foot_sync(7.0, 7.0), "más lento, el ciclo va más lento")
	eq(LocoBlend.foot_sync(0.0, 7.0), 1.0, "quieto")
	eq(LocoBlend.foot_sync(30.0, 7.0), 1.7, "tope")
