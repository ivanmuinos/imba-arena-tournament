class_name AcademyStore
extends RefCounted
## What the player did in the Academia: the best medal and time of each lesson, and whether it was already offered.
## Lessons no longer in the catalog stay in the file, so going back to an older build does not lose them.

const PATH := "user://academy.json"
const VERSION := 1

static var _shared: AcademyStore = null

var path := PATH
var offered := false
var lessons := {}  # lesson id -> {medal, best_ms, plays}


static func shared() -> AcademyStore:
	if _shared == null:
		_shared = AcademyStore.new(PATH, bool(SettingsStore.shared().get_value("tutorial_seen")))
	return _shared


## `already_seen`: with no file yet, whoever saw the old tutorial is not offered the Academia as a first-timer.
func _init(p_path := PATH, already_seen := false) -> void:
	path = p_path
	offered = already_seen
	load_file()


func load_file() -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	offered = bool(parsed.get("offered", offered))
	if typeof(parsed.get("lessons")) != TYPE_DICTIONARY:
		return
	for id in parsed.lessons:
		var raw = parsed.lessons[id]
		if typeof(raw) == TYPE_DICTIONARY:
			lessons[str(id)] = {
				"medal": clampi(int(raw.get("medal", 0)), AcademyMedals.NONE, AcademyMedals.GOLD),
				"best_ms": maxf(0.0, float(raw.get("best_ms", 0.0))),
				"plays": maxi(0, int(raw.get("plays", 0))),
			}


func save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"_v": VERSION, "offered": offered, "lessons": lessons}))


func mark_offered() -> void:
	offered = true


func medal(id: String) -> int:
	return int(lessons.get(id, {}).get("medal", 0))


func best_ms(id: String) -> float:
	return float(lessons.get(id, {}).get("best_ms", 0.0))


func plays(id: String) -> int:
	return int(lessons.get(id, {}).get("plays", 0))


func played(id: String) -> bool:
	return plays(id) > 0


## Adds a run. A run without a medal (it skipped a step) marks the lesson as seen and nothing else.
## Returns whether it beat the player's best. The caller saves.
func record(id: String, new_medal: int, ms: float) -> bool:
	var e: Dictionary = lessons.get(id, {"medal": 0, "best_ms": 0.0, "plays": 0})
	e.plays = int(e.plays) + 1
	lessons[id] = e
	if new_medal <= AcademyMedals.NONE:
		return false
	var better_medal := new_medal > int(e.medal)
	var better_time := float(e.best_ms) <= 0.0 or ms < float(e.best_ms)
	e.medal = maxi(int(e.medal), new_medal)
	if better_time:
		e.best_ms = ms
	return better_medal or (new_medal == int(e.medal) and better_time)
