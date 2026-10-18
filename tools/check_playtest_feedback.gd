extends SceneTree
## Real-renderer regression check and screenshots. Run with:
## godot --path . --resolution 1600x900 --script res://tools/check_playtest_feedback.gd -- --offline --mode=3 --map=tomb --cls=mage --no-capture --gfx=media

var failures := 0


func check(ok: bool, message: String) -> void:
	print("FEEDBACK ", "PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screens/" + file + ".png")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await create_timer(2.0).timeout
	var view: MatchView = main._match
	check(view != null, "offline match starts")
	if view == null:
		quit(1)
		return
	var hud := view.hud
	hud._slots[6].root.mouse_entered.emit()
	await create_timer(0.3).timeout
	check(hud._ability_tip.visible and hud._ability_tip._usage.text.contains("clic izquierdo"), "hover shows ground-cast instructions")
	var bounds := Rect2(Vector2.ZERO, hud._root.size)
	check(bounds.encloses(hud._ability_tip.get_rect()), "tooltip fits scaled HUD")
	await shot("feedback_tooltip")
	hud._slots[6].root.mouse_exited.emit()
	check(not hud._ability_tip.visible, "tooltip closes on exit")
	# Authoritative death snapshot, then normal frame/input path; no production debug override.
	var unit: ArenaUnit = main.server.game.units.filter(func(u): return u.id == view.my_id)[0]
	unit.alive = false
	unit.hp = 0
	await create_timer(0.5).timeout
	check(hud._spirit.visible and view._spectating >= 0, "death enables spirit view and ally camera")
	var previous := view._spectating
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await process_frame
	check(view._spectating != previous, "Tab cycles living allies")
	await shot("feedback_spirit")
	unit.alive = true
	unit.hp = float(GameData.classes[unit.cls].hp)
	await create_timer(0.5).timeout
	check(not hud._spirit.visible and view._spectating == -1, "respawn clears spirit and spectator state")
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
