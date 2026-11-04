class_name LessonFlow
extends StepFlow
## One Academia lesson: its steps plus what the medals need. Time only runs on steps with objectives, so reading costs nothing.

var id := ""
var title := ""
var chapter := ""
var scenario := ""
var active_ms := 0.0
var skipped := 0
var medal_rule := {}  # see AcademyMedals
var mistake_keys: Array = []  # LessonEvents keys that count as a named mistake of this lesson
var mistakes := 0
var taken := 0.0
var downs := 0


func _init(p_id := "", p_title := "", p_chapter := "", p_scenario := "") -> void:
	id = p_id
	title = p_title
	chapter = p_chapter
	scenario = p_scenario


## One entry of the server's journal, for the medals.
func note_event(ev: Dictionary, me: int) -> void:
	var e := str(ev.get("e", ""))
	if e == "dmg" and int(ev.get("t", -1)) == me:
		taken += float(ev.get("amt", 0.0))
	elif e == "down" and int(ev.get("t", -1)) == me:
		downs += 1
	for key in LessonEvents.keys(ev, me):
		if mistake_keys.has(key):
			mistakes += 1


func stats(hp_pct: float) -> Dictionary:
	return {"skipped": skipped, "time_ms": active_ms, "mistakes": mistakes, "taken": taken, "downs": downs, "hp_pct": hp_pct}


func tick(ms: float) -> void:
	if not finished and not current().manual:
		active_ms += ms


## "Saltar paso" on a step with objectives counts as skipping it; "Continuar" on an information step does not.
func next() -> void:
	if not finished and not current().manual:
		skipped += 1
	super.next()
