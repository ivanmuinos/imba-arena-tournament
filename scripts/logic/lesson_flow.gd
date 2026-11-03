class_name LessonFlow
extends StepFlow
## One Academia lesson: its steps plus what the medals need. Time only runs on steps with objectives, so reading costs nothing.

var id := ""
var title := ""
var chapter := ""
var scenario := ""
var active_ms := 0.0
var skipped := 0


func _init(p_id := "", p_title := "", p_chapter := "", p_scenario := "") -> void:
	id = p_id
	title = p_title
	chapter = p_chapter
	scenario = p_scenario


func tick(ms: float) -> void:
	if not finished and not current().manual:
		active_ms += ms


## "Saltar paso" on a step with objectives counts as skipping it; "Continuar" on an information step does not.
func next() -> void:
	if not finished and not current().manual:
		skipped += 1
	super.next()
