class_name AcademyEstrategia
extends RefCounted
## Chapter 4 of the Academia: line of sight, focus and the floor of the arena.

const CHAPTER := "estrategia"


## Hide from a caster behind a pillar, come out to hit and hide again. The medal is the damage taken.
static func vision(_cls: String, _spec := "") -> LessonFlow:
	var f := LessonFlow.new("vision", "Línea de visión", CHAPTER, "los_1")
	f.medal_rule = {"silver": {"max_taken": 220.0}, "gold": {"max_taken": 90.0}}
	f.add_step("intro", "Línea de visión", "Nadie le puede lanzar nada a quien no ve. Los [b]pilares[/b] y las paredes tapan: son tu mejor defensa. Esta vez la medalla es por [b]recibir poco daño[/b].", [])
	f.add_step("hide", "Cubrite", "Ese hechicero te va a tirar fuego apenas te vea. Ponete detrás de un pilar: si no te ve, no puede lanzar.",
		[StepFlow.obj("hidden", "Quedate fuera de su vista un momento", "note:hidden")], {"arrow": "unit:Hechicero", "cue": 1, "mood": "seria"})
	f.add_step("peek", "Asomarse y volver", "Así se pelea contra uno que lanza: salís, pegás y volvés a cubrirte antes de que termine su hechizo.",
		[StepFlow.obj("hit", "Salí y hacele daño", "dmg"),
		StepFlow.obj("back", "Volvé a esconderte", "note:hidden")], {"arrow": "unit:Hechicero", "mood": "burlona"})
	f.add_step("done", "¡Listo!", "El pilar es tu amigo.", [], {"final": true})
	return f


## Mark a focus, keep another target, cast on the focus without switching.
static func foco(cls: String, spec := "") -> LessonFlow:
	var kit := AcademyKit.new(cls, spec)
	var slot := kit.control_slot() if kit.kind(kit.control_slot()) == "hostile" else 1 if kit.kind(1) == "hostile" else 0
	var kb := Keybinds.shared()
	var f := LessonFlow.new("foco", "El foco", CHAPTER, "focus_1")
	f.medal_rule = {"silver": {"max_time_ms": 45000.0}, "gold": {"max_time_ms": 22000.0}}
	f.add_step("intro", "Dos rivales a la vez", "En 2v2 y 3v3 casi siempre querés [b]pegarle a uno y controlar a otro[/b]. Para eso existe el foco: un segundo objetivo que no perdés al cambiar el primero.", [])
	f.add_step("mark", "Marcar el foco", "Elegí al [b]sanador[/b] y apretá [key]%s[/key]: queda marcado como foco, en el recuadro violeta." % kb.label("focus"),
		[StepFlow.obj("focus", "Elegí al sanador y marcalo con [key]%s[/key]" % kb.label("focus"), "focus_set")], {"arrow": "unit:Sanador"})
	f.add_step("use", "Lanzar al foco", "Ahora elegí al guerrero con [key]%s[/key]. Con [key]Shift[/key] + la tecla de un poder, lo lanzás [b]sobre tu foco[/b] sin soltar a tu objetivo." % kb.label("target_next"),
		[StepFlow.obj("other", "Cambiá de objetivo al guerrero", "tab_target"),
		StepFlow.obj("cast", "[key]Shift[/key] + [key]%s[/key]: [b]%s[/b] sobre el foco" % [kit.key(slot), str(kit.ability(slot).name)], "focus_cast")], {"arrow": "unit:Guerrero", "slot": slot, "mood": "contenta"})
	f.add_step("done", "¡Listo!", "Pegarle a uno y dormir al otro: así se gana un 2v2.", [], {"final": true, "mood": "orgullosa"})
	return f


## Cross a strip of lava without touching it and pick up a gem.
static func terreno(_cls: String, _spec := "") -> LessonFlow:
	var f := LessonFlow.new("terreno", "Lava y gemas", CHAPTER, "ground_1")
	f.medal_rule = {"silver": {"max_taken": 45.0}, "gold": {"max_mistakes": 0}}
	f.mistake_keys = ["burned"]
	var jump := Keybinds.shared().label("jump")
	f.add_step("intro", "El piso también juega", "Algunas arenas tienen [b]lava[/b]: quema mientras estés encima. Y cada tanto aparecen [b]gemas[/b] que dan una ventaja por unos segundos. La medalla de oro es por no quemarte nunca.", [])
	f.add_step("cross", "Cruzar la lava", "Pasá la puerta: del otro lado hay una franja de lava. Rodeala por los costados. Saltar con [key]%s[/key] no te salva: quema igual aunque estés en el aire." % jump,
		[StepFlow.obj("plate", "Llegá a la placa del otro lado", "plate:18")], {"arrow": "plate:18", "mood": "burlona"})
	f.add_step("gem", "Agarrar una gema", "Apareció una gema. Se agarra pasando por encima. Las hay de [b]crítico[/b], [b]celeridad[/b], [b]escudo[/b], [b]sigilo[/b] y [b]vida[/b]: el que llega primero se la queda.",
		[StepFlow.obj("gem", "Agarrá la gema", "gem")], {"cue": 1, "mood": "contenta"})
	f.add_step("done", "¡Listo!", "Mirá el piso antes de pelear.", [], {"final": true})
	return f
