class_name LessonOverlay
extends TutorialOverlay
## A guided step card over an Academia lesson. On top of the tutorial's overlay: objectives also tick from the server's journal, each
## step can tell the scenario to set up its part (`cue`), and the clock of the medals runs here. finished: "retry" | "menu".


var last_hp_pct := -1.0


func attach(p_mv: MatchView, p_flow: StepFlow) -> void:
	super.attach(p_mv, p_flow)
	if mv.client != null:
		mv.client.lesson_events.connect(_on_lesson_events)


func _on_lesson_events(list: Array) -> void:
	for ev in list:
		(flow as LessonFlow).note_event(ev, mv.my_id)
		for key in LessonEvents.keys(ev, mv.my_id):
			push(key)


func _step_entered(s: Dictionary) -> void:
	if int(s.get("cue", -1)) >= 0 and mv.client != null:
		mv.client.send_cue(int(s.cue))


func _final_card(_s: Dictionary) -> void:
	_card.set_text(_record_run())
	_card.add_button("Repetir", "primary", func(): finished.emit("retry"))
	_card.add_button("Menú", "ghost", func(): finished.emit("menu"))


## Grades the run and keeps it. Saved here, not on the button: closing the game on the last card must not lose the medal.
func _record_run() -> String:
	var f := flow as LessonFlow
	var hp := float(mv.me.get("hp", 0.0)) / maxf(GameData.entry_max_hp((mv.views[mv.my_id] as UnitView).entry), 1.0)
	last_hp_pct = hp
	var medal := AcademyMedals.grade(f.medal_rule, f.stats(hp))
	var store := AcademyStore.shared()
	var best := store.record(f.id, medal, f.active_ms)
	store.mark_offered()
	store.save()
	return AcademyMedals.result_text(medal, f.active_ms, best)


func _process(delta: float) -> void:
	super._process(delta)
	if flow != null and mv != null and not mv.game_menu.visible:
		(flow as LessonFlow).tick(delta * 1000.0)
