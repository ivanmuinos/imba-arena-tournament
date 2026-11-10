class_name StepFlow
extends RefCounted
## A guided sequence as pure data + a tiny state machine (no nodes). A step has objectives that tick when gameplay events arrive;
## it advances by itself when they are all done. A step without objectives (`manual`) waits for next().
## Used by TutorialFlow and the Academia's LessonFlow.

var steps: Array = []
var index := 0
var finished := false


## An objective that needs `need` matching events.
static func obj(id: String, text: String, event: String, need := 1) -> Dictionary:
	return {"id": id, "text": text, "event": event, "done": false, "n": 0, "need": need}


func add_step(id: String, title: String, text: String, objectives: Array, extra := {}) -> void:
	var s := {"id": id, "title": title, "text": text, "objectives": objectives, "manual": objectives.is_empty(), "arrow": "", "on_enter": ""}
	s.merge(extra, true)
	steps.append(s)


func current() -> Dictionary:
	return steps[mini(index, steps.size() - 1)]


func is_done() -> bool:
	return finished


## Feeds a gameplay event. Returns true when something changed (an objective got checked or the step advanced).
func push(event: String) -> bool:
	if finished:
		return false
	var s := current()
	var changed := false
	for o in s.objectives:
		if not o.done and o.event == event:
			o.n = int(o.get("n", 0)) + 1
			o.done = o.n >= int(o.get("need", 1))
			changed = true
	if changed and not s.manual and _objectives_done(s):
		_advance()
	return changed


func _objectives_done(s: Dictionary) -> bool:
	for o in s.objectives:
		if not o.done:
			return false
	return true


## "Continuar" on information steps (and "Saltar" on any step).
func next() -> void:
	if finished:
		return
	_advance()


func _advance() -> void:
	if index >= steps.size() - 1:
		finished = true
		return
	index += 1


func progress() -> Vector2:
	return Vector2(index + 1, steps.size())


func objective_events() -> Array:
	var out: Array = []
	for o in current().objectives:
		if not o.done:
			out.append(o.event)
	return out
