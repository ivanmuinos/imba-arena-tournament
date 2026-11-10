class_name LessonOverlay
extends TutorialOverlay
## A guided step card over an Academia lesson. On top of the tutorial's overlay: Tizón speaks on the card, objectives also
## tick from the server's journal, each step can tell the scenario to set up its part (`cue`), the clock of the medals runs
## here and the lesson closes with the medal it earned. finished: "retry" | "next" | "menu".

## What Tizón says about a result, by medal.
const CLOSING := [
	"Che, sin saltear pasos la próxima.",
	"Aprobado. Se puede más rápido y más limpio, ¿eh?",
	"¡Muy bien! Te faltó poquito para el oro.",
	"¡Impecable! Ni yo lo hacía así de joven.",
]
const CLOSING_MOOD := ["burlona", "neutral", "contenta", "orgullosa"]
const TITLES := ["Lección vista", "Medalla de bronce", "Medalla de plata", "¡Medalla de oro!"]

var last_hp_pct := -1.0
var last_medal := AcademyMedals.NONE
var last_best := false
var _status_t := 0.0


func attach(p_mv: MatchView, p_flow: StepFlow) -> void:
	super.attach(p_mv, p_flow)
	if mv.client != null:
		mv.client.lesson_events.connect(_on_lesson_events)


func _on_lesson_events(list: Array) -> void:
	for ev in list:
		(flow as LessonFlow).note_event(ev, mv.my_id)
		for key in LessonEvents.keys(ev, mv.my_id):
			push(key)


## An objective got ticked or the step moved on: a small sound, so progress is heard without looking at the card.
func _after_change() -> void:
	if mv != null and mv.audio != null and not flow.current().get("final", false):
		mv.audio.play("tick")
	super._after_change()


func _step_entered(s: Dictionary) -> void:
	if int(s.get("cue", -1)) >= 0 and mv.client != null:
		mv.client.send_cue(int(s.cue))


func _decorate(s: Dictionary) -> void:
	var f := flow as LessonFlow
	_card._caption.text = "Tizón · %s · %d de %d" % [f.title, flow.index + 1, flow.steps.size()]
	_card.set_coach(str(s.get("mood", "neutral")))
	_card.set_progress(flow.index, flow.steps.size())
	_show_status()


func _show_status() -> void:
	var f := flow as LessonFlow
	if f.finished or f.current().get("final", false) or f.medal_rule.is_empty():
		_card.set_status("")
		return
	var stats := f.stats(1.0)
	var medal := AcademyMedals.still_possible(f.medal_rule, stats)
	_card.set_status(AcademyMedals.live_text(f.medal_rule, stats), AcademyMedals.COLORS[medal].lightened(0.15) if medal > AcademyMedals.NONE else UiKit.MUTED)


func _final_card(_s: Dictionary) -> void:
	var f := flow as LessonFlow
	var words := _record_run()
	_card._caption.text = "Tizón · %s" % f.title
	_card.set_title(str(TITLES[last_medal]))
	_card.set_coach(str(CLOSING_MOOD[last_medal]))
	_card.set_text("%s\n%s" % [str(CLOSING[last_medal]), words])
	var badge := _card.show_result(last_medal, _result_rows(f), _next_goal(f))
	if last_medal > AcademyMedals.NONE and badge != null:
		mv.audio.play("win")
	mv.hud.center_overlay(_card)
	var has_next := AcademyCatalog.after(f.id) != ""
	if has_next:
		_card.add_button("Siguiente lección", "primary", func(): finished.emit("next"))
	_card.add_button("Repetir", "secondary" if has_next else "primary", func(): finished.emit("retry"))
	_card.add_button("Academia", "ghost", func(): finished.emit("menu"))


## The numbers of the run that its medals look at, plus the time.
func _result_rows(f: LessonFlow) -> Array:
	var rows: Array = [["Tiempo", AcademyMedals.time_text(f.active_ms)]]
	var asked := {}
	for level in f.medal_rule:
		for c in f.medal_rule[level]:
			asked[str(c)] = true
	if asked.has("max_taken"):
		rows.append(["Daño recibido", str(int(f.taken))])
	if asked.has("max_mistakes"):
		rows.append(["Errores", str(f.mistakes)])
	if asked.has("max_downs"):
		rows.append(["Caídas", str(f.downs)])
	if asked.has("min_hp_pct"):
		rows.append(["Vida al final", "%d%%" % int(last_hp_pct * 100.0)])
	return rows


func _next_goal(f: LessonFlow) -> String:
	if last_medal >= AcademyMedals.GOLD:
		return "No hay medalla más alta que esta."
	var next := maxi(last_medal + 1, AcademyMedals.BRONZE)
	return "Medalla de [b]%s[/b]: %s." % [str(AcademyMedals.NAMES[next]).to_lower(), AcademyMedals.goal_text(f.medal_rule, next)]


## Grades the run and keeps it. Saved here, not on the button: closing the game on the last card must not lose the medal.
func _record_run() -> String:
	var f := flow as LessonFlow
	var hp := float(mv.me.get("hp", 0.0)) / maxf(GameData.entry_max_hp((mv.views[mv.my_id] as UnitView).entry), 1.0)
	last_hp_pct = hp
	last_medal = AcademyMedals.grade(f.medal_rule, f.stats(hp))
	var store := AcademyStore.shared()
	last_best = store.record(f.id, last_medal, f.active_ms)
	store.mark_offered()
	store.save()
	return AcademyMedals.result_text(last_medal, f.active_ms, last_best)


func _process(delta: float) -> void:
	super._process(delta)
	if flow == null or mv == null or mv.game_menu.visible:
		return
	(flow as LessonFlow).tick(delta * 1000.0)
	_status_t += delta
	if _status_t >= 0.25:
		_status_t = 0.0
		_show_status()
