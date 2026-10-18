class_name PlayerController
extends RefCounted
## Casting and target selection of the local player, WoW style (no crosshair): one selected target, spells use it
## according to their kind (see SpellKinds); ground spells use a reticle; the auto-attack is a toggle.
## Free of scene/UI so it can be tested headless.
##
## ctx given to the calls: {now, alive, phase, units: [{id,team,x,z,alive,visible,incap}], pos: Vector2, fwd: Vector2 (character
## facing), my_id, mouse_ground: Vector2, auto_on: bool, los: Callable(Vector2 from, Vector2 to) -> bool (optional)}.

const QUEUE_WINDOW := 450.0
const QUEUE_LIFE := 700.0
## A spell pressed this close to the end of the current cast is queued (WoW spell queue); earlier presses are ignored.
const CAST_QUEUE_WINDOW := 400.0
## Radius for auto-selecting an enemy when a melee ability / auto-attack is used with no target.
const MELEE_PICK_RADIUS := 8.0

var cls := "mage"
var spec_id := ""
var team := "red"
## Selected unit (enemy or ally), -1 = none.
var target := -1
## Slot waiting for a ground click, -1 = none.
var pending_ground := -1
## Absolute local times (ms) when each slot comes off cooldown.
var ready_at: Array = []
var cast_lock: Array = []
var queued := {}
var last_range_warn := -1e9
var _cast_warned := false


func setup(p_cls: String, p_team: String, p_spec := "") -> void:
	cls = p_cls
	spec_id = GameData.normalize_spec(p_cls, p_spec)
	team = p_team
	target = -1
	pending_ground = -1
	queued = {}
	ready_at = []
	cast_lock = []
	for i in int(GameData.C.SLOT_COUNT):
		ready_at.append(0.0)
		cast_lock.append(0.0)


func ability(slot: int) -> Dictionary:
	return GameData.ability(cls, slot, spec_id)


func has_auto() -> bool:
	return ability(0).get("auto", false)


## Cooldowns reported by the server (ms remaining per slot).
func sync_cooldowns(cds: Array, now_ms: float) -> void:
	for i in cds.size():
		if not ability(i).get("ult", false):
			ready_at[i] = now_ms + float(cds[i])


func _unit(ctx: Dictionary, id: int) -> Dictionary:
	for u in ctx.units:
		if u.id == id:
			return u
	return {}


func target_unit(ctx: Dictionary) -> Dictionary:
	var u := _unit(ctx, target)
	return u if not u.is_empty() and u.alive and u.visible else {}


func is_friend(u: Dictionary) -> bool:
	return not u.is_empty() and u.team == team


# ---------------------------------------------------------------- selection

func select(id: int, _ctx := {}) -> void:
	target = id


func clear_target() -> void:
	target = -1
	pending_ground = -1


## Tab: nearest-to-the-front enemies first, cycling outward. Returns false when there is nobody.
func cycle_target(ctx: Dictionary) -> bool:
	var id := TargetLogic.cycle(ctx.units, team, ctx.pos, ctx.fwd, target if not is_friend(_unit(ctx, target)) else -1)
	if id < 0:
		return false
	target = id
	return true


## Drops a dead target (the server turns the auto-attack off by itself).
func maintain_target(ctx: Dictionary) -> void:
	if target >= 0:
		var u := _unit(ctx, target)
		if u.is_empty() or not u.alive:
			target = -1


## Right click (without drag) on a unit: select it, and start the auto-attack on enemies for classes that have one.
## Returns {"auto": "start"|"stop"|""}.
func right_click_unit(id: int, ctx: Dictionary) -> Dictionary:
	target = id
	var u := _unit(ctx, id)
	if is_friend(u):
		return {"auto": "stop"}
	if has_auto() and not u.is_empty() and u.alive:
		return {"auto": "start"}
	return {"auto": ""}


# ---------------------------------------------------------------- casting

func _res() -> Dictionary:
	return {"msg": {}, "error": "", "aim_dir": Vector2.ZERO, "auto": "", "pending_ground": false}


func _dist_to(ctx: Dictionary, u: Dictionary) -> float:
	return Vector2(u.x - ctx.pos.x, u.z - ctx.pos.y).length()


func _sight(ctx: Dictionary, u: Dictionary) -> bool:
	var f = ctx.get("los")
	return f == null or f.call(ctx.pos, Vector2(u.x, u.z))


## Tries the ability in `slot`. See _res() for the result shape.
func try_cast(slot: int, ctx: Dictionary) -> Dictionary:
	var res := _res()
	if not ctx.alive:
		return res
	var spec := ability(slot)
	var kind := SpellKinds.kind(spec)
	var now: float = ctx.now
	# Only buffs/shields are allowed in the start room; everything else needs the fight.
	if ctx.phase != "fight" and not (ctx.phase == "prep" and spec.id in ArenaMatch.PREP_OK):
		return res
	var cur = ctx.get("cast")
	if cur != null:
		# A cast is in progress: key presses never cancel it. Same spell: ignore. Another one: queue near the end, else ignore.
		if slot != int(cur.slot) and kind != "auto":
			if float(cur.left) <= CAST_QUEUE_WINDOW:
				queued = {"slot": slot, "at": now}
			elif not _cast_warned:
				_cast_warned = true
				res.error = "Ya estás lanzando"
		return res
	_cast_warned = false
	if now < cast_lock[slot]:
		return res
	if kind == "auto":
		return _toggle_auto(ctx, res)
	var wait: float = ready_at[slot] - now
	if not spec.get("ult", false) and wait > 60.0:
		if wait <= QUEUE_WINDOW:
			queued = {"slot": slot, "at": now}
		else:
			res.error = "%s: faltan %.1f s" % [spec.name, wait / 1000.0]
		return res
	var pos: Vector2 = ctx.pos
	match kind:
		"self":
			res.msg = {"slot": slot, "ax": pos.x, "az": pos.y, "target": -1}
		"direction":
			var tu := target_unit(ctx)
			var aim: Vector2 = pos + ctx.fwd * 12.0
			# Movement abilities (Blink, Disengage) follow your facing, like WoW; only Volley aims at the target.
			if not tu.is_empty() and not is_friend(tu) and not spec.id in ["blink", "disengage"]:
				aim = Vector2(tu.x, tu.z)
			res.msg = {"slot": slot, "ax": aim.x, "az": aim.y, "target": -1}
			res.aim_dir = aim - pos
		"ground":
			pending_ground = slot
			res.pending_ground = true
			return res
		"friendly":
			var fu := target_unit(ctx)
			var id: int = fu.id if (not fu.is_empty() and is_friend(fu)) else _best_heal_target(ctx, spec.range)
			var friend := _unit(ctx, id)
			if id != ctx.my_id and (_dist_to(ctx, friend) > spec.range + 1):
				res.error = "%s: Fuera de alcance" % spec.name
				return res
			if id != ctx.my_id and not _sight(ctx, friend):
				res.error = "No está a la vista"
				return res
			res.msg = {"slot": slot, "ax": friend.get("x", pos.x), "az": friend.get("z", pos.y), "target": id}
		_:  # hostile
			var e := target_unit(ctx)
			if e.is_empty() and target < 0 or (e.is_empty() and _unit(ctx, target).is_empty()):
				e = _auto_select(ctx, spec)
			if e.is_empty():
				res.error = "No tenés objetivo"
				return res
			if is_friend(e):
				res.error = "Objetivo inválido: es un aliado"
				return res
			var d := _dist_to(ctx, e)
			if spec.range > 0 and d > spec.range + 1:
				if now - last_range_warn > 1200.0:
					res.error = "%s: Fuera de alcance (%d m / %d m)" % [spec.name, roundi(d), roundi(spec.range)]
					last_range_warn = now
				return res
			if not _sight(ctx, e):
				res.error = "No está a la vista"
				return res
			res.msg = {"slot": slot, "ax": e.x, "az": e.z, "target": e.id}
			res.aim_dir = Vector2(e.x, e.z) - pos
			if has_auto() and not ctx.get("auto_on", false):
				res.auto = "start"  # any ability on a hostile target also starts the auto-attack (WoW)
	cast_lock[slot] = now + 250.0
	return res


## No (valid) target: selects the nearest living, visible enemy in front of you within reach of the ability
## (a small radius for melee), like WoW. Returns the unit or {}.
func _auto_select(ctx: Dictionary, spec: Dictionary) -> Dictionary:
	var radius: float = MELEE_PICK_RADIUS if (spec.get("melee", false) or float(spec.get("range", 0)) <= 5.0) else float(spec.range)
	var best := {}
	var bd := 1e9
	for u in ctx.units:
		if u.team == team or not u.alive or not u.visible or u.id == ctx.my_id:
			continue
		var off := Vector2(u.x - ctx.pos.x, u.z - ctx.pos.y)
		var d := off.length()
		if d > radius or (d > 0.5 and (ctx.fwd as Vector2).dot(off / d) < (-0.5 if d <= 4.0 else 0.2)) or not _sight(ctx, u):
			continue
		if d < bd:
			bd = d
			best = u
	if not best.is_empty():
		target = best.id
	return best


## Heal with no ally selected: the most wounded ally (or you) in range, else you.
func _best_heal_target(ctx: Dictionary, range_m: float) -> int:
	var best: int = ctx.my_id
	var worst := 0.999
	for u in ctx.units:
		if u.team != team or not u.alive or not u.visible:
			continue
		var ratio := float(u.get("hp", 1.0))
		if ratio >= worst:
			continue
		if u.id != ctx.my_id and (_dist_to(ctx, u) > range_m + 1 or not _sight(ctx, u)):
			continue
		worst = ratio
		best = u.id
	return best


func _toggle_auto(ctx: Dictionary, res: Dictionary) -> Dictionary:
	if ctx.get("auto_on", false):
		res.auto = "stop"
		return res
	var e := target_unit(ctx)
	if e.is_empty():
		e = _auto_select(ctx, ability(0))
	if e.is_empty():
		res.error = "No tenés objetivo"
	elif is_friend(e):
		res.error = "Objetivo inválido: es un aliado"
	else:
		res.auto = "start"
	return res


## Confirms the pending ground spell at the point under the cursor (clamped to the spell's range).
func confirm_ground(point: Vector2, ctx: Dictionary) -> Dictionary:
	var res := _res()
	if pending_ground < 0:
		return res
	var slot := pending_ground
	pending_ground = -1
	var spec := ability(slot)
	var pos: Vector2 = ctx.pos
	var off := point - pos
	if spec.range > 0 and off.length() > spec.range:
		point = pos + off.normalized() * spec.range
	res.msg = {"slot": slot, "ax": point.x, "az": point.y, "target": -1}
	cast_lock[slot] = ctx.now + 250.0
	return res


func cancel_ground() -> void:
	pending_ground = -1


## Spell queue: returns the slot to retry now, or -1.
func poll_queue(now: float, casting := false) -> int:
	if queued.is_empty():
		return -1
	if casting:
		return -1  # wait for the cast in progress to finish
	if now - queued.at > QUEUE_LIFE:
		queued = {}
		return -1
	if now >= ready_at[queued.slot] - 30.0:
		var s: int = queued.slot
		queued = {}
		return s
	return -1
