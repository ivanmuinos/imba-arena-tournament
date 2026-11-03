class_name AcademyPrimerosPasos
extends RefCounted
## Chapter 1 of the Academia: first steps.

const CHAPTER := "primeros_pasos"


## Walks through the plates of the first room and out of the door. Each step's `cue` also opens its part if the previous one
## was skipped, so skipping can never leave the player stuck.
static func moverse(_cls: String, _spec := "") -> LessonFlow:
	var f := LessonFlow.new("moverse", "Moverse", CHAPTER, "move_1")
	var jump := Keybinds.shared().label("jump")
	f.add_step("intro", "Moverse", "Acá nada te puede matar y podés repetir todo las veces que quieras. Las placas brillantes del piso marcan a dónde ir.", [])
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
