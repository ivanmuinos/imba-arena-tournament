class_name AcademyCatalog
extends RefCounted
## Every lesson of the Academia, by id. Lessons are code, not data: their text depends on the player's real keys and kit.


## A fresh LessonFlow for the player's kit, or null when there is no such lesson.
static func lesson(id: String, cls: String, spec := "") -> LessonFlow:
	match id:
		"moverse":
			return AcademyPrimerosPasos.moverse(cls, spec)
	return null
