class_name AcademyValley
extends RefCounted
## The Academia's lessons as quests of the valley: Tizón gives them at his camp, they send you around the map and they end
## back with him. Same ids, medals and store as the lessons of the menu: a quest done here is that lesson done.
## Plates: 0-6 are the zones (camp, yard, ruins, river, grove, quarry, arena), 7-11 the first quests' (GameMap).

const SCENARIO := "valley_free"
## Quests in the order Tizón gives them.
const QUESTS := ["moverse", "camara", "objetivo", "habilidades", "lanzamientos", "definitiva", "control", "abalorio", "cortar", "vision", "foco", "terreno", "duelo"]
## The cue that sends away everyone a quest brought in and puts the valley's rules back (LessonScenarios, valley_free).
const CLEANUP_CUE := 60
const YARD := 1
const RUINS := 2
const RIVER := 3
const ARENA := 6
## What Tizón says when he offers each one.
const PITCH := {
	"moverse": "¡Llegaste! Antes de pelear hay que saber caminar. Dame una vuelta por el campamento y te espero acá.",
	"camara": "Bien. Ahora los ojos: en la arena pierde el que deja de ver a su rival. Te enseño a mirar.",
	"objetivo": "Hora de pegarle a algo. En el Patio de práctica dejé unas cajas: seguí el sendero, el minimapa te marca dónde.",
	"habilidades": "Ya sabés pegar. Ahora quiero ver toda tu barra: andá al Patio y probá cada botón contra un muñeco.",
	"lanzamientos": "Hay poderes que tardan en salir, y ahí es donde te cazan. En el Patio te muestro cómo se manejan.",
	"definitiva": "Te falta el botón gordo. Te lo dejo cargado en el Patio para que lo estrenes.",
	"control": "Pegar fuerte no alcanza: el que gana es el que deja al otro sin jugar. Tengo un sparring en el Patio que se deja.",
	"abalorio": "Ahora al revés: te voy a dejar duro a vos. Quedate acá nomás, es un segundo... bueno, seis.",
	"cortar": "Un hechicero amigo va a lanzarte cosas en el Patio. Tu trabajo es que no termine ni una.",
	"vision": "En las Ruinas, al este, hay otro hechicero con peor carácter. Ahí vas a aprender para qué sirven los pilares.",
	"foco": "En el Patio te esperan dos a la vez. Pegarle a uno y dormir al otro: eso es un 2v2.",
	"terreno": "Al norte corre el Río de lava. Hay que cruzarlo sin quemarse, y del otro lado dejé algo brillante.",
	"duelo": "Ya está. En la Arena del duelo, pasando el río, te espera Brasa. Es flojito, pero pelea de verdad.",
}
const BACK := "Volvé con Tizón: es la marca que late en el minimapa"


static func has(id: String) -> bool:
	return QUESTS.has(id)


## The quest Tizón has for you now: the first one without a medal ("" when all have one).
static func next_quest(store: AcademyStore) -> String:
	for id in QUESTS:
		if store.medal(str(id)) <= AcademyMedals.NONE:
			return str(id)
	return ""


## The quest after this one ("" for the last one and for unknown ids).
static func after(id: String) -> String:
	var i := QUESTS.find(id)
	return str(QUESTS[i + 1]) if i >= 0 and i + 1 < QUESTS.size() else ""


static func pitch(id: String) -> String:
	return str(PITCH.get(id, ""))


## The quest Tizón offers when there is no new one: the first whose medal can still get better ("" when all are gold).
static func improve_quest(store: AcademyStore) -> String:
	for id in QUESTS:
		if store.medal(str(id)) < AcademyMedals.GOLD:
			return str(id)
	return ""


## A fresh quest for the player's kit, or null when the valley has no such quest.
static func quest(id: String, cls: String, spec := "") -> LessonFlow:
	match id:
		"moverse": return _moverse()
		"camara": return _camara()
		"objetivo": return _objetivo(cls, spec)
		"habilidades": return _field(id, cls, spec, YARD, 7, {}, "Al Patio de práctica", "Parate en la placa del Patio de práctica, frente a los muñecos.")
		"lanzamientos":
			var cast := AcademyKit.new(cls, spec).cast_slot() >= 0
			return _field(id, cls, spec, YARD, 8, {"push": 9 if cast else 10}, "Al Patio de práctica", "Parate en la placa del Patio de práctica.")
		"definitiva": return _field(id, cls, spec, YARD, 11, {"use": 12}, "Al Patio de práctica", "Parate en la placa del Patio de práctica: ahí te cargo la definitiva.")
		"control": return _field(id, cls, spec, YARD, 13, {"first": 14}, "Al Patio de práctica", "Parate en la placa del Patio de práctica: el sparring sale cuando llegues.")
		"abalorio": return _field(id, cls, spec, -1, -1, {"free": 15}, "", "")
		"cortar": return _field(id, cls, spec, YARD, 16, {"cut": 17}, "Al Patio de práctica", "Parate en la placa del Patio de práctica.")
		"vision": return _field(id, cls, spec, RUINS, 18, {"hide": 19}, "A las Ruinas", "Las Ruinas de los pilares quedan al este: del cruce de caminos, el sendero de la derecha. Parate en su placa.", 25000.0)
		"foco": return _field(id, cls, spec, YARD, 20, {"mark": 21}, "Al Patio de práctica", "Parate en la placa del Patio de práctica.")
		"terreno": return _terreno()
		"duelo": return _field(id, cls, spec, ARENA, 25, {"fight": 26}, "A la Arena del duelo", "La arena está al norte, pasando el río por cualquiera de los dos vados. Entrá por su puerta y parate en la placa.")
	return null


## A lesson of the catalog played in the valley: the same steps, after walking to the plate of the zone where it happens.
## `go_cue` readies that plate and `cues` gives each step that brings someone in its cue of the valley (by step id).
## `walk_ms`: the time the trip adds to the medals' limits.
static func _field(id: String, cls: String, spec: String, plate: int, go_cue: int, cues: Dictionary, go_title: String, go_text: String, walk_ms := 20000.0) -> LessonFlow:
	var f := AcademyCatalog.lesson(id, cls, spec)
	f.scenario = SCENARIO
	for s in f.steps:
		s.erase("cue")
		if cues.has(str(s.id)):
			s["cue"] = int(cues[s.id])
	if plate >= 0:
		var steps := f.steps
		f.steps = []
		f.add_step("go", go_title, go_text, [StepFlow.obj("plate", "Llegá a la placa: la marca amarilla del minimapa", "plate:%d" % plate)], {"arrow": "plate:%d" % plate, "cue": go_cue})
		f.steps.append_array(steps)
		for level in f.medal_rule:
			if (f.medal_rule[level] as Dictionary).has("max_time_ms"):
				f.medal_rule[level] = (f.medal_rule[level] as Dictionary).duplicate()
				f.medal_rule[level]["max_time_ms"] = float(f.medal_rule[level].max_time_ms) + walk_ms
	return f


## Cross the lava river by a ford without burning, all the way to the arena, and pick up a gem on the way.
static func _terreno() -> LessonFlow:
	var f := LessonFlow.new("terreno", "Lava y gemas", "estrategia", SCENARIO)
	f.medal_rule = {"silver": {"max_taken": 45.0}, "gold": {"max_mistakes": 0}}
	f.mistake_keys = ["burned"]
	var jump := Keybinds.shared().label("jump")
	f.add_step("go", "Al Río de lava", "Seguí el sendero al norte hasta la orilla. La medalla de oro es por [b]no quemarte nunca[/b]: mirá dónde pisás.",
		[StepFlow.obj("plate", "Llegá a la orilla del río", "plate:%d" % RIVER)], {"arrow": "plate:%d" % RIVER, "cue": 22})
	f.add_step("cross", "Cruzar por un vado", "La lava quema mientras estés encima, y saltar con [key]%s[/key] no te salva. Hay dos [b]vados[/b] de tierra, al este y al oeste: en el minimapa son los cortes del río." % jump,
		[StepFlow.obj("plate", "Cruzá y llegá a la puerta de la arena", "plate:%d" % ARENA)], {"arrow": "plate:%d" % ARENA, "cue": 23, "mood": "burlona"})
	f.add_step("gem", "Agarrar una gema", "Apareció una [b]gema[/b] acá cerca. Se agarra pasando por encima. Las hay de crítico, celeridad, escudo, sigilo y vida: el que llega primero se la queda.",
		[StepFlow.obj("gem", "Agarrá la gema", "gem")], {"cue": 24, "mood": "contenta"})
	f.add_step("done", "¡Listo!", "", [], {"final": true})
	return f


static func _turn_in(f: LessonFlow, words: String) -> void:
	f.add_step("back", "Volver con Tizón", words, [StepFlow.obj("tizon", BACK, "tizon")], {"arrow": "tizon", "mood": "contenta"})
	f.add_step("done", "¡Listo!", "", [], {"final": true})


static func _moverse() -> LessonFlow:
	var f := LessonFlow.new("moverse", "Moverse", "primeros_pasos", SCENARIO)
	f.medal_rule = {"silver": {"max_time_ms": 100000.0}, "gold": {"max_time_ms": 60000.0}}
	var jump := Keybinds.shared().label("jump")
	f.add_step("walk", "Caminar", "[key]W[/key] avanza y [key]S[/key] retrocede. [key]A[/key] y [key]D[/key] giran a tu campeón. Las placas que brillan en el piso marcan a dónde ir.",
		[StepFlow.obj("plate", "Llegá a la placa de la izquierda", "plate:7")], {"arrow": "plate:7", "cue": 1})
	f.add_step("strafe", "Paso lateral", "[key]Q[/key] y [key]E[/key] te mueven de costado sin girar: así seguís mirando a tu rival mientras esquivás.",
		[StepFlow.obj("plate", "Cruzá de costado hasta la placa de la derecha", "plate:8")], {"arrow": "plate:8", "cue": 2})
	f.add_step("look", "Mirar con el mouse", "Con [key]clic derecho[/key] sostenido tu campeón gira con la cámara, y [key]A[/key] y [key]D[/key] pasan a ser pasos laterales.",
		[StepFlow.obj("look", "Mantené [key]clic derecho[/key] y mové el mouse", "cam_rmb"),
		StepFlow.obj("plate", "Andá hasta la placa del sendero", "plate:9")], {"arrow": "plate:9", "cue": 3})
	f.add_step("cross", "Saltar y correr", "[key]%s[/key] salta: sirve para cancelar un lanzamiento y para esquivar. Seguí el sendero hasta el cruce de caminos." % jump,
		[StepFlow.obj("jump", "Saltá una vez", "jumped"),
		StepFlow.obj("plate", "Llegá al cruce de caminos", "plate:11")], {"arrow": "plate:11", "cue": 4, "mood": "burlona"})
	_turn_in(f, "Eso es moverse. El círculo de arriba a la derecha es el [b]minimapa[/b]: tu flecha en el centro, el norte arriba. Usalo para volver.")
	return f


static func _camara() -> LessonFlow:
	var f := LessonFlow.new("camara", "La cámara", "primeros_pasos", SCENARIO)
	f.medal_rule = {"silver": {"max_time_ms": 60000.0}, "gold": {"max_time_ms": 35000.0}}
	f.add_step("orbit", "Mirar alrededor", "Con [key]clic izquierdo[/key] sostenido la cámara da vueltas alrededor tuyo [b]sin girar[/b] a tu campeón: sirve para espiar sin dejar de correr.",
		[StepFlow.obj("lmb", "Mantené [key]clic izquierdo[/key] y arrastrá", "cam_lmb"),
		StepFlow.obj("zoom", "Acercá o alejá con la [key]rueda[/key] del mouse", "zoom")])
	f.add_step("turn", "Girar de verdad", "Con [key]clic derecho[/key] sostenido girás vos también. Dejé una placa al fondo del campamento, [b]junto al muro[/b]: buscala con la cámara y pisala.",
		[StepFlow.obj("rmb", "Mantené [key]clic derecho[/key] y arrastrá", "cam_rmb"),
		StepFlow.obj("plate", "Pisá la placa junto al muro", "plate:10")], {"arrow": "plate:10", "cue": 5, "mood": "burlona"})
	_turn_in(f, "Ya mirás para todos lados. Una cosa más y te suelto.")
	return f


static func _objetivo(cls: String, spec: String) -> LessonFlow:
	var kit := AcademyKit.new(cls, spec)
	var f := LessonFlow.new("objetivo", "Objetivo y primer golpe", "primeros_pasos", SCENARIO)
	f.medal_rule = {"silver": {"max_time_ms": 110000.0}, "gold": {"max_time_ms": 70000.0}}
	var tab := Keybinds.shared().label("target_next")
	f.add_step("go", "Al Patio de práctica", "El patio queda al oeste, por el sendero que sale a la izquierda del cruce. La marca amarilla del minimapa te lleva.",
		[StepFlow.obj("plate", "Llegá al Patio de práctica", "plate:1")], {"arrow": "plate:1", "cue": 6})
	f.add_step("pick", "Elegir un objetivo", "Acá no se apunta con una mira: tus poderes van al [b]objetivo que elegiste[/b]. Su vida aparece arriba de la pantalla, y [key]Esc[/key] lo suelta.",
		[StepFlow.obj("click", "[key]Clic izquierdo[/key] sobre una caja para elegirla", "click_target"),
		StepFlow.obj("tab", "[key]%s[/key] pasa al siguiente sin usar el mouse" % tab, "tab_target")], {"arrow": "unit:Caja"})
	var basic := kit.ability(0)
	var text := "[b]%s[/b] es tu golpe básico. " % str(basic.name)
	if kit.kind(0) == "auto":
		text += "Es un auto-ataque: con [key]clic derecho[/key] sobre el enemigo (o [key]%s[/key]) pega solo mientras estés a %s m y mirándolo." % [kit.key(0), str(basic.range)]
	else:
		text += "Apretá [key]%s[/key] con una caja elegida: llega hasta %s m. Repetilo: casi no tiene espera." % [kit.key(0), str(basic.range)]
	f.add_step("hit", "Tu primer golpe", text, [StepFlow.obj("break", "Rompé las 3 cajas", "death", 3)], {"arrow": "unit:Caja", "mood": "contenta"})
	_turn_in(f, "¡Astillas por todos lados! Elegir bien a quién pegarle es media pelea.")
	return f
