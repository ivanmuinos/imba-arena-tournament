class_name Playtest
extends Node
## Automated playtest that drives the REAL game through Input.parse_input_event (mouse buttons, drags, motion, keys), the same
## path a human uses. Enabled with `--playtest` (needs a real window; run via tools/playtest.sh). Asserts on outcomes and
## prints "PLAYTEST ..." lines; exits 0 when everything passed.

var main: Node
var mv: MatchView
var fails: Array = []
var passes := 0
var shots := 0
var shot_prefix := "/tmp/playtest"
var _mouse := Vector2(640, 360)
var _keys_down := {}


func _check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("PLAYTEST ok   ", what)
	else:
		fails.append(what)
		print("PLAYTEST FAIL ", what)


func _abs(c: String) -> Array:
	return GameData.abilities(c, spec)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


# ---------------------------------------------------------------- raw input helpers

func _motion(pos: Vector2, rel := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = _button_mask()
	_mouse = pos
	Input.parse_input_event(e)


var _buttons := {}


func _button_mask() -> int:
	var m := 0
	if _buttons.get(MOUSE_BUTTON_LEFT, false): m |= MOUSE_BUTTON_MASK_LEFT
	if _buttons.get(MOUSE_BUTTON_RIGHT, false): m |= MOUSE_BUTTON_MASK_RIGHT
	return m


func _button(b: int, down: bool, pos := Vector2(-1, -1)) -> void:
	if pos.x >= 0:
		_mouse = pos
	_buttons[b] = down
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.position = _mouse
	e.global_position = _mouse
	e.button_mask = _button_mask()
	Input.parse_input_event(e)


func _key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	_keys_down[code] = down
	Input.parse_input_event(e)


func _tap(code: int) -> void:
	_key(code, true)
	await _wait(0.05)
	_key(code, false)
	await _wait(0.05)


func _drag(rel_total: Vector2, steps := 8, delay := 0.016) -> void:
	for i in steps:
		_motion(_mouse + rel_total / steps, rel_total / steps)
		await _wait(delay)


func _release_everything() -> void:
	for b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if _buttons.get(b, false):
			_button(b, false)
	for k in _keys_down.keys():
		if _keys_down[k]:
			_key(k, false)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s_%d_%s.png" % [shot_prefix, shots, tag]
	shots += 1
	get_viewport().get_texture().get_image().save_png(path)
	print("PLAYTEST shot ", path)


# ---------------------------------------------------------------- game queries

func _enemies() -> Array:
	var out := []
	for id in mv.views:
		var v: UnitView = mv.views[id]
		if v.entry.team != mv.my_team and v.shown and v.is_alive():
			out.append(id)
	return out


func _my_pos() -> Vector2:
	return Vector2(mv.predictor.m.x, mv.predictor.m.z)


func _enemy_hp_total() -> float:
	var t := 0.0
	for id in mv.views:
		var v: UnitView = mv.views[id]
		if v.entry.team != mv.my_team and not v.snap.is_empty():
			t += float(v.snap.hp)
	return t


func _nearest_enemy() -> int:
	var best := -1
	var bd := 1e9
	for id in _enemies():
		var d := _my_pos().distance_to(Vector2(mv.views[id].position.x, mv.views[id].position.z))
		if d < bd:
			bd = d
			best = id
	return best


## The visible enemy with no ally drawn over it (clicking an ally in front of an enemy selects the ally, as in WoW).
func _clear_enemy() -> int:
	var best := -1
	for id in _enemies():
		var sp := _screen_of(id)
		var covered := false
		for aid in mv.views:
			var a: UnitView = mv.views[aid]
			if aid != mv.my_id and a.entry.team == mv.my_team and a.shown and a.is_alive() and _screen_of(aid).distance_to(sp) < MatchView.PICK_RADIUS * 1.6:
				covered = true
		if not covered and _on_screen(sp):
			return id
		if best < 0:
			best = id
	return best


func _screen_of(id: int) -> Vector2:
	var v: UnitView = mv.views[id]
	return mv.cam.unproject_position(v.position + Vector3(0, 1.1, 0))


func _on_screen(p: Vector2) -> bool:
	var r := get_viewport().get_visible_rect()
	return r.grow(-60).has_point(p)


## Turns toward world point (x, z) with real mouselook: holds RMB, drags until the camera faces it, releases.
## Turns (real mouselook) until the unit is inside the screen; returns whether it is.
func _bring_on_screen(id: int) -> bool:
	for i in 5:
		if not mv.views.has(id) or not mv.views[id].is_alive():
			return false
		var sp := _screen_of(id)
		if _on_screen(sp) and not mv.cam.is_position_behind(mv.views[id].position + Vector3(0, 1.0, 0)):
			return true
		await _turn_to(mv.views[id].position.x, mv.views[id].position.z)
		await _wait(0.15)
	return false


## Clicks on unit `id` using its position at this very frame (enemies keep running, so stale coordinates miss).
var last_click := Vector2.ZERO
var _pick_ok_now := false
var spec := ""
var landed := 0   # hits by me (or absorbed on an enemy) seen in the fx stream


## True when the current target is the intended unit, or another hostile unit that overlaps the click (the picker takes the nearest).
func _picked_ok(id: int) -> bool:
	var t: int = mv.controller.target
	if t == id:
		return true
	if t < 0 or not mv.views.has(t):
		return false
	# another unit drawn over the click (an ally standing in front selects the ally, as in WoW) is fine
	return _screen_of(t).distance_to(last_click) <= MatchView.PICK_RADIUS * 1.5


func _click_unit(id: int, button: int) -> void:
	await get_tree().process_frame
	var sp := _screen_of(id)
	_motion(sp)
	last_click = sp
	_button(button, true, sp)  # same frame as the motion: the unit has not moved yet
	await get_tree().process_frame
	_button(button, false)
	await get_tree().process_frame
	_pick_ok_now = _picked_ok(id)  # judged right after the click, before the camera turns toward the target
	await _wait(0.2)


func _turn_to(x: float, z: float) -> void:
	_button(MOUSE_BUTTON_RIGHT, true, Vector2(640, 360))
	await _wait(0.03)
	for i in 30:
		var want := atan2(x - _my_pos().x, z - _my_pos().y)
		var diff := wrapf(want - mv.cam.yaw, -PI, PI)
		if absf(diff) < 0.06:
			break
		var rel_x := clampf(-diff / (0.0028 * SettingsStore.shared().get_value("sens")), -140.0, 140.0)
		_motion(_mouse + Vector2(rel_x, 0), Vector2(rel_x, 0))
		await _wait(0.03)
	_button(MOUSE_BUTTON_RIGHT, false)
	await _wait(0.05)


func _walk_toward(id: int, stop_dist: float, max_s: float) -> void:
	var t := 0.0
	_key(KEY_W, true)
	while t < max_s and mv.views.has(id) and mv.views[id].is_alive():
		var ep := Vector2(mv.views[id].position.x, mv.views[id].position.z)
		if _my_pos().distance_to(ep) <= stop_dist:
			break
		var want := atan2(ep.x - _my_pos().x, ep.y - _my_pos().y)
		if absf(wrapf(want - mv._face, -PI, PI)) > 0.35:
			_key(KEY_W, false)
			await _turn_to(ep.x, ep.y)
			_key(KEY_W, true)
		await _wait(0.1)
		t += 0.1
	_key(KEY_W, false)


# ---------------------------------------------------------------- the scenario

func run(p_main: Node, cls: String, prefix: String, p_spec := "") -> void:
	main = p_main
	spec = GameData.normalize_spec(cls, p_spec)
	shot_prefix = prefix
	print("PLAYTEST start class=", cls)
	# wait for the match view and the fight phase
	for i in 400:
		mv = main._match
		if mv != null and mv.last_state.get("phase", "") == "fight" and not mv.me.is_empty():
			break
		await _wait(0.25)
	_check(mv != null and mv.last_state.get("phase", "") == "fight", "la partida llegó a la fase de pelea")
	if mv == null:
		return finish()
	mv.capture_mouse = true
	mv.client.fx_received.connect(func(list: Array):
		for f in list:
			if f.k == "hit" and int(f.get("by", -1)) == mv.my_id:
				landed += 1
			elif f.k == "absorb" and mv.views.has(int(f.get("id", -1))) and mv.views[int(f.id)].entry.team != mv.my_team:
				landed += 1)
	await _wait(0.5)
	var vp := get_viewport().get_visible_rect().size
	var center := vp / 2.0
	_motion(center)
	await _wait(0.1)

	# 1. RMB mouselook: captured cursor, camera and character turn together, cursor restored afterwards
	var yaw0: float = mv.cam.yaw
	var saved := center + Vector2(120, 40)
	_motion(saved)
	await _wait(0.05)
	_button(MOUSE_BUTTON_RIGHT, true, saved)
	await _wait(0.03)
	await _drag(Vector2(-90, 0), 10)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "RMB arrastrado: el cursor se captura")
	_check(absf(wrapf(mv.cam.yaw - yaw0, -PI, PI)) > 0.1, "RMB arrastrado: la cámara giró (%.2f rad)" % wrapf(mv.cam.yaw - yaw0, -PI, PI))
	await _wait(0.1)
	_check(absf(wrapf(mv._face - mv.cam.yaw, -PI, PI)) < 0.05, "RMB: el personaje mira hacia donde mira la cámara")
	await _shot("rmb_mouselook")
	_button(MOUSE_BUTTON_RIGHT, false)
	await _wait(0.1)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "al soltar RMB el cursor vuelve a ser visible")
	_check(not mv._look and not mv._rmb, "al soltar RMB no queda estado de mouselook pegado")
	# (a synthetic event stream has no OS cursor to warp, so check that the saved position is what gets restored)
	_check(mv._saved_mouse.distance_to(saved) < 4.0, "el cursor se guardó donde estaba antes del arrastre y se restaura ahí")

	# 2. LMB orbit: camera turns, character does not
	var face0: float = mv._face
	var cam0: float = mv.cam.yaw
	_button(MOUSE_BUTTON_LEFT, true, center)
	await _wait(0.03)
	await _drag(Vector2(100, 0), 10)
	_check(absf(wrapf(mv.cam.yaw - cam0, -PI, PI)) > 0.1, "LMB arrastrado: la cámara orbita")
	_check(absf(wrapf(mv._face - face0, -PI, PI)) < 0.05, "LMB arrastrado: el personaje conserva su rumbo")
	_button(MOUSE_BUTTON_LEFT, false)
	await _wait(0.1)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not mv._look and not mv._lmb, "al soltar LMB todo vuelve a la normalidad")

	# 3. both buttons: run forward
	var p0 := _my_pos()
	_button(MOUSE_BUTTON_LEFT, true, center)
	_button(MOUSE_BUTTON_RIGHT, true, center)
	await _wait(0.8)
	var moved := _my_pos().distance_to(p0)
	_button(MOUSE_BUTTON_RIGHT, false)
	_button(MOUSE_BUTTON_LEFT, false)
	await _wait(0.1)
	_check(moved > 2.0, "ambos botones: el personaje avanza solo (%.1f m)" % moved)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not mv._look and not mv._lmb and not mv._rmb, "tras soltar ambos botones no queda nada pegado")

	# 4. find an enemy on screen: walk toward the nearest one (WASD held through real key events)
	var target_id := -1
	for i in 60:
		var e := _nearest_enemy()
		if e >= 0:
			target_id = e
			break
		await _wait(0.5)
	_check(target_id >= 0, "se ve al menos un enemigo")
	if target_id < 0:
		return finish()
	var ep := Vector2(mv.views[target_id].position.x, mv.views[target_id].position.z)
	await _turn_to(ep.x, ep.y)
	var spell_ranges: Array = _abs(cls)
	var melee := cls in ["warrior", "rogue"]
	await _walk_toward(target_id, 12.0 if not melee else 3.0, 25.0)
	_check(mv.views[target_id].shown or true, "caminó hacia el enemigo")
	await _wait(0.2)

	# 5. click targeting (LMB click on the enemy's screen position)
	target_id = _clear_enemy()
	if target_id < 0:
		_check(false, "hay un enemigo cerca para seleccionar")
		return finish()
	var sp := _screen_of(target_id)
	await _bring_on_screen(target_id)
	await _click_unit(target_id, MOUSE_BUTTON_LEFT)
	_check(_pick_ok_now, "clic izquierdo selecciona al enemigo (target=%d, esperado %d, clic %s, unidad en %s)" % [mv.controller.target, target_id, str(last_click), str(_screen_of(target_id))])
	await _shot("target_selected")

	# 6. Esc clears, Tab selects
	await _tap(KEY_ESCAPE)
	_check(mv.controller.target == -1, "Esc suelta el objetivo")
	await _tap(KEY_TAB)
	await _wait(0.1)
	_check(mv.controller.target >= 0 and mv.views[mv.controller.target].entry.team != mv.my_team, "Tab elige un enemigo")

	# 7. right click on the enemy: select + face + auto-attack for classes that have it
	target_id = _clear_enemy()
	if target_id < 0:
		target_id = mv.controller.target
	sp = _screen_of(target_id)
	await _bring_on_screen(target_id)
	await _click_unit(target_id, MOUSE_BUTTON_RIGHT)
	await _wait(0.5)
	var has_auto: bool = _abs(cls)[0].get("auto", false)
	_check(_pick_ok_now, "clic derecho selecciona al enemigo (target=%d, esperado %d, clic %s, unidad en %s)" % [mv.controller.target, target_id, str(last_click), str(_screen_of(target_id))])
	_check(not mv._look and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "un clic derecho corto no captura el cursor")
	if has_auto:
		_check(bool(mv.last_state.get("you", {}).get("auto", false)), "clic derecho en enemigo inicia el auto-ataque (%s)" % cls)
	else:
		_check(not bool(mv.last_state.get("you", {}).get("auto", false)), "%s no tiene auto-ataque: clic derecho no lo activa" % cls)

	# 8. deal damage: close in (melee) and use the first ability with the real key
	var hp_before := _enemy_hp_total()
	if melee:
		await _walk_toward(target_id, 2.4, 12.0)
	var lowest := hp_before
	if melee or cls == "hunter" or cls == "mage" or cls == "warlock":  # a short burst of frames: wind-up, strike, trail, recovery
		for k in 4:
			if k == 0 and not bool(mv.last_state.get("you", {}).get("auto", false)):
				await _tap(KEY_1)
			await _wait(0.12)
			await _shot("swing_%d" % k)
	for i in 14:
		if not has_auto:
			await _tap(KEY_1)  # slot 1 of auto classes is a toggle: pressing it repeatedly would switch the attack off
		elif i == 0 and not bool(mv.last_state.get("you", {}).get("auto", false)):
			await _tap(KEY_1)
		await _tap(KEY_2)
		await _wait(0.4)
		lowest = minf(lowest, _enemy_hp_total())  # enemy priests heal, so look at the lowest total seen
	await _shot("fighting")
	_check(lowest < hp_before or landed > 0, "se hizo daño (o el escudo enemigo absorbió) a los enemigos (%.0f -> mínimo %.0f, golpes %d)" % [hp_before, lowest, landed])

	# 8b. warlock showcase: curses ticking, a feared target, the drain beam (screenshots for review; info only)
	if cls == "warlock" and mv.me.alive and mv.controller.target >= 0:
		await _tap(KEY_Q)
		await _wait(0.9)
		await _tap(KEY_E)
		await _wait(1.6)
		await _shot("warlock_curses_fear")
		await _tap(KEY_F)
		await _wait(0.9)
		await _shot("warlock_drain")
		print("PLAYTEST info warlock curses=%s" % str(mv.views[mv.controller.target].snap.get("cc", {})))
		await _wait(1.0)

	# 9. ground reticle: place and cancel (classes with a ground spell)
	var ground_slot := -1
	for i in spell_ranges.size():
		if SpellKinds.kind(spell_ranges[i]) == "ground":
			ground_slot = i
	for i in 40:  # a cast in progress ignores other keys (by design): let it finish first
		if mv.me.get("cast") == null:
			break
		await _wait(0.1)
	var ult_ready: bool = float(mv.last_state.get("you", {}).get("ult", 0.0)) >= 100.0
	if ground_slot >= 0 and mv.me.alive and (not _abs(cls)[ground_slot].get("ult", false) or ult_ready):
		var key: int = {0: KEY_1, 1: KEY_2, 2: KEY_Q, 3: KEY_E, 4: KEY_SHIFT, 5: KEY_F, 6: KEY_R}[ground_slot]
		await _tap(key)
		await _wait(0.1)
		if mv.controller.pending_ground == ground_slot:
			_check(true, "la tecla del hechizo de zona abre el retículo")
			_motion(center + Vector2(40, 60))
			await _wait(0.2)
			await _shot("ground_reticle")
			await _tap(KEY_ESCAPE)
			_check(mv.controller.pending_ground < 0, "Esc cancela el retículo")
			await _tap(key)
			await _wait(0.1)
			_button(MOUSE_BUTTON_RIGHT, true, center)
			_button(MOUSE_BUTTON_RIGHT, false)
			await _wait(0.1)
			_check(mv.controller.pending_ground < 0, "clic derecho cancela el retículo")
			await _tap(key)
			await _wait(0.1)
			_motion(center + Vector2(0, 80))
			await _wait(0.2)
			_button(MOUSE_BUTTON_LEFT, true, center + Vector2(0, 80))
			_button(MOUSE_BUTTON_LEFT, false)
			await _wait(0.2)
			_check(mv.controller.pending_ground < 0, "clic izquierdo coloca el hechizo de zona")
		else:
			_check(false, "la tecla del hechizo de zona abre el retículo (puede estar en reutilización: %s)" % str(mv.controller.pending_ground))

	# 9b. no target: walk up and use an ability, like a new player would (no right click, no Tab)
	if mv.me.alive:
		await _no_target_scenario(cls, has_auto, melee)

	# 9c. mashing keys during a cast must not cancel or restart it (classes with a cast-time spell)
	if mv.me.alive and cls in ["mage", "hunter", "priest"]:
		await _mash_scenario(cls)

	# 10. no stuck state
	await _wait(0.3)
	_release_everything()
	await _wait(0.3)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "el cursor está visible al final")
	_check(not mv._look and not mv._lmb and not mv._rmb, "ningún botón ni mouselook quedó pegado")
	_check(mv.controller.pending_ground < 0, "no queda un retículo pendiente")
	finish()


## Walks around until the enemy is in line of sight (statues and pillars block spells, as in the game).
func _ensure_los(id: int) -> void:
	for i in 8:
		if not mv.views.has(id) or not mv.views[id].is_alive():
			return
		var ep := Vector2(mv.views[id].position.x, mv.views[id].position.z)
		var los := Rules.has_los(mv.world.map, {"x": _my_pos().x, "z": _my_pos().y}, {"x": ep.x, "z": ep.y})
		if los:
			return
		await _turn_to(ep.x, ep.y)
		_key(KEY_W, true)
		await _wait(0.5)
		_key(KEY_W, false)


func _no_target_scenario(cls: String, has_auto: bool, melee: bool) -> void:
	_release_everything()
	await _tap(KEY_ESCAPE)
	if bool(mv.last_state.get("you", {}).get("auto", false)):
		await _tap(KEY_1)  # toggle the auto-attack off
		await _wait(0.2)
	await _tap(KEY_ESCAPE)
	_check(mv.controller.target == -1, "[sin objetivo] arranca sin objetivo")
	var e := _nearest_enemy()
	if e < 0:
		_check(false, "[sin objetivo] hay un enemigo a la vista")
		return
	print("PLAYTEST info enemies_visible=%d start_dist=%.1f" % [_enemies().size(), _my_pos().distance_to(Vector2(mv.views[e].position.x, mv.views[e].position.z))])
	await _walk_toward(e, 2.6 if melee else 11.0, 20.0)
	e = _nearest_enemy()
	if e >= 0:
		await _ensure_los(e)
	print("PLAYTEST info after walk: enemies_visible=%d me_alive=%s" % [_enemies().size(), str(mv.me.alive)])
	if e >= 0:
		await _turn_to(mv.views[e].position.x, mv.views[e].position.z)
	var before := _enemy_hp_total()
	if e < 0 or _my_pos().distance_to(Vector2(mv.views[e].position.x, mv.views[e].position.z)) > (7.0 if melee else 18.0):
		print("PLAYTEST info [sin objetivo] no hay enemigo dentro del radio de selección automática; se omite (%s)" % cls)
		return
	if e >= 0:
		var ep2 := Vector2(mv.views[e].position.x, mv.views[e].position.z)
		var fwd := Vector2(sin(mv._face), cos(mv._face))
		print("PLAYTEST info dist=%.1f facing_dot=%.2f auto=%s alive=%s" % [_my_pos().distance_to(ep2), fwd.dot((ep2 - _my_pos()).normalized()), str(mv.last_state.get("you", {}).get("auto")), str(mv.me.alive)])
	await _tap(KEY_1)  # first ability, with no target selected
	var lowest := before
	var landed0 := landed
	var t := 0.0
	var picked := false
	var auto_on := false
	while t < 1.6:
		await _wait(0.1)
		t += 0.1
		lowest = minf(lowest, _enemy_hp_total())
		picked = picked or mv.controller.target >= 0
		auto_on = auto_on or bool(mv.last_state.get("you", {}).get("auto", false))
	_check(picked, "[sin objetivo] la habilidad eligió un objetivo (%s)" % cls)
	_check(lowest < before or landed > landed0, "[sin objetivo] hubo daño en ~1.5 s sin haber elegido objetivo (%.0f -> %.0f) %s" % [before, lowest, cls])
	if has_auto:
		_check(auto_on, "[sin objetivo] el auto-ataque se encendió solo")
	await _shot("no_target_attack")


func _mash_scenario(cls: String) -> void:
	var cast_slot := 1
	for i in [0, 1]:
		if float(_abs(cls)[i].cast) > 0.0:
			cast_slot = i
			break
	var cast_key: int = KEY_1 if cast_slot == 0 else KEY_2
	await _wait(float(_abs(cls)[cast_slot].cd) / 1000.0 + 2.5)  # let the cast-time spell come off cooldown (game-time seconds)
	if not mv.me.alive:
		return
	var e := _nearest_enemy()
	if e < 0 and cls != "priest":
		print("PLAYTEST info [ráfaga] no quedan enemigos a la vista; se omite (%s)" % cls)
		return
	if e >= 0:
		await _ensure_los(e)
		await _turn_to(mv.views[e].position.x, mv.views[e].position.z)
		if cls != "priest":
			await _click_unit(e, MOUSE_BUTTON_LEFT)
	_release_everything()
	if cls != "priest" and mv.controller.target < 0:
		await _tap(KEY_TAB)
	await _tap(cast_key)  # pyroblast / frostbolt / aimed shot / heal: has a cast time
	var min_left := 1e9
	var started := false
	var finished_left := -1.0
	var presses := 0
	var t := 0.0
	while t < 3.0:
		var c = mv.me.get("cast")
		if c != null:
			started = true
			min_left = minf(min_left, float(c.left))
			if presses < 10:
				var other: int = KEY_2 if cast_key == KEY_1 else KEY_1
				_key(cast_key if presses % 2 == 0 else other, true)
				_key(cast_key if presses % 2 == 0 else other, false)
				presses += 1
		elif started:
			finished_left = min_left
			break
		if c != null:
			print("PLAYTEST info cast left=%.0f err='%s' keys=%s btn=%s" % [float(c.left), mv.hud.error_text.text, str(_keys_down), str(_buttons)])
		await _wait(0.08)
		t += 0.08
	print("PLAYTEST info cast end err='%s'" % mv.hud.error_text.text)
	_check(started, "[ráfaga] el lanzamiento empezó (%s; error='%s' objetivo=%d enemigos=%d vivo=%s)" % [cls, mv.hud.error_text.text, mv.controller.target, _enemies().size(), str(mv.me.alive)])
	_check(presses >= 5, "[ráfaga] se apretaron teclas durante el lanzamiento (%d)" % presses)
	var lost := mv.hud.error_text.text.contains("Perdiste") or mv.hud.error_text.text.contains("cancelado") or _enemies().size() == 0
	if finished_left >= 250.0 and lost:
		print("PLAYTEST info el lanzamiento terminó antes porque el objetivo murió o se perdió (no por las teclas)")
		finished_left = 0.0
	_check(finished_left >= 0.0 and finished_left < 250.0, "[ráfaga] el lanzamiento llegó hasta el final sin cancelarse (quedaban %.0f ms al verlo terminar)" % finished_left)


func finish() -> void:
	_release_everything()
	print("PLAYTEST done passes=%d fails=%d" % [passes, fails.size()])
	for f in fails:
		print("PLAYTEST FAILED: ", f)
	get_tree().quit(1 if not fails.is_empty() else 0)
