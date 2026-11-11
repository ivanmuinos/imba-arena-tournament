class_name AcademyPrueba
extends RefCounted
## Chapter 5 of the Academia: a real fight against an easy rival.

const CHAPTER := "prueba"


static func duelo(_cls: String, _spec := "") -> LessonFlow:
	var f := LessonFlow.new("duelo", "Tu primer duelo", CHAPTER, "duel_1")
	f.medal_rule = {"silver": {"max_downs": 0}, "gold": {"min_hp_pct": 0.5}}
	f.add_step("intro", "Cómo es una partida", "Una partida real es al mejor de 3 rondas. Cada equipo espera 10 s en su sala y, cuando se abren las puertas, gana la ronda quien elimina a todos los rivales.", [], {"mood": "seria"})
	f.add_step("damp", "Si la pelea se alarga", "Pasados 40 s aparece la [b]amortiguación[/b]: las curaciones rinden cada vez menos, así ninguna ronda es eterna. Y la definitiva se carga pegando y recibiendo.", [])
	f.add_step("fight", "¡A pelear!", "Brasa pelea de verdad, pero es flojito. Usá todo: control, cubrirte y tu abalorio. [b]Plata[/b] si no caés nunca, [b]oro[/b] si además terminás con más de media vida.",
		[StepFlow.obj("win", "Derrotá a Brasa", "note:won")], {"arrow": "unit:Brasa", "cue": 1, "mood": "burlona"})
	f.add_step("done", "¡Ganaste!", "Ya estás para la arena de verdad.", [], {"final": true, "mood": "orgullosa"})
	return f
