class_name TutorialOverlay
extends Node
## Guided tutorial card drawn over the practice yard: the current step with a checklist, highlighted keys and an arrow pointing
## at the HUD element (or the dummy) being taught. It turns gameplay into TutorialFlow events (MatchView.gameplay_event plus a few
## polled conditions: walking, hiding from the caster, crowd control on a dummy, a debuff on the target, a tooltip).

signal finished(action: String)  # "arena" | "bots" | "menu"

var flow: StepFlow
var mv: MatchView

var _card: LessonCard
var _buttons: HBoxContainer
var _layer: CanvasLayer
var _arrows: Control
var _shown_step := -1
var _walked := Vector2.INF
var _hidden_for := 0.0
var _t := 0.0
var _cc_seen := {}


func attach(p_mv: MatchView, p_flow: StepFlow) -> void:
	mv = p_mv
	flow = p_flow
	mv.add_child(self)
	_build()
	mv.gameplay_event.connect(push)
	_refresh()


func _build() -> void:
	_card = LessonCard.new()
	_buttons = _card.buttons
	mv.hud.add_overlay(_card, 142.0, 12.0, false)
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)
	_arrows = Control.new()
	_arrows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrows.draw.connect(_draw_arrow)
	_layer.add_child(_arrows)


func push(event: String) -> void:
	if flow == null or flow.is_done():
		return
	if flow.push(event):
		_after_change()


func _after_change() -> void:
	if flow.is_done():
		finished.emit("menu")
		return
	_refresh()


func _refresh() -> void:
	var s := flow.current()
	if flow.index != _shown_step:
		_shown_step = flow.index
		_hidden_for = 0.0
		_walked = Vector2.INF
		_cc_seen.clear()
		if s.on_enter in ["ult", "stun"] and mv.client != null:
			mv.client.send_practice(s.on_enter)
		_step_entered(s)
	_card.show_step("Paso %d de %d" % [flow.index + 1, flow.steps.size()], str(s.title), str(s.text), s.objectives)
	if s.get("final", false):
		_final_card(s)
		return
	if s.manual:
		_card.add_button("Continuar", "primary", func():
			flow.next()
			_after_change())
	else:
		_card.add_button("Saltar paso", "ghost", func():
			flow.next()
			_after_change())
	_card.add_button("Salir", "ghost", func(): finished.emit("menu"))


## A new step just became current.
func _step_entered(_s: Dictionary) -> void:
	pass


## The buttons (and last words) of the final step.
func _final_card(_s: Dictionary) -> void:
	_card.add_button("Arena de práctica", "primary", func(): finished.emit("arena"))
	_card.add_button("Contra bots", "secondary", func(): finished.emit("bots"))
	_card.add_button("Menú", "ghost", func(): finished.emit("menu"))
	_card.set_text("¡Listo! Probá la [b]Arena de práctica[/b] para repetir rotaciones con medidor de daño, o jugá contra bots.")
	_card.set_title("¡Listo!")


func _process(delta: float) -> void:
	if flow == null or mv == null or flow.is_done() or mv.me.is_empty():
		return
	_t += delta
	var pos := Vector2(mv.predictor.m.x, mv.predictor.m.z)
	if _walked == Vector2.INF:
		_walked = pos
	elif pos.distance_to(_walked) > 5.0:
		push("moved")
	if bool(mv.last_state.get("you", {}).get("auto", false)):
		push("auto_on")
	if mv.hud.tooltip_slot() >= 0:
		push("tooltip")
	var caster := _dummy_view("caster")
	if caster != null and caster.shown:
		var hidden := not Rules.has_los(mv.world.map, {"x": pos.x, "z": pos.y}, {"x": caster.position.x, "z": caster.position.z})
		_hidden_for = _hidden_for + delta if hidden else 0.0
		if _hidden_for > 0.8:
			push("los_hidden")
	var tid: int = mv.controller.target
	for id in mv.views:
		var v: UnitView = mv.views[id]
		if v.snap.is_empty() or str(v.entry.get("dummy", "")) == "" or v.entry.team == mv.my_team:
			continue
		var cc: Dictionary = v.snap.cc
		var controlled := false
		for k in ["stun", "root", "slow", "fear", "silence", "incap"]:
			controlled = controlled or cc.has(k)
		if controlled:
			push("cc")
		if id == tid and not cc.is_empty():
			push("debuff_seen")
	_arrows.queue_redraw()


func _dummy_view(kind: String) -> UnitView:
	for id in mv.views:
		var v: UnitView = mv.views[id]
		if str(v.entry.get("dummy", "")) == kind:
			return v
	return null


## Where the current step points: a HUD rectangle ("bar", "target_panel", ...) or a dummy in the world ("dummy:caster").
func arrow_anchor() -> Dictionary:
	var key := str(flow.current().get("arrow", ""))
	if key == "":
		return {}
	if key.begins_with("plate:"):
		var plates: Array = mv.world.map.plates
		var n := int(key.substr(6))
		if n < 0 or n >= plates.size():
			return {}
		var at := Vector3(plates[n].x, 0.0, plates[n].z)
		if mv.cam.is_position_behind(at):
			return {}
		var screen := mv.get_viewport().get_visible_rect().size
		var pos := mv.cam.unproject_position(at + Vector3(0, 1.2, 0))
		return {"pos": pos.clamp(Vector2(60, 60), screen - Vector2(60, 60)), "dir": Vector2.DOWN}  # off screen it stays at the edge, on that side
	if key.begins_with("dummy:"):
		var v := _dummy_view(key.substr(6))
		if v == null or not v.shown or mv.cam.is_position_behind(v.position + Vector3(0, 2.0, 0)):
			return {}
		return {"pos": mv.cam.unproject_position(v.position + Vector3(0, 3.1, 0)), "dir": Vector2.DOWN}
	var r := mv.hud.rect_of(key)
	if r.size == Vector2.ZERO:
		return {}
	if key == "target_panel" or key == "score":
		return {"pos": Vector2(r.position.x + r.size.x * 0.5, r.end.y + 6.0), "dir": Vector2.UP}
	return {"pos": Vector2(r.position.x + r.size.x * 0.5, r.position.y - 8.0), "dir": Vector2.DOWN}


func _draw_arrow() -> void:
	var a := arrow_anchor()
	if a.is_empty():
		return
	var bob := sin(_t * 6.0) * 6.0
	var dir: Vector2 = a.dir
	var tip: Vector2 = a.pos - dir * (4.0 + bob) if dir == Vector2.DOWN else a.pos - dir * (4.0 + bob)
	var side := Vector2(-dir.y, dir.x)
	var base := tip - dir * 26.0
	var pts := PackedVector2Array([tip, base + side * 15.0, base - side * 15.0])
	_arrows.draw_colored_polygon(pts, Color("#ffc15a"))
	_arrows.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color("#1a0800"), 3.0)
