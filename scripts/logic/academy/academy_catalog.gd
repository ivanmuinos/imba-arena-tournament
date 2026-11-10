class_name AcademyCatalog
extends RefCounted
## Every lesson of the Academia, by id and by chapter. Lessons are code, not data: their text depends on the player's real keys and kit.

## Chapters in teaching order. Nothing is locked: the order is only what the Academia suggests next.
## `mins`: a rough length shown on the lesson's card.
const CHAPTERS := [
	{"id": "primeros_pasos", "title": "Primeros pasos", "blurb": "Moverte, mirar y dar tu primer golpe.", "lessons": [
		{"id": "moverse", "title": "Moverse", "blurb": "Caminar, pasos laterales y saltar.", "mins": 2},
		{"id": "camara", "title": "La cámara", "blurb": "Mirar alrededor sin perder a tu rival.", "mins": 1},
		{"id": "objetivo", "title": "Objetivo y primer golpe", "blurb": "Elegir a quién y pegarle.", "mins": 1},
	]},
	{"id": "habilidades", "title": "Tus habilidades", "blurb": "La barra de tu campeón, botón por botón.", "lessons": [
		{"id": "habilidades", "title": "Tu barra", "blurb": "Cada poder y su tiempo de espera.", "mins": 2},
		{"id": "lanzamientos", "title": "Lanzamientos", "blurb": "Terminar, cancelar y aguantar una barra.", "mins": 2},
		{"id": "definitiva", "title": "La definitiva", "blurb": "Tu botón más fuerte y cómo se carga.", "mins": 1},
	]},
	{"id": "control", "title": "Control", "blurb": "Dejar al rival sin actuar, y que no te lo hagan a vos.", "lessons": [
		{"id": "control", "title": "Controlar al rival", "blurb": "Tu control y por qué cada vez dura menos.", "mins": 2},
		{"id": "abalorio", "title": "El abalorio", "blurb": "Liberarte del control que te mata.", "mins": 1},
		{"id": "cortar", "title": "Cortar un lanzamiento", "blurb": "Frenar el hechizo antes de que salga.", "mins": 1},
	]},
	{"id": "estrategia", "title": "Estrategia", "blurb": "Usar la arena y pelear contra más de uno.", "lessons": [
		{"id": "vision", "title": "Línea de visión", "blurb": "Los pilares como defensa.", "mins": 2},
		{"id": "foco", "title": "El foco", "blurb": "Pegarle a uno y controlar a otro.", "mins": 1},
		{"id": "terreno", "title": "Lava y gemas", "blurb": "Lo que el piso te quita y te da.", "mins": 1},
	]},
	{"id": "prueba", "title": "Prueba final", "blurb": "Todo junto, contra un rival de verdad.", "lessons": [
		{"id": "duelo", "title": "Tu primer duelo", "blurb": "Un 1 contra 1 completo.", "mins": 3},
	]},
]


## A fresh LessonFlow for the player's kit, or null when there is no such lesson.
static func lesson(id: String, cls: String, spec := "") -> LessonFlow:
	match id:
		"moverse": return AcademyPrimerosPasos.moverse(cls, spec)
		"camara": return AcademyPrimerosPasos.camara(cls, spec)
		"objetivo": return AcademyPrimerosPasos.objetivo(cls, spec)
		"habilidades": return AcademyHabilidades.habilidades(cls, spec)
		"lanzamientos": return AcademyHabilidades.lanzamientos(cls, spec)
		"definitiva": return AcademyHabilidades.definitiva(cls, spec)
		"control": return AcademyControl.control(cls, spec)
		"abalorio": return AcademyControl.abalorio(cls, spec)
		"cortar": return AcademyControl.cortar(cls, spec)
		"vision": return AcademyEstrategia.vision(cls, spec)
		"foco": return AcademyEstrategia.foco(cls, spec)
		"terreno": return AcademyEstrategia.terreno(cls, spec)
		"duelo": return AcademyPrueba.duelo(cls, spec)
	return null


static func chapters() -> Array:
	return CHAPTERS


static func lesson_ids() -> Array:
	var out: Array = []
	for c in CHAPTERS:
		for l in c.lessons:
			out.append(str(l.id))
	return out


static func total() -> int:
	return lesson_ids().size()


## The catalog entry of a lesson ({} for unknown ids).
static func info(id: String) -> Dictionary:
	for c in CHAPTERS:
		for l in c.lessons:
			if str(l.id) == id:
				return l
	return {}


## The chapter a lesson belongs to ({} for unknown ids).
static func chapter_of(id: String) -> Dictionary:
	for c in CHAPTERS:
		for l in c.lessons:
			if str(l.id) == id:
				return c
	return {}


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


## The whole Academia: lessons with a medal, golds, and the rank those earn.
static func overall(store: AcademyStore) -> Dictionary:
	var out := {"done": 0, "total": total(), "gold": 0}
	for c in CHAPTERS:
		var p := progress(c, store)
		out.done += int(p.done)
		out.gold += int(p.gold)
	out["rank"] = rank(int(out.done), int(out.gold), int(out.total))
	return out


## What Tizón calls the player, by what they earned.
static func rank(done: int, gold: int, all: int) -> String:
	if all > 0 and gold >= all:
		return "Maestro de la arena"
	if all > 0 and done >= all:
		return "Graduado"
	if done * 2 >= all and all > 0:
		return "Gladiador en formación"
	return "Aprendiz" if done > 0 else "Recién llegado"
