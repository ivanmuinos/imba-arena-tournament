class_name QuestOverlay
extends LessonOverlay
## A quest of the valley on screen: a lesson whose card stays while you walk the map, that ends by going back to Tizón and
## that leaves the valley running when it is over. finished: "next" | "free" (keep exploring) | "menu" (dropped).

## How close to Tizón counts as talking to him.
const NEAR := 5.5


func _process(delta: float) -> void:
	super._process(delta)
	if flow == null or mv == null or mv.me.is_empty() or flow.is_done():
		return
	if Vector2(mv.predictor.m.x, mv.predictor.m.z).distance_to(GameMap.TIZON_AT) <= NEAR:
		push("tizon")


func _refresh() -> void:
	super._refresh()
	for b in _card.buttons.get_children():
		if b is Button and (b as Button).text == "Salir":
			(b as Button).text = "Abandonar"


func _final_buttons(f: LessonFlow) -> void:
	if AcademyValley.after(f.id) != "":
		_card.add_button("Siguiente misión", "primary", func(): finished.emit("next"))
		_card.add_button("Seguir explorando", "ghost", func(): finished.emit("free"))
	else:
		_card.add_button("Seguir explorando", "primary", func(): finished.emit("free"))


func arrow_anchor() -> Dictionary:
	if str(flow.current().get("arrow", "")) != "tizon":
		return super.arrow_anchor()
	var at := Vector3(GameMap.TIZON_AT.x, mv.world.h(GameMap.TIZON_AT.x, GameMap.TIZON_AT.y) + 3.4, GameMap.TIZON_AT.y)
	if mv.cam.is_position_behind(at):
		return {}
	var screen := mv.get_viewport().get_visible_rect().size
	return {"pos": clear_of(mv.cam.unproject_position(at).clamp(Vector2(60, 60), screen - Vector2(60, 60)), _card.get_global_rect()), "dir": Vector2.DOWN}


## Where the current step sends you, for the minimap (Vector2.INF: nowhere in particular).
func goal_world() -> Vector2:
	if flow == null or flow.is_done():
		return Vector2.INF
	return goal_of(flow.current(), mv.world.map, func(unit_name: String) -> Vector2:
		var v := _named_view(unit_name)
		return Vector2(v.position.x, v.position.z) if v != null else Vector2.INF)


## The place a step points at: a plate, Tizón, or a unit by name (`where_is` finds it).
static func goal_of(step: Dictionary, map: GameMap, where_is: Callable) -> Vector2:
	var key := str(step.get("arrow", ""))
	if step.get("final", false):
		return Vector2.INF
	if key == "tizon":
		return GameMap.TIZON_AT
	if key.begins_with("plate:"):
		var n := int(key.substr(6))
		return Vector2(map.plates[n].x, map.plates[n].z) if n >= 0 and n < map.plates.size() else Vector2.INF
	if key.begins_with("unit:"):
		return where_is.call(key.substr(5))
	return Vector2.INF
