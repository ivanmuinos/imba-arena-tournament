class_name MatchView
extends Node3D
## One match as the player sees it: scenery, fighters, effects, camera, HUD and input
## (port of the frame loop / input / event handling in src/main.ts).

signal finished(end_msg: Dictionary, rows: Array)

const PICK_RADIUS := 42.0

var client: GameClient
var world: ArenaWorld
var cam: CameraRig
var fx: FxManager
var hud: Hud
var audio: AudioBank
var views := {}
var my_id := -1
var my_team := "red"
var my_cls := "mage"
var my_spec := ""
var me: Dictionary = {}
var last_state: Dictionary = {}
var controller := PlayerController.new()
var predictor := Predictor.new()
## false for automated runs (screenshots, smoke tests) so the real mouse is left alone.
var capture_mouse := true
## Smoke tests: a scripted player that moves, targets and casts at random (--drive).
var drive_bot := false
## Screenshots: keep an enemy selected (and start the auto-attack when the class has one).
var demo_target := false
## alta | media | baja | auto (auto starts at alta and drops when fps stays low).
var gfx_choice := "auto"
var gfx_level := "alta"

var _roster: Array = []
var _state_ms := 0.0
var _look := false  # cursor hidden and captured while dragging with a button
var _hover := -1
var _face := 0.0  # the character's facing (yaw), independent of the camera until mouselook
var _lmb := false
var _rmb := false
var _press := {}  # button -> screen position where it went down
var _dragged := {}  # button -> true once it turned into a drag
var _saved_mouse := Vector2.ZERO
var _reticle: MeshInstance3D
var _ground_point := Vector2.ZERO
var _sent_target := -2
var _last_target_sync := 0.0
var _last_sent := {"dx": 0.0, "dz": 0.0, "ax": 0.0, "az": 0.0, "at": 0.0}
var _last_jump := 0.0
var _prev_casting := {}
var _pending_end := {}
var _end_at := 0.0
var _active := false
var _last_prep_tick := -1
var _auto := AutoQuality.new()
var _fps_t := 0.0
var _fps_n := 0
var _drive_cast_at := 0.0
var _drive_tab_at := 0.0
var _drive_jump_at := 0.0
var _spectating := -1


## Only allies present in the filtered snapshot are eligible; never exposes hidden enemies.
static func spectate_id(units: Array, own: int, team: String, current: int, cycle := false, roster: Array = []) -> int:
	var ids: Array = []
	for u in units:
		var unit_team: String = u.get("team", "")
		for entry in roster:
			if int(entry.id) == int(u.id):
				unit_team = entry.team
				break
		if int(u.id) != own and unit_team == team and u.alive:
			ids.append(int(u.id))
	if ids.is_empty():
		return -1
	var index := ids.find(current)
	return int(ids[(index + 1) % ids.size()]) if cycle or index < 0 else current


func start(p_client: GameClient, msg: Dictionary) -> void:
	client = p_client
	my_id = int(msg.you)
	_roster = msg.roster
	var mine: Dictionary = _roster.filter(func(r): return r.id == my_id)[0]
	my_team = mine.team
	my_cls = mine.cls
	my_spec = str(mine.get("spec", ""))
	world = ArenaWorld.new()
	add_child(world)
	world.setup(GameMap.create(msg.map))
	cam = CameraRig.new()
	add_child(cam)
	cam.current = true
	fx = FxManager.new()
	add_child(fx)
	fx.setup(world)
	fx.shake.connect(func(amount, x, z): if Vector2(x - predictor.m.x, z - predictor.m.z).length() < 14.0: cam.add_shake(amount))
	for r in _roster:
		var v := UnitView.new()
		add_child(v)
		v.setup(r, r.id == my_id, world)
		v.predicted = r.id == my_id
		views[r.id] = v
		v.landed.connect(func(pos: Vector3):
			audio.play("land", Vector2(pos.x, pos.z), 30.0)
			fx.dash(pos.x, pos.z))
	hud = Hud.new()
	add_child(hud)
	hud.setup(_roster, my_id, my_cls, my_team, my_spec)
	hud.frame_clicked.connect(_on_frame_clicked)
	controller.setup(my_cls, my_team, my_spec)
	controller.ready_at = hud.ready_at
	predictor.place(mine_spawn().x, mine_spawn().y)
	_face_enemy()
	audio = AudioBank.new()
	audio.gain_db = linear_to_db(maxf(0.001, SettingsStore.shared().get_value("sfx")))
	add_child(audio)
	client.state_received.connect(_on_state)
	client.fx_received.connect(_on_fx)
	client.kill_received.connect(func(m): hud.kill(m))
	client.server_error.connect(_on_server_error)
	client.match_ended.connect(_on_end)
	gfx_level = Quality.resolve(gfx_choice, Quality.initial_level(RenderingServer.get_video_adapter_type(), Quality.compatibility_renderer()))
	_apply_level(gfx_level)
	_active = true
	hud.lock_hint.visible = false
	_reticle = _make_reticle()
	add_child(_reticle)
	CursorKit.reset()
	# First frame: camera on the spawn point.
	cam.chase(predictor.m.x, predictor.m.z, 0.016, world, true)


func mine_spawn() -> Vector2:
	var map := GameMap.get_map(client.map_id)
	var spawns: Array = map.spawns[my_team]
	var idx := 0
	var n := 0
	for r in _roster:
		if r.team == my_team:
			if r.id == my_id:
				idx = n
			n += 1
	var s: Dictionary = spawns[idx % spawns.size()]
	return Vector2(s.x, s.z)


func stop() -> void:
	_active = false
	set_capture(false)
	if client != null:
		for sig in [client.state_received, client.fx_received, client.server_error, client.match_ended]:
			for c in sig.get_connections():
				sig.disconnect(c.callable)
		for c in client.kill_received.get_connections():
			client.kill_received.disconnect(c.callable)


## Hides and captures the cursor while a mouse button drags the camera; restores it where it was.
func _begin_look(restore_at: Vector2) -> void:
	if _look or not capture_mouse:
		return
	_look = true
	_saved_mouse = restore_at  # where the button went down, not where the drag was detected a few pixels later
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end_look() -> void:
	if not _look:
		return
	_look = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(_saved_mouse)


func set_capture(on: bool) -> void:  # kept for callers: leaving a match must always free the cursor
	if not on:
		_end_look()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		CursorKit.reset()


func _face_enemy() -> void:
	_face = PI if my_team == "red" else 0.0
	cam.yaw = _face
	cam.pitch = 0.16


# ---------------------------------------------------------------- network events

func _now_ms() -> float:
	return float(Time.get_ticks_msec())


func _unit_snap(s: Dictionary, id: int) -> Dictionary:
	for u in s.units:
		if u.id == id:
			return u
	return {}


func _on_state(s: Dictionary) -> void:
	if not _active:
		return
	var now := _now_ms()
	_state_ms = now
	var prev_phase: String = last_state.get("phase", "")
	last_state = s
	me = _unit_snap(s, my_id)
	if not me.is_empty() and not me.alive:
		controller.cancel_ground()
		_spectating = spectate_id(s.units, my_id, my_team, _spectating, false, _roster)
	else:
		_spectating = -1
	if s.phase == "prep" and prev_phase != "prep":
		_face_enemy()
	# Spell names over casters when a cast begins.
	for u in s.units:
		var v: UnitView = views.get(u.id)
		var casting: bool = u.cast != null
		if v != null and casting and not _prev_casting.get(u.id, false):
			audio.play("castStart", Vector2(u.x, u.z))
			var spec: Dictionary = GameData.ability(v.entry.cls, int(u.cast.slot), str(v.entry.get("spec", "")))
			hud.float_text(Vector3(u.x, world.h(u.x, u.z) + 3.2 * UnitView.VS, u.z), spec.name, Color("#ffe08a"), true)
		_prev_casting[u.id] = casting
	if prev_phase != "fight" and s.phase == "fight":
		audio.play("fight")
	if s.phase == "prep":
		var sec := ceili(s.phaseLeft / 1000.0)
		if sec != _last_prep_tick and sec <= 3:
			audio.play("tick")
		_last_prep_tick = sec
	if not me.is_empty():
		predictor.on_state(me, s.phase, now)
	var hand_list: Array = []
	for hid in views:
		var hv: UnitView = views[hid]
		if hv.shown and hv.is_alive():
			hand_list.append(hv.hand_position())
	fx.hands = hand_list
	fx.sync_projectiles(s.projs, now / 1000.0)
	fx.sync_aoes(s.aoes, now / 1000.0)
	fx.sync_traps(s.traps)
	fx.sync_powers(s.powers)
	world.map.apply_state(s.gates, s.ft)
	world.sync_state(s.gates, s.ft, now / 1000.0)
	hud.on_state(s, me, now)
	hud.set_ping(client.rtt_ms if client.rtt_ms >= 0 and client.transport is PeerTransport else -1)


func _on_server_error(text: String) -> void:
	if _active:
		hud.error(text)
		audio.play("error")


func _on_end(msg: Dictionary) -> void:
	_pending_end = msg
	_end_at = _now_ms() + 2600.0


func _finish() -> void:
	if _pending_end.is_empty():
		return
	var end := _pending_end
	_pending_end = {}
	var rows: Array = []
	for r in _roster:
		var st := {}
		for s in end.stats:
			if int(s.id) == r.id:
				st = s
		rows.append({"name": r.name, "team": r.team, "cls": r.cls, "dmg": int(st.get("dmg", 0)), "kills": int(st.get("kills", 0)), "deaths": int(st.get("deaths", 0)), "heal": int(st.get("heal", 0))})
	audio.play("win" if end.winner == my_team else "lose")
	finished.emit(end, rows)


const CC_WORDS := ["ATURDIDO", "OVEJA", "CONGELADO", "SILENCIADO", "ENRAIZADO", "ATERRORIZADO", "CEGADO"]
const CAST_SOUND := {
	"fireball": "fireball", "pyro": "pyro", "shot": "shot", "aimed": "aimed", "conc": "conc", "silence": "silence", "volley": "volley",
	"poly": "poly", "counter": "counter", "disengage": "disengage", "trap": "trapSet", "meteor": "meteorFall", "strike": "swing", "stab": "swing",
	"mortal": "heavySwing", "eviscerate": "heavySwing", "hamstring": "swing", "cheapshot": "heavySwing", "pummel": "interrupt", "kick": "interrupt",
	"charge": "charge", "shieldwall": "wall", "bladestorm": "storm", "smite": "smite", "pwshield": "shieldUp", "renew": "renew", "dispel": "dispel",
	"blind": "blind", "vanish": "vanish", "deathmark": "deathmark",
	"shadowbolt": "shadowbolt", "corruption": "corruption", "agony": "agony", "fear": "scream", "darkpact": "darkpact", "drainlife": "drainlife", "soulrot": "soulrot",
	"frostbolt": "frostbolt", "icelance": "icelance", "blizzard": "blizzard",
}


func _ability_icon(id: String) -> String:
	for cls in GameData.classes:
		for a in GameData.classes[cls].abilities:
			if a.id == id:
				return ""
	return ""


func _ability_spec(id: String) -> Dictionary:
	for cls in GameData.classes:
		for a in GameData.classes[cls].abilities:
			if a.id == id:
				return a
		for sid in GameData.spec_ids(cls):
			for a in GameData.abilities(cls, sid):
				if a.id == id:
					return a
	return {}


func _on_fx(list: Array) -> void:
	if not _active:
		return
	for f in list:
		_one_fx(f)


func _one_fx(f: Dictionary) -> void:
	var v: UnitView = views.get(int(f.id)) if f.has("id") else null
	var pos := Vector3.ZERO
	if v != null:
		pos = v.position
	var is_me: bool = f.has("id") and int(f.id) == my_id
	var p2 := Vector2(pos.x, pos.z)
	match f.k:
		"hit":
			if f.get("dot", false):
				# periodic damage: the number only (no flash, impact, shake or sound; those strobe on every tick)
				if v != null and v.shown:
					hud.float_text(Vector3(f.x, world.h(f.x, f.z) + 2.3 * UnitView.VS, f.z), "-%d" % f.amt, Color("#ff6b6b") if v.entry.team == my_team else Color("#ffd27a"))
				return
			if v != null:
				v.flash()
			var ally: bool = v != null and v.entry.team == my_team
			var color := Color("#ff6b6b") if ally else Color("#ffd27a")
			var wp := Vector3(f.x, world.h(f.x, f.z) + 2.3 * UnitView.VS, f.z)
			if f.crit:
				hud.float_text(wp + Vector3(0, 0.2, 0), "%d!" % f.amt, color, false, "crit")
			else:
				hud.float_text(wp, "-%d" % f.amt, color)
			if f.has("ability") and (v == null or v.shown):
				fx.hit_impact(f.x, f.z, str(f.ability), f.crit)
				if str(f.ability) == "soulrot" and f.amt >= 20:  # the opening hit, not the 8-point ticks
					fx.soulrot_burst(f.x, f.z)
			if int(f.get("by", -1)) == my_id and (f.crit or f.amt >= 40):
				cam.add_shake(0.22 if f.crit else 0.12)  # only crits and big hits shake the camera
			if is_me:
				audio.play("hitMe" if SpellSchools.school_of(str(f.get("ability", ""))) == "physical" else "hitMeSpell")
				cam.add_shake(0.6 if f.crit else 0.3)
				cam.kick(0.35 if f.crit else 0.12)
			else:
				audio.play("crit" if f.crit else ("hit" if SpellSchools.school_of(str(f.get("ability", ""))) == "physical" else "hitSpell"), Vector2(f.x, f.z))
		"heal":
			if v != null and v.shown:
				fx.heal(pos.x, pos.z)
				hud.float_text(pos + Vector3(0, 2.4 * UnitView.VS, 0), "+%d" % f.amt, Color("#5cff8a"), false, "heal")
				audio.play("heal", p2)
		"power":
			if v != null:
				var spec: Dictionary = GameData.powers[f.kind]
				fx.pickup(pos.x, pos.z, f.kind)
				hud.float_text(pos + Vector3(0, 3.3 * UnitView.VS, 0), spec.name, Color.WHITE, true)
				audio.play("power", p2)
				if is_me and f.kind != "heal":
					hud.error("%s: %s" % [spec.name, spec.desc])
		"absorb":
			if v != null:
				hud.float_text(pos + Vector3(0, 2.6 * UnitView.VS, 0), "ABSORBIDO", Color("#7fdbff"), true)
				audio.play("absorb", p2)
		"boom":
			fx.boom(f.x, f.z, f.r, f.kind)
			audio.play("bigBoom" if f.kind in ["meteor", "pyro"] else "boom", Vector2(f.x, f.z))
		"nova":
			fx.nova(f.x, f.z, f.r)
			audio.play("nova", Vector2(f.x, f.z))
		"blink":
			fx.blink(f.x0, f.z0, f.x1, f.z1)
			audio.play("blink", Vector2(f.x1, f.z1))
		"trap":
			fx.trap(f.x, f.z)
			audio.play("trapHit", Vector2(f.x, f.z))
		"label":
			if v != null and v.shown:
				hud.float_text(pos + Vector3(0, 3.1 * UnitView.VS, 0), f.text, Color(str(f.color)), true)
			if f.text == "INTERRUMPIDO":
				audio.play("interrupt", p2)
			elif is_me and CC_WORDS.any(func(w): return f.text.contains(w)):
				audio.play("ccMe")
		"cast":
			if v != null and v.shown:
				if f.ability == "disengage":
					fx.dash(pos.x, pos.z)
				else:
					fx.cast_spark(pos.x, pos.z, f.ability, float(v.snap.get("rot", 0.0)))
					v.cast_gesture()
			# Ultimates are announced over the caster's head so everyone can read the fight.
			var aspec := _ability_spec(f.ability)
			if aspec.get("ult", false) and v != null and v.shown:
				hud.float_text(pos + Vector3(0, 3.4 * UnitView.VS, 0), str(aspec.name).to_upper(), Color("#ffd166"))
			if f.ability == "darkpact" and v != null and v.shown:
				fx.pact(pos.x, pos.z)
			if CAST_SOUND.has(f.ability) and (is_me or (v != null and v.shown)):
				audio.play(CAST_SOUND[f.ability], p2)
		"breath":
			fx.breath(f.x, f.z, f.dx, f.dz, f.r)
			audio.play("dragonbreath", Vector2(f.x, f.z))
		"scream":
			fx.scream(f.x, f.z, f.r)
			audio.play("scream", Vector2(f.x, f.z))
		"hymn":
			fx.hymn(f.x, f.z, f.r)
			audio.play("hymn", Vector2(f.x, f.z))
		"charge":
			fx.charge(f.x0, f.z0, f.x1, f.z1)
			if is_me:
				cam.kick(0.5)
		"swing":
			if v != null:
				v.swing(f.heavy)
				v.swing_count += 1
				if v.shown:
					fx.slash(pos.x, pos.z, float(v.snap.get("rot", 0.0)), f.heavy, 1.0 if (v.swing_count % 2 == 0) else -1.0)
		"death":
			hud.mark_dead(int(f.id))
			if v != null:
				fx.boom(pos.x, pos.z, 0.6, "fireball")
				audio.play("death", p2)


# ---------------------------------------------------------------- input (WoW style)

func _on_frame_clicked(id: int) -> void:
	if not me.is_empty() and not me.alive and views.has(id) and views[id].entry.team == my_team and views[id].is_alive():
		_spectating = id
		return
	_select(id)


func _select(id: int) -> void:
	controller.select(id)
	hud.set_friend(id if _team_of(id) == my_team else -1)
	audio.play("tick")


func _team_of(id: int) -> String:
	for r in _roster:
		if r.id == id:
			return r.team
	return ""


## Unit under the cursor from the projected positions (head/chest), nearest to the camera first.
func _unit_at(mouse: Vector2) -> int:
	var cands: Array = []
	for id in views:
		var v: UnitView = views[id]
		if id == my_id or not v.shown or not v.is_alive():
			continue
		var wp := v.position + Vector3(0, 1.1 * UnitView.VS, 0)
		if cam.is_position_behind(wp):
			continue
		cands.append({"id": id, "pos": cam.unproject_position(wp), "r": PICK_RADIUS, "depth": cam.global_position.distance_to(wp)})
	return ClickPicker.pick(cands, mouse)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseMotion:
		if _look:
			cam.look(event.relative)
		else:
			for b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				if _press.has(b) and not _dragged.get(b, false) and InputLogic.is_drag(_press[b], event.position):
					_dragged[b] = true
					_begin_look(_press[b])
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		var slot := InputLogic.slot_for_key(event.keycode)
		if slot >= 0:
			get_viewport().set_input_as_handled()
			_cast(slot)
			return
		match event.keycode:
			KEY_ESCAPE:
				if controller.pending_ground >= 0:
					controller.cancel_ground()
				elif not me.is_empty() and me.get("cast") != null:
					client.send_stop_cast()  # Esc cancels the cast in progress (movement and jumping do too)
				else:
					controller.clear_target()
					hud.set_friend(-1)
			KEY_TAB:
				get_viewport().set_input_as_handled()
				_cycle_target()
			KEY_SPACE:
				get_viewport().set_input_as_handled()
				_jump()
			KEY_M:
				hud.error("Sonido apagado (M)" if audio.toggle_mute() else "Sonido activado (M)")
			KEY_F1, KEY_F2, KEY_F3:
				var ids := hud.ally_ids()
				var i: int = int(event.keycode - KEY_F1)
				if i < ids.size():
					_select(ids[i])


func _on_mouse_button(event: InputEventMouseButton) -> void:
	var b: int = event.button_index
	if b == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		cam.zoom(-0.35)
		return
	if b == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		cam.zoom(0.35)
		return
	if b != MOUSE_BUTTON_LEFT and b != MOUSE_BUTTON_RIGHT:
		return
	if event.pressed:
		# Ground spell waiting for a click: left places it, right cancels.
		if controller.pending_ground >= 0:
			if b == MOUSE_BUTTON_LEFT:
				_confirm_ground()
			else:
				controller.cancel_ground()
			get_viewport().set_input_as_handled()
			return
		_press[b] = event.position
		_dragged[b] = false
		if b == MOUSE_BUTTON_LEFT:
			_lmb = true
		else:
			_rmb = true
		return
	# released
	var was_drag: bool = _dragged.get(b, false)
	var had_press := _press.has(b)
	_press.erase(b)
	_dragged.erase(b)
	if b == MOUSE_BUTTON_LEFT:
		_lmb = false
	else:
		_rmb = false
	if not _lmb and not _rmb:
		_end_look()
	if had_press and not was_drag:
		_click(b, event.position)


## A click that did not become a drag: left selects, right selects and (melee/hunter) starts the auto-attack.
func _click(button: int, pos: Vector2) -> void:
	var id := _unit_at(pos)
	if id < 0:
		return
	if button == MOUSE_BUTTON_LEFT:
		_select(id)
		return
	var res := controller.right_click_unit(id, _ctx())
	_select(id)
	if _team_of(id) != my_team:
		_face_toward(id)
	_apply_auto(res.auto)


func _face_toward(id: int) -> void:
	var v: UnitView = views.get(id)
	if v == null:
		return
	var d := Vector2(v.position.x - predictor.m.x, v.position.z - predictor.m.z)
	if d.length() > 0.1:
		_face = atan2(d.x, d.y)
		cam.yaw = _face


func _apply_auto(mode: String) -> void:
	if mode == "start":
		client.send_target(controller.target)
		client.send_auto(true, controller.target)
	elif mode == "stop":
		client.send_auto(false)


func _confirm_ground() -> void:
	var res := controller.confirm_ground(_ground_point, _ctx())
	if not res.msg.is_empty():
		client.send_cast(res.msg)


func _ctx() -> Dictionary:
	var units := []
	for id in views:
		var v: UnitView = views[id]
		if v.snap.is_empty():
			continue
		units.append({"id": id, "team": v.entry.team, "x": v.position.x, "z": v.position.z, "alive": v.snap.alive, "visible": v.shown,
			"hp": float(v.snap.hp) / float(GameData.classes[v.entry.cls].hp),
			"incap": v.snap.cc.has("incap")})
	var map := world.map
	return {
		"now": _now_ms(), "alive": not me.is_empty() and me.alive, "phase": last_state.get("phase", ""), "units": units,
		"pos": Vector2(predictor.m.x, predictor.m.z), "fwd": Vector2(sin(_face), cos(_face)), "my_id": my_id,
		"cast": me.get("cast"), "mouse_ground": _ground_point, "auto_on": bool(last_state.get("you", {}).get("auto", false)),
		"los": func(a: Vector2, b: Vector2) -> bool: return Rules.has_los(map, {"x": a.x, "z": a.y}, {"x": b.x, "z": b.y}),
	}


func _cycle_target_quiet() -> bool:
	return controller.cycle_target(_ctx())


func _cycle_target() -> void:
	if not me.is_empty() and not me.alive:
		_spectating = spectate_id(last_state.units, my_id, my_team, _spectating, true, _roster)
		return
	if not controller.cycle_target(_ctx()):
		hud.error("No hay enemigos a la vista")
	else:
		audio.play("tick")


func _jump() -> void:
	var t := _now_ms()
	if me.is_empty() or not me.alive or t - _last_jump < JUMP_COOLDOWN_MS or me.cc.has("stun") or me.cc.has("incap") or me.cc.has("root"):
		return
	_last_jump = t
	client.send_jump()
	views[my_id].jump_now(t / 1000.0)


const JUMP_COOLDOWN_MS := 650.0


func _cast(slot: int) -> void:
	if me.is_empty():
		return
	var res := controller.try_cast(slot, _ctx())
	if res.error != "":
		hud.error(res.error)
		audio.play("error")
	if res.auto != "":
		_apply_auto(res.auto)
	if res.pending_ground:
		hud.error("Clic izquierdo para colocar · clic derecho o Esc para cancelar")
	if not res.msg.is_empty():
		client.send_cast(res.msg)
		if predictor.predict_movement(my_cls, slot, res.aim_dir, me, world.map, _now_ms()):
			cam.kick(0.6)


func _make_reticle() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshBuilder.ring(0.88, 1.0, 48)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.8, 0.3, 0.9)
	m.no_depth_test = true
	mi.material_override = m
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## World point under the cursor (ground), clamped to the pending spell's range.
func _mouse_ground(mouse: Vector2) -> Vector2:
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var hit = cam.march_ground(origin, dir, 120.0, world)
	var p := Vector2(predictor.m.x, predictor.m.z) + Vector2(sin(_face), cos(_face)) * 10.0
	if hit != null:
		p = Vector2(hit.x, hit.z)
	return p


# ---------------------------------------------------------------- frame

var _scale := 1.0
var _base_scale := 1.0


## Applies a quality level at the window's real pixel size (Retina windows render 3D below native and upscale).
func _apply_level(level: String) -> void:
	var q := Quality.effective(level, Vector2i(get_window().size))
	_base_scale = float(q.scale)
	_scale = _base_scale
	world.apply_quality(q)
	fx.apply_quality(q)


func _process(delta: float) -> void:
	if not _active:
		return
	var dt := minf(delta, 0.05)
	var now := _now_ms()
	_fps_t += AutoQuality.real_delta(delta, Engine.time_scale)
	_fps_n += 1
	if _fps_t >= 1.0:
		if gfx_choice == "auto":
			var fps := roundi(_fps_n / _fps_t)
			var target := 90 if DisplayServer.screen_get_refresh_rate() > 100.0 else 60
			var sc := _auto.step_scale(fps, now, _scale, _base_scale, target)
			if sc != _scale:
				_scale = sc
				world.set_render_scale(_scale, Quality.upscaler_for(OS.get_name(), _scale))
			elif _auto.at_floor(_scale):
				var lvl := _auto.feed(fps, now, gfx_level)
				if lvl != gfx_level:
					gfx_level = lvl
					_apply_level(lvl)
					hud.error("Bajé los gráficos a %s para que ande más fluido" % lvl)
		_fps_t = 0.0
		_fps_n = 0
	if not _pending_end.is_empty() and now >= _end_at:
		_finish()
		return
	var t := now / 1000.0
	if last_state.is_empty() or client == null:
		return
	# Other players: interpolated; me: predicted.
	var sample := client.buffer.sample(now)
	for id in views:
		var v: UnitView = views[id]
		if sample.has(id):
			v.apply(sample[id])
		else:
			v.set_hidden()
			hud.hide_plate(id)
	var my_view: UnitView = views[my_id]
	if demo_target and not me.is_empty() and controller.target < 0 and last_state.phase == "fight" and _cycle_target_quiet():
		var r := controller.right_click_unit(controller.target, _ctx())
		_apply_auto(r.auto)
	if not me.is_empty():
		var km := InputLogic.keyboard_move(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP), Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN),
			Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT), Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT), _rmb, _lmb)
		if drive_bot:
			cam.yaw += sin(t * 0.7) * 0.02
			_face = cam.yaw
			km = {"fwd": 1, "strafe": 0, "turn": 0}
		var turn: float = km.turn * InputLogic.TURN_RATE * dt
		_face += turn
		if _rmb and not drive_bot:
			_face = cam.yaw  # mouselook: the character faces where the camera looks
		else:
			cam.yaw += turn
		cam.yaw = InputLogic.follow_yaw(cam.yaw, _face, dt, km.fwd != 0 or km.strafe != 0, _lmb or _rmb)
		var input := InputLogic.move_vector(km.fwd, km.strafe, _face)
		if drive_bot:
			input = _drive_step(now, t)
		if not me.alive:
			input = Vector2.ZERO
		var fighting: bool = last_state.phase == "fight"
		var age := minf(0.1, (now - _state_ms) / 1000.0)
		predictor.step(dt, input, me, my_cls, fighting, world.map, age, now)
		my_view.drive(predictor.m.x, predictor.m.z, predictor.m.vx, predictor.m.vz)
		my_view.apply({"x": predictor.m.x, "z": predictor.m.z, "rot": _face, "unit": me})
		my_view.facing_override = _face if (me.alive and not me.cc.has("stun") and not me.cc.has("incap")) else NAN

		# Spectate a living ally while dead.
		var focus := Vector2(predictor.m.x, predictor.m.z)
		var observed := ""
		if not me.alive and views.has(_spectating):
			var v: UnitView = views[_spectating]
			if v.is_alive() and v.shown:
				focus = Vector2(v.position.x, v.position.z)
				observed = v.entry.name
		hud.set_spectator(not me.alive, observed)
		cam.chase(focus.x, focus.y, dt, world)
		audio.listener = focus
		_aim_and_target(focus, now)
		_send_input(input, now)
		var q := controller.poll_queue(now, me.get("cast") != null)
		if q >= 0:
			_cast(q)
		_hud_frame(focus, now, dt)
	for id in views:
		var v: UnitView = views[id]
		v.near_camera = v.shown and (v.position + Vector3(0, 1.4, 0)).distance_to(cam.global_position) < 2.6  # measured from the head/hat, which is what fills the screen
		v.update(dt, t)
		hud.update_plate(id, v, cam, id == controller.target, id == _hover)
	_warlock_fx(dt, t)
	fx.update(dt, t)
	world.update(dt, t)
	hud.tick(now, AutoQuality.real_delta(delta, Engine.time_scale), cam)


## Continuous shadow-school visuals: per-curse ticks on victims, fear wisps, Drain Life beams caster -> target.
var _curse_clock := {}

func _warlock_fx(dt: float, t: float) -> void:
	var beams: Array = []
	for id in views:
		var v: UnitView = views[id]
		if not v.shown or v.snap.is_empty() or not v.snap.alive:
			continue
		var cc: Dictionary = v.snap.cc
		for key in ["corruption", "agony", "soulrot"]:
			if cc.has(key):
				var k := "%d:%s" % [id, key]
				_curse_clock[k] = float(_curse_clock.get(k, 0.0)) - dt
				if _curse_clock[k] <= 0.0:
					_curse_clock[k] = 0.5
					fx.curse_pulse(v.position.x, v.position.z, key)
		if cc.has("fear"):
			var kf := "%d:fear" % id
			_curse_clock[kf] = float(_curse_clock.get(kf, 0.0)) - dt
			if _curse_clock[kf] <= 0.0:
				_curse_clock[kf] = 0.2
				fx.fear_wisps(v.position.x, v.position.z)
		var c = v.snap.cast
		if c != null and v.entry.cls == "warlock":
			var abil: Array = GameData.abilities("warlock", "")
			var slot := int(c.slot)
			if slot >= 0 and slot < abil.size() and abil[slot].id == "drainlife" and views.has(int(c.get("tid", -1))):
				var tv: UnitView = views[int(c.tid)]
				if tv.shown:
					beams.append({"id": id, "from": v.position + Vector3(0, 1.2 * UnitView.VS, 0), "to": tv.position + Vector3(0, 1.0 * UnitView.VS, 0)})
	fx.set_beams(beams, t)


func _drive_step(now: float, t: float) -> Vector2:
	if now >= _drive_cast_at:
		_drive_cast_at = now + 280.0
		var slot := randi() % int(GameData.C.SLOT_COUNT)
		_cast(slot)
		if controller.pending_ground >= 0:
			_ground_point = Vector2(predictor.m.x, predictor.m.z) + Vector2(sin(_face), cos(_face)) * 8.0
			_confirm_ground()
	if now >= _drive_tab_at:
		_drive_tab_at = now + 1500.0
		_cycle_target()
		var ids := hud.ally_ids()
		if randf() < 0.3 and not ids.is_empty():
			_select(ids[randi() % ids.size()])
	if now >= _drive_jump_at:
		_drive_jump_at = now + 2500.0
		_jump()
	return Vector2(sin(_face + sin(t) * 1.2), cos(_face + sin(t) * 1.2))


## Hover/cursor, ground reticle, target sync, selection visuals (called every frame while alive).
func _aim_and_target(_focus: Vector2, now: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var ctx := _ctx()
	controller.maintain_target(ctx)
	_hover = _unit_at(mouse) if not _look and controller.pending_ground < 0 else -1
	var rel := ""
	var dist := 0.0
	var reach := 0.0
	if _hover >= 0:
		var hv: UnitView = views[_hover]
		rel = "friend" if _team_of(_hover) == my_team else "enemy"
		dist = Vector2(hv.position.x - predictor.m.x, hv.position.z - predictor.m.z).length()
		var basic := GameData.ability(my_cls, 0, my_spec)
		reach = float(basic.range) + 1.0 if rel == "enemy" else 25.0
	CursorKit.refit(Vector2(get_window().size))
	CursorKit.set_kind(CursorKit.kind_for(rel, dist, reach, controller.pending_ground >= 0))
	# Ground reticle for AoE placement.
	if controller.pending_ground >= 0:
		var spec := controller.ability(controller.pending_ground)
		var p := _mouse_ground(mouse)
		var pos := Vector2(predictor.m.x, predictor.m.z)
		if spec.range > 0 and p.distance_to(pos) > spec.range:
			p = pos + (p - pos).normalized() * spec.range
		_ground_point = p
		var r: float = spec.get("aoe", 1.5) if spec.get("aoe", 0.0) > 0 else 1.5
		_reticle.visible = true
		_reticle.position = Vector3(p.x, world.h(p.x, p.y) + 0.25, p.y)
		_reticle.scale = Vector3(r, 1, r) * (1.0 + 0.05 * sin(now * 0.012))
	else:
		_reticle.visible = false
	if controller.target != _sent_target or now - _last_target_sync > 1000.0:
		_sent_target = controller.target
		_last_target_sync = now
		client.send_target(controller.target)
	for id in views:
		var v: UnitView = views[id]
		var mode := ""
		if id == controller.target:
			mode = "friend" if _team_of(id) == my_team else "lock"
		elif id == _hover:
			mode = "hover"
		v.set_targeted(mode)
	hud.show_target_arrow(controller.target, views, cam)


func _send_input(input: Vector2, now: float) -> void:
	var fwd := Vector2(sin(_face), cos(_face))
	var aim := Vector2(predictor.m.x, predictor.m.z) + fwd * 30.0
	var l := _last_sent
	if input.x != l.dx or input.y != l.dz or Vector2(aim.x - l.ax, aim.y - l.az).length() > 0.3 or now - l.at > 120.0:
		client.send_input(input.x, input.y, aim.x, aim.y)
		_last_sent = {"dx": input.x, "dz": input.y, "ax": aim.x, "az": aim.y, "at": now}


func _hud_frame(focus: Vector2, now: float, _dt: float) -> void:
	var local := Vector2(predictor.m.x, predictor.m.z)
	var fighting: bool = last_state.phase == "fight"
	var bush := Rules.bush_at(world.map, local.x, local.y)
	world.reveal_around(local.x, local.y, bush, cam.global_position)
	var hz := Rules.hazard_at(world.map, local.x, local.y)
	var in_well: bool = fighting and me.alive and not hz.is_empty()
	var burning: bool = in_well and hz.dps > 0
	var healing: bool = in_well and hz.hps > 0
	var text := ""
	if not me.alive:
		text = "Caíste — mirando a tus aliados"
	elif burning:
		text = "¡Te estás quemando en el magma!"
	elif healing:
		text = "El pozo lunar te cura"
	elif bush >= 0:
		text = "Oculto entre la vegetación"
	hud.status(text, burning)
	_target_frame(local)


func _target_frame(local: Vector2) -> void:
	var v: UnitView = views.get(controller.target)
	if v == null or v.snap.is_empty():
		hud.show_target({})
		return
	var s: Dictionary = v.snap
	var spec: Dictionary = GameData.classes[v.entry.cls]
	var basic := GameData.ability(my_cls, 0, my_spec)
	var d := Vector2(v.position.x - local.x, v.position.z - local.y).length()
	var in_sight := Rules.has_los(world.map, {"x": local.x, "z": local.y}, {"x": v.position.x, "z": v.position.z})
	var status := ""
	var kind := ""
	if not me.is_empty() and me.alive:
		if not v.shown:
			status = "Lo perdiste de vista"
			kind = "warn"
		elif d > basic.range + 1:
			status = "Fuera de alcance: acercate (%d / %d m)" % [roundi(d), roundi(basic.range)]
			kind = "bad"
		elif not in_sight:
			status = "Sin línea de visión"
			kind = "warn"
		else:
			status = ("Atacando con %s" % basic.name) if basic.get("auto", false) and bool(last_state.get("you", {}).get("auto", false)) else ("A tiro: clic derecho o tecla 1 para atacar" if basic.get("auto", false) else "A tiro: usá tus hechizos (%s)" % GameData.ability(my_cls, 0, my_spec).name)
			kind = "good"
	var friend: bool = v.entry.team == my_team
	if friend:
		status = ""
		kind = ""
	hud.show_target({
		"friend": friend, "name": v.entry.name, "cls": v.entry.cls, "hp": float(s.hp), "max_hp": float(spec.hp), "cast": s.cast,
		"effects": Effects.debuffs_of(s.cc) + Effects.buffs_of(s.buffs), "dist": ("%d m" % roundi(d)) if v.shown else "fuera de vista",
		"status": status, "status_kind": kind, "lost": not v.shown,
	})
