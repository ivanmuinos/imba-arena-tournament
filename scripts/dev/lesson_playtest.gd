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
	if main.args.has("valley"):
		await _run_valley()
		return
	if str(main.args.get("lesson", "moverse")) == "objetivo":
		await _run_objetivo()
		return
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
	_check(labels.has("Siguiente lección"), "y seguir con la que viene: %s" % str(labels))
	_check(ov._card.face != null, "Tizón está en la tarjeta")
	_check(absf(ov._card.get_global_rect().get_center().x - 640.0) < 40.0, "la tarjeta del final va al centro (%s)" % str(ov._card.get_global_rect()))
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


## The second lesson with a fight in it: real clicks on the crates, the real basic attack, and on to the next lesson.
func _run_objetivo() -> void:
	await _find_overlay()
	_check(ov is LessonOverlay and (ov.flow as LessonFlow).id == "objetivo", "la lección de objetivo está activa")
	if ov == null:
		return finish()
	mv.capture_mouse = true
	await _wait(0.5)
	_motion(Vector2(640, 380))
	_check(await _click_button_named("Continuar"), "botón Continuar")
	_check(_step_id() == "pick", "pasa a elegir objetivo")
	var crates := _enemies()
	_check(crates.size() == 3, "hay tres cajas a la vista (%d)" % crates.size())
	if crates.is_empty():
		return finish()
	await _shot("crates")
	await _bring_on_screen(crates[0])
	await _click_unit(crates[0], MOUSE_BUTTON_LEFT)
	_check(mv.controller.target >= 0, "un clic elige una caja")
	await _tap(KEY_TAB)
	await _wait(0.4)
	_check(_step_id() == "hit", "clic y Tab completan el paso (%s)" % _step_id())
	for n in 3:
		var id := _nearest_enemy()
		if id < 0:
			break
		await _bring_on_screen(id)
		await _click_unit(id, MOUSE_BUTTON_LEFT)
		for i in 30:
			if not mv.views.has(id) or not (mv.views[id] as UnitView).is_alive() or not (mv.views[id] as UnitView).shown:
				break
			await _tap(KEY_1)
			await _wait(0.3)
	await _wait(0.6)
	_check(_step_id() == "done", "romper las tres cajas termina la lección (%s)" % _step_id())
	await _wait(1.2)
	await _shot("result")
	_check(AcademyStore.shared().medal("objetivo") >= AcademyMedals.BRONZE, "queda guardada una medalla")
	_check(await _click_button_named("Siguiente lección"), "botón Siguiente lección")
	await _wait(0.8)
	ov = null
	await _find_overlay()
	_check(ov != null and (ov.flow as LessonFlow).id == AcademyCatalog.after("objetivo"), "Siguiente abre la lección que sigue")
	await _wait(1.0)
	await _shot("next")
	await _click_button_named("Salir")
	await _wait(0.8)
	_check(main._menu.nav.current == "academy", "Salir vuelve a la Academia")
	await _wait(0.6)
	await _shot("academy")
	finish()


## The valley: Tizón offers a quest, the card and the minimap follow it, handing it in gives the medal and the next one.
## The buttons are real clicks; the walking is done by moving the champion on the server, to keep it short.
func _run_valley() -> void:
	for i in 200:
		mv = main._match
		if mv != null and mv.last_state.get("phase", "") == "fight" and not mv.me.is_empty():
			break
		await _wait(0.25)
	_check(mv != null and mv.world.map.id == GameMap.VALLEY_ID, "el valle está abierto")
	if mv == null:
		return finish()
	var quests: ValleyQuests = null
	var hud_v: ValleyHud = null
	for c in mv.get_children():
		if c is ValleyQuests:
			quests = c
		if c is ValleyHud:
			hud_v = c
	_check(quests != null and hud_v != null, "con su minimapa y sus misiones")
	if quests == null:
		return finish()
	await _wait(1.0)
	_check(quests.mark.text == "!", "Tizón tiene un «!» (%s)" % quests.mark.text)
	_check(hud_v.zone_id == "camp" and hud_v.minimap.place.contains("Campamento"), "el minimapa dice dónde estás (%s)" % hud_v.minimap.place)
	_check(quests.offer != null and quests.offered == "moverse", "al llegar, ofrece la primera misión (%s)" % quests.offered)
	await _shot("offer")
	var accept: Button = null
	for b in quests.offer.buttons.get_children():
		if (b as Button).text == "Aceptar":
			accept = b
	await _click_control(accept)
	await _wait(0.5)
	ov = quests.overlay
	_check(ov != null and _step_id() == "walk", "Aceptar empieza la misión")
	if ov == null:
		return finish()
	_check(quests.mark.text == "?", "Tizón pasa a esperar con un «?»")
	_check(hud_v.minimap.goal.distance_to(Vector2(-8, 45)) < 0.1, "el minimapa marca la primera placa (%s)" % str(hud_v.minimap.goal))
	await _shot("quest")
	var hero: ArenaUnit = main.server.game.unit_for_peer(main.client.peer_id)
	for plate in [7, 8]:
		await _hop(hero, Vector2(mv.world.map.plates[plate].x, mv.world.map.plates[plate].z))
	_check(_step_id() == "look", "las placas avanzan la misión (%s)" % _step_id())
	ov.push("cam_rmb")
	await _hop(hero, Vector2(mv.world.map.plates[9].x, mv.world.map.plates[9].z))
	ov.push("jumped")
	await _hop(hero, Vector2(mv.world.map.plates[11].x, mv.world.map.plates[11].z))
	_check(_step_id() == "back", "queda volver con Tizón (%s)" % _step_id())
	_check(hud_v.minimap.goal == GameMap.TIZON_AT, "y el minimapa lo marca a él")
	await _hop(hero, GameMap.TIZON_AT + Vector2(1.5, 2.0))
	await _wait(1.2)
	_check(_step_id() == "done", "al llegar se entrega (%s)" % _step_id())
	_check(AcademyStore.shared().medal("moverse") >= AcademyMedals.BRONZE, "con su medalla guardada")
	await _shot("result")
	_check(await _click_button_named("Siguiente misión"), "botón Siguiente misión")
	await _wait(0.8)
	ov = quests.overlay
	_check(ov != null and (ov.flow as LessonFlow).id == "camara", "sigue la misión de la cámara")
	await _shot("next")
	_check(await _click_button_named("Abandonar"), "botón Abandonar")
	await _wait(0.5)
	_check(quests.overlay == null and main._state == "match", "abandonar deja el valle abierto")
	await _hop(hero, Vector2(0, 30))
	await _wait(0.5)
	_check(hud_v.zone_id == "" and quests.mark.text == "!", "lejos de él, Tizón vuelve a tener un «!»")
	await _hop(hero, GameMap.TIZON_AT + Vector2(1.5, 2.0))
	await _wait(0.8)
	_check(quests.offer != null and quests.offered == "camara", "y al volver ofrece la que quedó pendiente (%s)" % quests.offered)
	finish()


## Puts the champion somewhere on the server and waits for the client to see it there.
func _hop(hero: ArenaUnit, to: Vector2) -> void:
	hero.x = to.x
	hero.z = to.y
	mv.predictor.m.x = to.x
	mv.predictor.m.z = to.y
	await _wait(0.5)


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
