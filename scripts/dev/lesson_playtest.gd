class_name LessonPlaytest
extends TutorialPlaytest
## Real-input playtest of the pilot lesson (`--playtest --lesson-test --lesson=moverse`): walks over the plates with real keys and
## mouse, checks the door, the pause under the Esc menu and that Repetir starts over.


func _me_pos() -> Vector2:
	return Vector2(mv.predictor.m.x, mv.predictor.m.z)


## Holds a key until the player's position on one axis gets close to `goal`.
func _walk(code: int, axis: String, goal: float, tolerance := 0.8) -> void:
	_key(code, true)
	var guard := 0
	while guard < 400:
		guard += 1
		var p := _me_pos()
		if absf((p.x if axis == "x" else p.y) - goal) <= tolerance:
			break
		await _wait(0.02)
	_key(code, false)
	await _wait(0.25)


func run(p_main: Node, cls: String, prefix: String, p_spec := "") -> void:
	main = p_main
	spec = GameData.normalize_spec(cls, p_spec)
	shot_prefix = prefix
	print("PLAYTEST start lesson class=", cls)
	await _find_overlay()
	_check(ov is LessonOverlay, "la lección está activa en su propia arena")
	if ov == null:
		return finish()
	mv.capture_mouse = true
	await _wait(0.5)
	_motion(Vector2(640, 380))
	_check(mv.world.map.id == GameMap.ACADEMY_ID, "es el mapa de la Academia")
	_check(mv.my_cls == cls and mv.my_spec == spec, "con el campeón pedido (%s %s)" % [mv.my_cls, mv.my_spec])
	_check(_me_pos().distance_to(Vector2(0, 48)) < 1.5, "arranca donde dice el escenario (%s)" % str(_me_pos()))
	await _shot("intro")
	_check(await _click_button_named("Continuar"), "botón Continuar")
	_check(_step_id() == "walk", "pasa a caminar")
	await _shot("walk")
	await _walk(KEY_Q, "x", -10.0)
	await _walk(KEY_W, "y", 45.0)
	await _wait(0.3)
	_check(_step_id() == "strafe", "la placa de la izquierda completa el paso (%s en %s)" % [_step_id(), str(_me_pos())])
	await _shot("strafe")
	await _walk(KEY_E, "x", 10.0)
	await _wait(0.3)
	_check(_step_id() == "look", "la placa de la derecha completa el paso (%s en %s)" % [_step_id(), str(_me_pos())])
	_check(not mv.world.map.door_open(0), "la puerta sigue cerrada")
	await _esc_pauses()
	_button(MOUSE_BUTTON_RIGHT, true, Vector2(640, 380))
	await _drag(Vector2(40, 0), 8)
	await _drag(Vector2(-40, 0), 8)
	_button(MOUSE_BUTTON_RIGHT, false)
	await _wait(0.2)
	mv._face = PI
	mv.cam.yaw = PI
	await _walk(KEY_Q, "x", 0.0)
	await _walk(KEY_W, "y", 39.0)
	await _wait(0.3)
	_check(_step_id() == "cross", "la placa frente a la puerta completa el paso (%s en %s)" % [_step_id(), str(_me_pos())])
	await _wait(1.5)
	_check(mv.world.map.door_open(0), "el cliente ve la puerta abierta")
	await _shot("door_open")
	await _tap(KEY_SPACE)
	await _walk(KEY_W, "y", 33.0)
	await _wait(0.4)
	_check(_step_id() == "done", "cruzar y saltar termina la lección (%s en %s)" % [_step_id(), str(_me_pos())])
	await _shot("done")
	var labels: Array = ov._buttons.get_children().map(func(b): return (b as Button).text)
	_check(labels.has("Repetir") and labels.has("Academia"), "el final ofrece repetir o volver: %s" % str(labels))
	_check((ov.flow as LessonFlow).skipped == 0, "no se salteó nada")
	_check((ov.flow as LessonFlow).active_ms > 0.0, "el reloj corrió")
	_check(AcademyStore.shared().medal("moverse") >= AcademyMedals.BRONZE, "queda guardada una medalla (%d)" % AcademyStore.shared().medal("moverse"))
	_check(absf((ov as LessonOverlay).last_hp_pct - 1.0) < 0.01, "sin recibir daño terminás con toda la vida (%.2f)" % (ov as LessonOverlay).last_hp_pct)
	_check(ov._card._body.text.contains("Medalla de"), "el final dice qué medalla ganaste: %s" % ov._card._body.text)
	await _click_button_named("Repetir")
	await _wait(0.5)
	ov = null
	await _find_overlay()
	_check(ov != null and _step_id() == "intro", "Repetir vuelve a empezar")
	_check(_me_pos().distance_to(Vector2(0, 48)) < 1.5, "desde el principio")
	_check(not mv.world.map.door_open(0), "con la puerta cerrada otra vez")
	await _click_button_named("Salir")
	await _wait(0.8)
	_check(main._state == "menu", "Salir vuelve al menú")
	_check(main._menu.nav.current == "academy", "a la Academia (%s)" % main._menu.nav.current)
	var academy: MAcademy = main._menu._views.academy
	_check(academy.medal_shown("moverse") >= AcademyMedals.BRONZE, "con la medalla que ganaste")
	var before: int = AcademyStore.shared().plays("moverse")
	await _click_control(academy.play_button("moverse"))
	await _wait(0.5)
	ov = null
	await _find_overlay()
	_check(ov != null and _step_id() == "intro", "desde la Academia se vuelve a jugar con un clic")
	await _click_button_named("Salir")
	await _wait(0.8)
	_check(AcademyStore.shared().plays("moverse") == before, "salir a mitad no cuenta como intento")
	finish()


func _find_overlay() -> void:
	for i in 400:
		mv = main._match
		if mv != null and mv.last_state.get("phase", "") == "fight" and not mv.me.is_empty():
			for c in mv.get_children():
				if c is LessonOverlay:
					ov = c
			if ov != null:
				return
		await _wait(0.25)


func _esc_pauses() -> void:
	await _tap(KEY_ESCAPE)
	await _wait(0.3)
	_check(mv.game_menu.visible, "Esc abre el menú")
	var t0: float = float(main.server.sim_now)
	await _wait(0.6)
	_check(is_equal_approx(float(main.server.sim_now), t0), "con el menú abierto la lección no corre")
	await _tap(KEY_ESCAPE)
	await _wait(0.3)
	_check(not mv.game_menu.visible, "Esc lo cierra")
	var t1: float = float(main.server.sim_now)
	await _wait(0.3)
	_check(float(main.server.sim_now) > t1, "y la lección sigue")
	mv.capture_mouse = true
