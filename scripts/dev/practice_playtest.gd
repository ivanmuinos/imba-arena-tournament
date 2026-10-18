class_name PracticePlaytest
extends TutorialPlaytest
## Real-input playtest of the practice arena (`--playtest --practice-test --practice`): cast on a dummy, watch the DPS meter fill,
## reset it, toggle no-cooldowns, ready the ultimate, switch champion from the dropdown and leave with the panel's button.


func _find_button(text: String) -> Control:
	var panel := mv.practice_panel
	for b in panel.find_children("*", "Button", true, false):
		if (b as Button).text == text and b.is_visible_in_tree():
			return b
	return null


func run(p_main: Node, cls: String, prefix: String, p_spec := "") -> void:
	main = p_main
	spec = GameData.normalize_spec(cls, p_spec)
	shot_prefix = prefix
	print("PLAYTEST start practice class=", cls)
	for i in 400:
		mv = main._match
		if mv != null and mv.last_state.get("phase", "") == "fight" and not mv.me.is_empty() and mv.practice_panel != null:
			break
		await _wait(0.25)
	_check(mv != null and mv.practice_panel != null, "la arena de práctica muestra el panel")
	if mv == null or mv.practice_panel == null:
		return finish()
	mv.capture_mouse = true
	await _wait(0.5)
	var panel := mv.practice_panel
	var id := _clear_enemy()
	if await _bring_on_screen(id):
		await _click_unit(id, MOUSE_BUTTON_LEFT)
	if mv.controller.target < 0 or mv.views[mv.controller.target].entry.team == mv.my_team:
		await _tap(KEY_TAB)
	_check(mv.controller.target >= 0, "se elige un muñeco")
	for i in 3:
		await _tap(KEY_1)
		await _wait(0.8)
		if int(panel._total.text.replace(" ", "")) > 0:
			break
	await _wait(0.6)
	var total := int(panel._total.text.replace(" ", ""))
	_check(total > 0, "el medidor sumó daño (%d)" % total)
	_check(panel._cells[0][0].text != "", "la tabla muestra la primera habilidad: %s" % panel._cells[0][0].text)
	await _shot("meter")
	await _click_control(_find_button("Reiniciar"))
	await _wait(0.6)
	_check(int(panel._total.text.replace(" ", "")) == 0, "Reiniciar pone el medidor en cero")
	await _click_control(panel._nocd)
	await _wait(1.2)
	_check(panel._nocd.button_pressed, "la casilla queda marcada tras la respuesta del servidor")
	_check(bool(mv.last_state.get("you", {}).get("nocd", false)), "el modo sin cooldowns se activó en el servidor")
	await _click_control(panel._nocd)
	await _wait(1.2)
	_check(not bool(mv.last_state.get("you", {}).get("nocd", false)), "y se apaga")
	await _click_control(_find_button("Definitiva lista"))
	await _wait(0.6)
	_check(int(mv.last_state.get("you", {}).get("ult", 0)) >= 100, "Definitiva lista carga la definitiva")
	var other := "warrior" if cls != "warrior" else "rogue"
	var idx := -1
	for i in panel._cls_pick.item_count:
		if panel._cls_pick.get_item_metadata(i) == other:
			idx = i
	var old_mv := mv
	panel._cls_pick.select(idx)
	panel._cls_pick.item_selected.emit(idx)
	await _wait(2.5)
	mv = main._match
	_check(mv != null and mv != old_mv and mv.my_cls == other and mv.practice, "cambiar de clase en el desplegable reinicia la práctica con %s" % other)
	await _shot("switched")
	await _wait(0.5)
	await _click_control(_find_button("Volver al menú"))
	await _wait(0.8)
	_check(main._state == "menu", "Volver al menú sale de la práctica")
	finish()
