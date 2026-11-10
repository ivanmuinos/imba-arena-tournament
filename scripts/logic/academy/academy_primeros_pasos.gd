class_name AcademyPrimerosPasos
extends RefCounted
## Chapter 1 of the Academia: first steps.

const CHAPTER := "primeros_pasos"


## Walks through the plates of the first room and out of the door. Each step's `cue` also opens its part if the previous one
## was skipped, so skipping can never leave the player stuck.
static func moverse(_cls: String, _spec := "") -> LessonFlow:
	var f := LessonFlow.new("moverse", "Moverse", CHAPTER, "move_1")
	f.medal_rule = {"silver": {"max_time_ms": 90000.0}, "gold": {"max_time_ms": 50000.0}}
	var jump := Keybinds.shared().label("jump")
	f.add_step("intro", "Moverse", "Soy Tizón, tu entrenador. Acá nada te puede matar y podés repetir todo las veces que quieras. Las placas brillantes del piso marcan a dónde ir.", [], {"mood": "contenta"})
	f.add_step("walk", "Caminar", "[key]W[/key] avanza y [key]S[/key] retrocede. [key]A[/key] y [key]D[/key] giran a tu campeón.",
		[StepFlow.obj("plate", "Llegá a la placa de la izquierda", "plate:0")], {"arrow": "plate:0"})
	f.add_step("strafe", "Paso lateral", "[key]Q[/key] y [key]E[/key] te mueven de costado sin girar: así seguís mirando a tu rival mientras esquivás.",
		[StepFlow.obj("plate", "Cruzá de costado hasta la placa de la derecha", "plate:1")], {"arrow": "plate:1", "cue": 1})
	f.add_step("look", "Mirar con el mouse", "Con [key]clic derecho[/key] sostenido tu campeón gira con la cámara, y [key]A[/key] y [key]D[/key] pasan a ser pasos laterales.",
		[StepFlow.obj("look", "Mantené [key]clic derecho[/key] y mové el mouse", "cam_rmb"),
		StepFlow.obj("plate", "Andá hasta la placa frente a la puerta", "plate:2")], {"arrow": "plate:2", "cue": 2})
	f.add_step("cross", "Cruzar", "Se abrió la puerta. [key]%s[/key] salta: sirve para cancelar un lanzamiento y para esquivar." % jump,
		[StepFlow.obj("jump", "Saltá una vez", "jumped"),
		StepFlow.obj("plate", "Pasá a la otra sala y pisá la placa", "plate:7")], {"arrow": "plate:7", "cue": 3})
	f.add_step("done", "¡Listo!", "Ya sabés moverte por la arena.", [], {"final": true})
	return f


## Orbit, zoom and turn with the mouse, then find the plate that starts behind the player.
static func camara(_cls: String, _spec := "") -> LessonFlow:
	var f := LessonFlow.new("camara", "La cámara", CHAPTER, "cam_1")
	f.medal_rule = {"silver": {"max_time_ms": 45000.0}, "gold": {"max_time_ms": 25000.0}}
	f.add_step("intro", "La cámara", "En la arena pierde el que deja de ver a su rival. La cámara se maneja con el mouse, y tiene dos formas de girar.", [])
	f.add_step("orbit", "Mirar alrededor", "Con [key]clic izquierdo[/key] sostenido la cámara da vueltas alrededor tuyo [b]sin girar[/b] a tu campeón: sirve para espiar sin dejar de correr.",
		[StepFlow.obj("lmb", "Mantené [key]clic izquierdo[/key] y arrastrá", "cam_lmb"),
		StepFlow.obj("zoom", "Acercá o alejá con la [key]rueda[/key] del mouse", "zoom")])
	f.add_step("turn", "Girar de verdad", "Con [key]clic derecho[/key] sostenido girás vos también. Hay una placa [b]a tu espalda[/b]: date vuelta con el mouse y pisala.",
		[StepFlow.obj("rmb", "Mantené [key]clic derecho[/key] y arrastrá", "cam_rmb"),
		StepFlow.obj("plate", "Pisá la placa que estaba detrás tuyo", "plate:3")], {"arrow": "plate:3", "cue": 1, "mood": "burlona"})
	f.add_step("done", "¡Listo!", "Ya mirás para todos lados.", [], {"final": true})
	return f


## Pick a target with the mouse and with the key, then break three crates with the basic attack.
static func objetivo(cls: String, spec := "") -> LessonFlow:
	var kit := AcademyKit.new(cls, spec)
	var f := LessonFlow.new("objetivo", "Objetivo y primer golpe", CHAPTER, "target_1")
	f.medal_rule = {"silver": {"max_time_ms": 45000.0}, "gold": {"max_time_ms": 25000.0}}
	var tab := Keybinds.shared().label("target_next")
	f.add_step("intro", "Elegir a quién", "Acá no se apunta con una mira: tus poderes van al [b]objetivo que elegiste[/b]. Sin objetivo, la mayoría no sale.", [])
	f.add_step("pick", "Elegir un objetivo", "El objetivo elegido muestra su vida arriba de la pantalla. [key]Esc[/key] lo suelta.",
		[StepFlow.obj("click", "[key]Clic izquierdo[/key] sobre una caja para elegirla", "click_target"),
		StepFlow.obj("tab", "[key]%s[/key] pasa a la siguiente sin usar el mouse" % tab, "tab_target")], {"arrow": "unit:Caja"})
	var basic := kit.ability(0)
	var text := "[b]%s[/b] es tu golpe básico. " % str(basic.name)
	if kit.kind(0) == "auto":
		text += "Es un auto-ataque: con [key]clic derecho[/key] sobre el enemigo (o [key]%s[/key]) pega solo mientras estés a %s m y mirándolo." % [kit.key(0), str(basic.range)]
	else:
		text += "Apretá [key]%s[/key] con una caja elegida: llega hasta %s m. Repetilo: casi no tiene espera." % [kit.key(0), str(basic.range)]
	f.add_step("hit", "Tu primer golpe", text,
		[StepFlow.obj("break", "Rompé las 3 cajas", "death", 3)], {"arrow": "unit:Caja", "mood": "contenta"})
	f.add_step("done", "¡Listo!", "Elegir bien a quién pegarle es media pelea.", [], {"final": true})
	return f
