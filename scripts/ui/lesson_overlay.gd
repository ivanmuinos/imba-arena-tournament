class_name LessonOverlay
extends TutorialOverlay
## A guided step card over an Academia lesson. On top of the tutorial's overlay: objectives also tick from the server's journal, each
## step can tell the scenario to set up its part (`cue`), and the clock of the medals runs here. finished: "retry" | "menu".


func attach(p_mv: MatchView, p_flow: StepFlow) -> void:
	super.attach(p_mv, p_flow)
	if mv.client != null:
		mv.client.lesson_events.connect(_on_lesson_events)


func _on_lesson_events(list: Array) -> void:
	for ev in list:
		for key in LessonEvents.keys(ev, mv.my_id):
			push(key)


func _step_entered(s: Dictionary) -> void:
	if int(s.get("cue", -1)) >= 0 and mv.client != null:
		mv.client.send_cue(int(s.cue))


func _final_card(_s: Dictionary) -> void:
	_card.add_button("Repetir", "primary", func(): finished.emit("retry"))
	_card.add_button("Menú", "ghost", func(): finished.emit("menu"))


func _process(delta: float) -> void:
	super._process(delta)
	if flow != null and mv != null and not mv.game_menu.visible:
		(flow as LessonFlow).tick(delta * 1000.0)
