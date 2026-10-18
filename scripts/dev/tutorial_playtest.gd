class_name TutorialPlaytest
extends Playtest
## Real-input playtest of the guided tutorial (`--playtest --tutorial-test --practice=tutorial`): walks the first steps with real keys
## and mouse, then skips to the end and leaves through the card's own button.

var ov: TutorialOverlay


func _step_id() -> String:
	return str(ov.flow.current().id)


func _click_control(c: Control) -> void:
	var r := Rect2(c.global_position, c.size * mv.hud.ui_scale)
	var p := r.get_center()
	_motion(p)
	await _wait(0.2)  # let the GUI register the hover before pressing (synthetic input is otherwise sometimes dropped)
	_button(MOUSE_BUTTON_LEFT, true, p)
	await _wait(0.06)
	_button(MOUSE_BUTTON_LEFT, false)
	await _wait(0.2)


func _click_button_named(text: String) -> bool:
	for b in ov._buttons.get_children():
		if b is Button and (b as Button).text == text:
			await _click_control(b)
			return true
	return false


func _wheel(up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = _mouse
	Input.parse_input_event(e)
	await _wait(0.1)


func run(p_main: Node, cls: String, prefix: String, p_spec := "") -> void:
	main = p_main
	spec = GameData.normalize_spec(cls, p_spec)
	shot_prefix = prefix
	print("PLAYTEST start tutorial class=", cls)
	for i in 400:
		mv = main._match
		if mv != null and mv.last_state.get("phase", "") == "fight" and not mv.me.is_empty():
			for c in mv.get_children():
				if c is TutorialOverlay:
					ov = c
			if ov != null:
				break
		await _wait(0.25)
	_check(ov != null, "el tutorial está activo sobre la arena de práctica")
	if ov == null:
		return finish()
	mv.capture_mouse = true
	await _wait(0.5)
	_motion(Vector2(640, 380))
	_check(_step_id() == "welcome", "empieza en la bienvenida")
	await _shot("welcome")
	_check(await _click_button_named("Continuar"), "botón Continuar")
	_check(_step_id() == "move", "Continuar avanza a moverse")
	# a key that does nothing for this step must not advance it
	await _tap(KEY_TAB)
	_check(_step_id() == "move", "una acción que no se pidió no avanza el paso")
	_key(KEY_W, true)
	await _wait(1.3)
	_key(KEY_W, false)
	_check(ov.flow.current().objectives[0].done, "caminar tilda el objetivo de moverse")
	await _tap(KEY_SPACE)
	await _wait(0.2)
	_check(_step_id() == "camera", "saltar completa el paso de moverse")
	await _shot("camera_step")
	_button(MOUSE_BUTTON_RIGHT, true, Vector2(640, 380))
	await _drag(Vector2(-80, 0), 8)
	_button(MOUSE_BUTTON_RIGHT, false)
	await _wait(0.1)
	_button(MOUSE_BUTTON_LEFT, true, Vector2(640, 380))
	await _drag(Vector2(60, 0), 8)
	_button(MOUSE_BUTTON_LEFT, false)
	await _wheel(true)
	await _wait(0.2)
	_check(_step_id() == "target", "clic derecho arrastrando, clic izquierdo arrastrando y rueda completan la cámara")
	var id := _clear_enemy()
	if id >= 0 and await _bring_on_screen(id):
		await _click_unit(id, MOUSE_BUTTON_LEFT)
	await _tap(KEY_TAB)
	await _wait(0.2)
	_check(ov.flow.current().objectives[0].done or _step_id() != "target", "clic sobre un muñeco enemigo tilda el objetivo")
	_check(_step_id() != "target", "con clic y Tab el paso de objetivo se completa (%s)" % _step_id())
	await _shot("after_target")
	# skip the rest with the card's own button and leave from the last step
	var guard := 0
	while _step_id() != "done" and guard < 30:
		guard += 1
		var before := ov.flow.index
		if not await _click_button_named("Continuar"):
			await _click_button_named("Saltar paso")
		if ov.flow.index == before:
			await _wait(0.3)
	_check(_step_id() == "done", "se llega al paso final (%s)" % _step_id())
	await _shot("done")
	var labels: Array = ov._buttons.get_children().map(func(b): return (b as Button).text)
	_check(labels.has("Arena de práctica") and labels.has("Contra bots") and labels.has("Menú"), "el final ofrece las tres salidas: %s" % str(labels))
	await _click_button_named("Menú")
	await _wait(0.8)
	_check(main._state == "menu", "Menú vuelve al menú principal")
	finish()
