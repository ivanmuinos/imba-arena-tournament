class_name AcademyHabilidades
extends RefCounted
## Chapter 2 of the Academia: the player's own bar. Every text is built from the kit they brought.

const CHAPTER := "habilidades"


static func _scenario(kit: AcademyKit) -> String:
	return "skills_1_ally" if kit.has_friendly() else "skills_1"


## Use every ability of the bar once, then read about cooldowns.
static func habilidades(cls: String, spec := "") -> LessonFlow:
	var kit := AcademyKit.new(cls, spec)
	var f := LessonFlow.new("habilidades", "Tu barra", CHAPTER, _scenario(kit))
	f.medal_rule = {"silver": {"max_time_ms": 60000.0}, "gold": {"max_time_ms": 30000.0}}
	f.add_step("intro", "Tu barra", "Trajiste a tu [b]%s[/b]. Abajo está tu barra: cada botón tiene su tecla escrita en la esquina. Pasá el mouse por encima de uno para leer qué hace." % kit.class_name_text(), [], {"arrow": "bar"})
	var objs: Array = []
	for slot in range(1, kit.ult_slot()):
		objs.append(StepFlow.obj("slot%d" % slot, "%s%s" % [kit.named(slot), kit.how(slot)], "cast:%s" % str(kit.ability(slot).id)))
	f.add_step("use", "Probalas todas", "Elegí al muñeco y usá cada habilidad una vez. Si alguna no sale, el juego te dice por qué: lejos, sin objetivo o sin línea de visión.", objs, {"arrow": "bar", "mood": "contenta"})
	f.add_step("cooldown", "La espera", "Después de usarla, cada habilidad se oscurece y muestra los segundos que faltan: es su [b]tiempo de espera[/b]. Las fuertes tardan más, así que no las tires porque sí.", [], {"arrow": "bar", "mood": "seria"})
	f.add_step("done", "¡Listo!", "Ya conocés tu barra.", [], {"final": true})
	return f


## Cast bars: finish one, cancel one, and feel how a hit delays it. Kits with no cast bar learn to read the rival's.
static func lanzamientos(cls: String, spec := "") -> LessonFlow:
	var kit := AcademyKit.new(cls, spec)
	var slot := kit.cast_slot()
	var jump := Keybinds.shared().label("jump")
	if slot < 0:
		var g := LessonFlow.new("lanzamientos", "Lanzamientos", CHAPTER, "cast_2")
		g.medal_rule = {"silver": {"max_time_ms": 40000.0}, "gold": {"max_time_ms": 20000.0}}
		g.add_step("intro", "Lanzamientos", "Tus golpes salen al instante, pero los de muchos rivales no: los hechizos fuertes [b]tardan en lanzarse[/b] y se ve una barra sobre su cabeza.", [])
		g.add_step("push", "Molestar al que lanza", "Cada golpe que recibe [b]demora[/b] su lanzamiento (hasta dos veces). Si se mueve o salta, lo pierde. Por eso un hechicero con alguien encima sufre.",
			[StepFlow.obj("hits", "Pegale al hechicero mientras lanza", "dmg", 3)], {"arrow": "unit:Hechicero", "cue": 1, "mood": "burlona"})
		g.add_step("done", "¡Listo!", "Ya sabés leer una barra de lanzamiento.", [], {"final": true})
		return g
	var f := LessonFlow.new("lanzamientos", "Lanzamientos", CHAPTER, "cast_1")
	f.medal_rule = {"silver": {"max_time_ms": 60000.0}, "gold": {"max_time_ms": 35000.0}}
	var cast_id := str(kit.ability(slot).id)
	var secs := "%.1f" % (float(kit.ability(slot).cast) / 1000.0)
	f.add_step("intro", "Lanzamientos", "Algunos poderes no salen al instante: [b]se lanzan[/b]. Mientras se llena la barra tenés que quedarte quieto.", [])
	f.add_step("finish", "Terminar un lanzamiento", "%s tarda %s s en salir%s." % [kit.named(slot), secs.replace(".", ","), " sobre el muñeco" if kit.kind(slot) != "friendly" else ""],
		[StepFlow.obj("finish", "Lanzala y quedate quieto hasta que termine", "cast:%s" % cast_id)], {"arrow": "cast", "slot": slot})
	f.add_step("cancel", "Cancelar", "Moverte, saltar con [key]%s[/key] o apretar [key]Esc[/key] [b]cancela[/b] el lanzamiento. Sirve para amagar o para salir corriendo a tiempo." % jump,
		[StepFlow.obj("cancel", "Empezá a lanzar y cancelalo a mitad", "cast_cancel")], {"arrow": "cast", "slot": slot, "mood": "burlona"})
	f.add_step("push", "Lanzar bajo presión", "Ahora viene alguien a pegarte. Cada golpe [b]demora[/b] tu barra un poco (hasta dos veces), pero no la corta. Aguantá y terminala igual.",
		[StepFlow.obj("pushed", "Terminá %s mientras te pegan" % kit.named(slot), "cast:%s" % cast_id)], {"arrow": "cast", "slot": slot, "cue": 1, "mood": "seria"})
	f.add_step("done", "¡Listo!", "Lanzar, cancelar y aguantar: eso es todo.", [], {"final": true})
	return f


## The ultimate: how it charges and what it does. The scenario hands it over ready.
static func definitiva(cls: String, spec := "") -> LessonFlow:
	var kit := AcademyKit.new(cls, spec)
	var slot := kit.ult_slot()
	var f := LessonFlow.new("definitiva", "La definitiva", CHAPTER, _scenario(kit))
	f.medal_rule = {"silver": {"max_time_ms": 30000.0}, "gold": {"max_time_ms": 12000.0}}
	f.add_step("intro", "La definitiva", "Tu último botón es la [b]definitiva[/b]. No tiene espera: se [b]carga[/b] haciendo y recibiendo daño. La barrita al lado de tu vida muestra cuánto falta.", [], {"arrow": "bar"})
	f.add_step("use", str(kit.ability(slot).name), "%s%s. %s\n\nPara practicar te la dejé cargada." % [kit.named(slot), kit.how(slot), TutorialFlow.short(str(kit.ability(slot).desc))],
		[StepFlow.obj("ult", "Usá tu definitiva", "cast:%s" % str(kit.ability(slot).id))], {"arrow": "bar", "cue": 5, "mood": "contenta"})
	f.add_step("done", "¡Listo!", "En una partida la vas a tener una o dos veces por ronda: guardala para cuando defina.", [], {"final": true, "mood": "orgullosa"})
	return f
