class_name AcademyValley
extends RefCounted
## The Academia's lessons as quests of the valley: Tizón gives them at his camp, they send you around the map and they end
## back with him. Same ids, medals and store as the lessons of the menu: a quest done here is that lesson done.
## Plates: 0-6 are the zones (camp, yard, ruins, river, grove, quarry, arena), 7-11 the first quests' (GameMap).

const SCENARIO := "valley_free"
## Quests in the order Tizón gives them.
const QUESTS := ["moverse", "camara", "objetivo"]
## What Tizón says when he offers each one.
const PITCH := {
	"moverse": "¡Llegaste! Antes de pelear hay que saber caminar. Dame una vuelta por el campamento y te espero acá.",
	"camara": "Bien. Ahora los ojos: en la arena pierde el que deja de ver a su rival. Te enseño a mirar.",
	"objetivo": "Hora de pegarle a algo. En el Patio de práctica dejé unas cajas: seguí el sendero, el minimapa te marca dónde.",
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


## A fresh quest for the player's kit, or null when the valley has no such quest.
static func quest(id: String, cls: String, spec := "") -> LessonFlow:
	match id:
		"moverse": return _moverse()
		"camara": return _camara()
		"objetivo": return _objetivo(cls, spec)
	return null


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
