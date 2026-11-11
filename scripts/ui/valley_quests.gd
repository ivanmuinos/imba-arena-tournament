class_name ValleyQuests
extends Node
## Tizón as a quest giver: a "!" over his head while he has a quest for you, the offer when you walk up to him, the quest on
## screen once you take it, a "?" while he waits for you to come back, and the next one after you hand it in.

const LEAVE := 9.0  # walking this far from Tizón closes his offer, and lets him offer again

var mv: MatchView
var view: ValleyHud
var overlay: QuestOverlay
var offer: LessonCard
var offered := ""
var snoozed := false
var mark: Label3D
var _t := 0.0


func attach(p_mv: MatchView, p_view: ValleyHud) -> void:
	mv = p_mv
	view = p_view
	mv.add_child(self)
	mark = Label3D.new()
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.font = UiKit.display(700)
	mark.font_size = 160
	mark.outline_size = 36
	mark.outline_modulate = Color(0.1, 0.05, 0.0)
	mark.pixel_size = 0.008
	mark.no_depth_test = true
	mark.render_priority = 2
	mv.world.add_child(mark)


## What Tizón shows over his head: "!" a quest for you, "?" he waits for you (gold: come now), "" nothing.
static func mark_for(has_quest: bool, active: bool, step: Dictionary) -> String:
	if active:
		return "" if step.get("final", false) else "?"
	return "!" if has_quest else ""


func _process(delta: float) -> void:
	if mv == null or mv.me.is_empty():
		return
	_t += delta
	var dist := Vector2(mv.predictor.m.x, mv.predictor.m.z).distance_to(GameMap.TIZON_AT)
	var next := AcademyValley.next_quest(AcademyStore.shared())
	if overlay == null:
		if dist > LEAVE:
			snoozed = false
			_close_offer()
		elif offer == null and not snoozed and dist <= QuestOverlay.NEAR:
			_offer(next)
		view.minimap.goal = GameMap.TIZON_AT if next != "" and offer == null else Vector2.INF
	else:
		view.minimap.goal = overlay.goal_world()
	var step: Dictionary = overlay.flow.current() if overlay != null else {}
	mark.text = mark_for(next != "", overlay != null, step)
	mark.modulate = Color("#ffd23a") if overlay == null or str(step.get("id", "")) == "back" else Color("#b8b0a4")
	mark.position = Vector3(GameMap.TIZON_AT.x, mv.world.h(GameMap.TIZON_AT.x, GameMap.TIZON_AT.y) + 3.2 + sin(_t * 2.6) * 0.12, GameMap.TIZON_AT.y)


## Tizón's card when you walk up to him: the next quest, or the list to repeat when he has no new one.
func _offer(id: String) -> void:
	offered = id
	offer = LessonCard.new()
	mv.hud.add_overlay(offer, 142.0, 12.0, false)
	offer.set_coach("contenta" if id != "" else "orgullosa")
	if id != "":
		var info := AcademyCatalog.info(id)
		offer.show_step("Tizón · Misión nueva", str(info.get("title", id)), AcademyValley.pitch(id), [])
		offer.set_status("Recompensa: medalla · %d min" % int(info.get("mins", 1)), UiKit.GOLD)
		offer.add_button("Aceptar", "primary", func(): accept(id))
		offer.add_button("Ahora no", "ghost", _snooze)
		return
	offer.show_step("Tizón", "Por ahora, eso es todo", "No tengo más misiones todavía: pronto vas a tener trabajo por todo el valle. Mientras tanto podés repetir cualquiera para mejorar tu medalla.", [])
	for q in AcademyValley.QUESTS:
		var again := str(q)
		offer.add_button(str(AcademyCatalog.info(again).get("title", again)).split(" ")[0], "secondary", func(): accept(again))
	offer.add_button("Cerrar", "ghost", _snooze)


func _snooze() -> void:
	snoozed = true
	_close_offer()


func _close_offer() -> void:
	if offer != null and is_instance_valid(offer):
		offer.queue_free()
	offer = null


## Takes a quest: its card replaces Tizón's offer and stays until it is handed in or dropped.
func accept(id: String) -> void:
	var flow := AcademyValley.quest(id, mv.my_cls, mv.my_spec)
	if flow == null or overlay != null:
		return
	_close_offer()
	overlay = QuestOverlay.new()
	overlay.attach(mv, flow)
	overlay.finished.connect(_on_finished)
	if mv.audio != null:
		mv.audio.play("fight")


func _on_finished(action: String) -> void:
	var id := (overlay.flow as LessonFlow).id
	overlay.close()
	overlay = null
	snoozed = true  # he does not talk over the result: walk away and back, or take the next one from the card
	if action == "next" and AcademyValley.after(id) != "":
		accept.call_deferred(AcademyValley.after(id))
