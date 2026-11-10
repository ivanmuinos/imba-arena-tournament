class_name AcademyControl
extends RefCounted
## Chapter 3 of the Academia: crowd control, the trinket and cutting casts.

const CHAPTER := "control"


## Control once, then three in a row to see it last less and less until the rival is immune.
static func control(cls: String, spec := "") -> LessonFlow:
	var kit := AcademyKit.new(cls, spec)
	var slot := kit.control_slot()
	var f := LessonFlow.new("control", "Controlar al rival", CHAPTER, "cc_1")
	f.medal_rule = {"silver": {"max_time_ms": 70000.0}, "gold": {"max_time_ms": 40000.0}}
	f.add_step("intro", "Control", "Un rival que no puede actuar no te pega ni se cura. Hay varios tipos: [b]aturdir[/b], [b]incapacitar[/b] (oveja, ceguera), [b]miedo[/b], [b]raíces[/b] y [b]ralentizar[/b].", [])
	f.add_step("first", "Tu control", "%s%s: %s. En esta lección no tiene espera, para que lo repitas." % [kit.named(slot), kit.how(slot), kit.cc_words(slot)],
		[StepFlow.obj("cc", "Controlá al sparring", "cc")], {"arrow": "unit:Sparring", "slot": slot, "mood": "contenta"})
	f.add_step("dr", "Cada vez dura menos", "Repetir el mismo tipo de control rinde cada vez menos: la segunda vez dura [b]la mitad[/b], la tercera [b]un cuarto[/b] y después el rival queda [b]inmune[/b]. Se reinicia a los 18 s sin recibirlo.",
		[StepFlow.obj("again", "Controlalo dos veces más", "cc", 2),
		StepFlow.obj("immune", "Una más: ahora dice INMUNE", "cc_immune:dr")], {"arrow": "unit:Sparring", "slot": slot, "mood": "seria"})
	f.add_step("breaks", "Qué lo rompe", "El daño [b]rompe[/b] la oveja, la ceguera, la trampa y la desorientación; el miedo aguanta un poco de daño. Un aturdimiento no se rompe con nada. No le pegues al que acabás de dormir.", [], {"mood": "burlona"})
	f.add_step("done", "¡Listo!", "Controlar con cabeza gana partidas.", [], {"final": true})
	return f


## A long stun, broken with the trinket.
static func abalorio(_cls: String, _spec := "") -> LessonFlow:
	var f := LessonFlow.new("abalorio", "El abalorio", CHAPTER, "trinket_1")
	f.medal_rule = {"silver": {"max_time_ms": 6000.0}, "gold": {"max_time_ms": 2500.0}}
	var key := Keybinds.shared().label("trinket")
	f.add_step("intro", "El abalorio", "Todos los campeones tienen un [b]abalorio[/b] en [key]%s[/key]: te libera de cualquier control. Tarda [b]2 minutos[/b] en volver, así que en una ronda lo usás una sola vez." % key, [], {"arrow": "bar"})
	f.add_step("warn", "¿Listo?", "Te voy a aturdir 6 segundos. Cuando no puedas moverte, apretá [key]%s[/key]. La medalla depende de cuánto tardes en reaccionar." % key, [], {"mood": "burlona"})
	f.add_step("free", "¡Liberate!", "Estás aturdido. [key]%s[/key] te suelta." % key,
		[StepFlow.obj("trinket", "Apretá [key]%s[/key] para liberarte" % key, "trinket")], {"arrow": "bar", "cue": 1, "mood": "seria"})
	f.add_step("when", "Cuándo usarlo", "No lo gastes en el primer control que te tiren: guardalo para el que te mata. Y ojo con la [b]oveja[/b]: te cura mientras dura, a veces conviene esperarla.", [], {"mood": "seria"})
	f.add_step("done", "¡Listo!", "Abalorio guardado, pelea ganada.", [], {"final": true})
	return f


## An enemy that casts over and over: control it while the bar is filling.
static func cortar(cls: String, spec := "") -> LessonFlow:
	var kit := AcademyKit.new(cls, spec)
	var slot := kit.stopper_slot()
	var f := LessonFlow.new("cortar", "Cortar un lanzamiento", CHAPTER, "kick_1")
	f.medal_rule = {"silver": {"max_time_ms": 30000.0}, "gold": {"max_time_ms": 12000.0}}
	f.add_step("intro", "Cortar", "Aturdir, incapacitar, asustar o silenciar a alguien [b]mientras lanza[/b] le corta el hechizo y se lo bloquea 4 segundos. Las raíces y la ralentización no cortan nada.", [])
	var tip := "" if float(kit.ability(slot).get("cast", 0)) <= 0.0 else " El tuyo también se lanza: empezalo apenas él arranque el suyo."
	f.add_step("cut", "Cortalo", "El hechicero lanza sin parar: mirá la barra sobre su cabeza. Usá %s%s cuando la barra se esté llenando.%s" % [kit.named(slot), kit.how(slot), tip],
		[StepFlow.obj("cut", "Cortale un lanzamiento: tiene que decir INTERRUMPIDO", "interrupt")], {"arrow": "unit:Hechicero", "slot": slot, "cue": 1, "mood": "seria"})
	f.add_step("done", "¡Listo!", "Un hechizo cortado es daño que nunca llegó.", [], {"final": true, "mood": "orgullosa"})
	return f
