class_name AcademyCatalog
extends RefCounted
## Every lesson of the Academia, by id and by chapter. Lessons are code, not data: their text depends on the player's real keys and kit.

## Chapters in teaching order. Nothing is locked: the order is only what the Academia suggests next.
const CHAPTERS := [
	{"id": "primeros_pasos", "title": "Primeros pasos", "blurb": "Moverte por la arena.", "lessons": [
		{"id": "moverse", "title": "Moverse"},
	]},
]


## A fresh LessonFlow for the player's kit, or null when there is no such lesson.
static func lesson(id: String, cls: String, spec := "") -> LessonFlow:
	match id:
		"moverse":
			return AcademyPrimerosPasos.moverse(cls, spec)
	return null


static func chapters() -> Array:
	return CHAPTERS


static func lesson_ids() -> Array:
	var out: Array = []
	for c in CHAPTERS:
		for l in c.lessons:
			out.append(str(l.id))
	return out


## The lesson after this one, in teaching order ("" for the last one and for unknown ids).
static func after(id: String) -> String:
	var ids := lesson_ids()
	var i := ids.find(id)
	return str(ids[i + 1]) if i >= 0 and i + 1 < ids.size() else ""


## The first lesson without a medal ("" when all have one).
static func next_lesson(store: AcademyStore) -> String:
	for id in lesson_ids():
		if store.medal(str(id)) <= AcademyMedals.NONE:
			return str(id)
	return ""


static func progress(chapter: Dictionary, store: AcademyStore) -> Dictionary:
	var out := {"done": 0, "total": (chapter.lessons as Array).size(), "gold": 0}
	for l in chapter.lessons:
		var medal := store.medal(str(l.id))
		if medal > AcademyMedals.NONE:
			out.done += 1
		if medal == AcademyMedals.GOLD:
			out.gold += 1
	return out
