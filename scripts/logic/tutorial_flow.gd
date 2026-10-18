class_name TutorialFlow
extends RefCounted
## "Cómo jugar": the interactive tutorial as pure data + a tiny state machine (no nodes, fully unit-tested).
## The tutorial runs inside the practice yard; TutorialOverlay feeds it gameplay events and draws the current step.
##
## Steps are built from the player's class/spec (names, keys and descriptions come from data/classes.json), skipping what a kit
## does not have (no cast time -> no cast-bar step, no ground spell -> no placement step, ...).
## Events (strings): moved, jumped, cam_rmb, cam_lmb, zoom, click_target, tab_target, cast:<ability id>, cast_cancel, ground_cast,
## auto_on, los_hidden, interrupt, cc, debuff_seen, tooltip. A step with `manual` also waits for next().

const KEYS := ["1", "2", "Q", "E", "Shift", "F", "R"]
## Abilities that cut a cast. A kit without one practises plain crowd control instead.
const INTERRUPTS := ["pummel", "kick", "counter", "silence"]

var steps: Array = []
var index := 0
var cls := "mage"
var spec := ""
var finished := false


func _init(p_cls := "mage", p_spec := "") -> void:
	GameData.ensure_loaded()
	cls = p_cls if GameData.classes.has(p_cls) else "mage"
	spec = GameData.normalize_spec(cls, p_spec)
	_build()


static func key_of(slot: int) -> String:
	return KEYS[slot] if slot >= 0 and slot < KEYS.size() else "?"


func _abilities() -> Array:
	return GameData.abilities(cls, spec)


static func _obj(id: String, text: String, event: String) -> Dictionary:
	return {"id": id, "text": text, "event": event, "done": false}


func _step(id: String, title: String, text: String, objectives: Array, extra := {}) -> void:
	var s := {"id": id, "title": title, "text": text, "objectives": objectives, "manual": objectives.is_empty(), "arrow": "", "on_enter": ""}
	s.merge(extra, true)
	steps.append(s)


## First sentence of a description (what the ability does), kept short for the checklist.
static func short(desc: String) -> String:
	var cut := desc.find(". ")
	var one := desc if cut < 0 else desc.substr(0, cut + 1)
	return one if one.length() <= 120 else one.substr(0, 117) + "..."


func _build() -> void:
	var abs := _abilities()
	var info: Dictionary = GameData.classes[cls]
	var spec_name := ""
	if spec != "":
		spec_name = " (%s)" % str(info.specs[spec].name)
	_step("welcome", "¡Bienvenido a la arena!",
		"Vas a aprender a jugar con tu campeón: el [b]%s%s[/b]. Es una práctica tranquila: los muñecos no te hacen daño. Cada paso se completa solo cuando hacés lo que pide. Podés saltear un paso o salir cuando quieras." % [info.name, spec_name], [], {"arrow": ""})
	_step("move", "Moverte", "Movete con [key]W[/key] [key]A[/key] [key]S[/key] [key]D[/key]. Saltás con [key]Espacio[/key].",
		[_obj("moved", "Caminá unos pasos", "moved"), _obj("jumped", "Saltá una vez", "jumped")])
	_step("camera", "La cámara", "Mirá alrededor sin perder a tus enemigos. Con el botón derecho tu personaje gira junto con la cámara.",
		[_obj("rmb", "Mantené [key]clic derecho[/key] y arrastrá: mirás y girás", "cam_rmb"),
		_obj("lmb", "Mantené [key]clic izquierdo[/key] y arrastrá: orbitás sin girar al personaje", "cam_lmb"),
		_obj("zoom", "Rueda del mouse: acercás y alejás la cámara", "zoom")])
	_step("target", "Elegir un objetivo", "Los hechizos usan el objetivo que elegiste. Los enemigos tienen la barra roja; tu equipo, verde.",
		[_obj("click", "[key]Clic izquierdo[/key] sobre un muñeco enemigo para elegirlo", "click_target"),
		_obj("tab", "[key]Tab[/key] cambia al siguiente enemigo ([key]Esc[/key] suelta el objetivo)", "tab_target")], {"arrow": "dummy:mid"})
	var b: Dictionary = abs[0]
	if b.get("auto", false):
		_step("basic", "Tu ataque básico", "El [b]%s[/b] es un auto-ataque: una vez activado pega solo mientras estés a tiro y mirando al objetivo. %s" % [b.name, str(b.desc)],
			[_obj("auto", "[key]Clic derecho[/key] sobre el muñeco (o tecla [key]1[/key]) para activar el auto-ataque", "auto_on"),
			_obj("hit", "Quedate a %s m o menos de tu objetivo hasta pegarle" % str(b.range), "cast:%s" % b.id)], {"arrow": "dummy:melee"})
	else:
		_step("basic", "Tu hechizo básico", "[b]%s[/b]. %s" % [b.name, str(b.desc)],
			[_obj("cast0", "Con un objetivo elegido, apretá [key]1[/key]", "cast:%s" % b.id)], {"arrow": "bar"})
	var objs: Array = []
	for slot in range(1, 6):
		var a: Dictionary = abs[slot]
		var friendly := SpellKinds.kind(a) == "friendly"
		var tail := " (sobre el aliado herido)" if friendly else ""
		objs.append(_obj("slot%d" % slot, "[key]%s[/key] [b]%s[/b]: %s%s" % [key_of(slot), a.name, short(str(a.desc)), tail], "cast:%s" % a.id))
	_step("abilities", "Tus habilidades", "Cada habilidad tiene su tecla y su cooldown (el número sobre el ícono). Probalas todas sobre los muñecos.", objs, {"arrow": "bar"})
	var cast_slot := -1
	for slot in range(0, 6):
		if float(abs[slot].get("cast", 0)) > 0.0 and not abs[slot].get("friendly", false):
			cast_slot = slot
			break
	if cast_slot < 0:
		for slot in range(0, 6):
			if float(abs[slot].get("cast", 0)) > 0.0:
				cast_slot = slot
				break
	if cast_slot >= 0:
		var c: Dictionary = abs[cast_slot]
		var friendly := SpellKinds.kind(c) == "friendly"
		var where := " sobre el aliado herido" if friendly else " sobre un muñeco"
		_step("cast", "La barra de lanzamiento", "Algunas habilidades tardan en lanzarse: se ve una barra de progreso. [b]Moverte, saltar o apretar Esc la cancela[/b], y cualquier daño que recibas también interrumpe a los lanzadores.",
			[_obj("finish", "Lanzá [b]%s[/b] [key]%s[/key]%s y quedate quieto hasta que termine" % [c.name, key_of(cast_slot), where], "cast:%s" % c.id),
			_obj("cancel", "Ahora lanzala y moveté a mitad: se cancela", "cast_cancel")], {"arrow": "cast", "slot": cast_slot})
	var ground_slot := -1
	for slot in range(1, 6):
		if SpellKinds.kind(abs[slot]) == "ground":
			ground_slot = slot
			break
	if ground_slot >= 0:
		var g: Dictionary = abs[ground_slot]
		_step("ground", "Hechizos de zona", "[b]%s[/b] se coloca en el suelo: aparece un retículo que sigue al mouse. [key]Clic izquierdo[/key] confirma y [key]clic derecho[/key] o [key]Esc[/key] cancela." % g.name,
			[_obj("place", "Apretá [key]%s[/key] y colocá [b]%s[/b] con clic izquierdo, bajo el muñeco móvil" % [key_of(ground_slot), g.name], "ground_cast")], {"arrow": "dummy:patrol"})
	_step("los", "Línea de visión", "Los hechizos necesitan [b]línea de visión[/b]: los pilares y paredes tapan. El muñeco hechicero (a la derecha) lanza un hechizo largo.",
		[_obj("hide", "Escondete detrás del pilar del centro-izquierda para que no te vea", "los_hidden")], {"arrow": "dummy:caster"})
	var interrupt_slot := -1
	for slot in range(1, 6):
		if INTERRUPTS.has(str(abs[slot].id)):
			interrupt_slot = slot
			break
	if interrupt_slot >= 0:
		var it: Dictionary = abs[interrupt_slot]
		_step("control", "Interrumpir al hechicero", "Cortar un lanzamiento lo deja bloqueado unos segundos. Tu [b]%s[/b] interrumpe: %s" % [it.name, short(str(it.desc))],
			[_obj("kick", "Esperá a que el muñeco hechicero empiece a lanzar (barra sobre su cabeza) y apretá [key]%s[/key] sobre él" % key_of(interrupt_slot), "interrupt")], {"arrow": "dummy:caster"})
	else:
		_step("control", "Control de masas", "Aturdir, aterrorizar, enraizar o ralentizar da ventaja. Los efectos repetidos rinden cada vez menos (retornos decrecientes).",
			[_obj("cc", "Usá cualquier habilidad que controle (aturdir, enraizar, ralentizar, miedo...) sobre un muñeco", "cc")], {"arrow": "dummy:mid"})
	_step("debuffs", "Efectos y tooltips", "Debajo de cada objetivo ves sus efectos (debuffs) con el tiempo que les queda. Pasá el mouse por un ícono para leer qué hace.",
		[_obj("debuff", "Elegí un muñeco con un efecto activo y mirá su cuadro arriba", "debuff_seen"),
		_obj("tip", "Pasá el mouse sobre una habilidad de tu barra para leer su descripción", "tooltip")], {"arrow": "target_panel"})
	var ult: Dictionary = abs[6]
	var ult_where := " Se coloca en el suelo con el retículo: clic izquierdo confirma." if SpellKinds.kind(ult) == "ground" else ""
	_step("ult", "La definitiva", "[b]%s[/b] [key]R[/key] se carga haciendo y recibiendo daño. Para la práctica te la dejamos lista. %s%s" % [ult.name, short(str(ult.desc)), ult_where],
		[_obj("ult", "Usá tu definitiva", "cast:%s" % ult.id)], {"arrow": "bar", "on_enter": "ult"})
	_step("rounds", "Cómo es una partida real",
		"Cada equipo arranca en su [b]sala de inicio[/b] con las puertas cerradas (10 s antes de cada ronda). Ahí podés usar escudos y curas.\n\nCuando las puertas se abren, empieza la pelea. Gana la ronda el equipo que elimina a todos los rivales; gana la partida el primero en ganar [b]2 rondas[/b] (al mejor de 3).\n\nSi la ronda se estira, aparece la [b]amortiguación[/b]: pasados 40 s la curación recibida baja cada vez más (2% por segundo), así los duelos de sanadores terminan.",
		[], {"arrow": "score"})
	_step("done", "¡Listo!", "Ya sabés lo básico. Probá la [b]Arena de práctica[/b] para repetir rotaciones con medidor de daño, o jugá contra bots.", [], {"final": true})


func current() -> Dictionary:
	return steps[mini(index, steps.size() - 1)]


func is_done() -> bool:
	return finished


## Feeds a gameplay event. Returns true when something changed (an objective got checked or the step advanced).
func push(event: String) -> bool:
	if finished:
		return false
	var s := current()
	var changed := false
	for o in s.objectives:
		if not o.done and o.event == event:
			o.done = true
			changed = true
	if changed and not s.manual and _objectives_done(s):
		_advance()
	return changed


func _objectives_done(s: Dictionary) -> bool:
	for o in s.objectives:
		if not o.done:
			return false
	return true


## "Continuar" on information steps (and "Saltar" on any step).
func next() -> void:
	if finished:
		return
	_advance()


func _advance() -> void:
	if index >= steps.size() - 1:
		finished = true
		return
	index += 1


func progress() -> Vector2:
	return Vector2(index + 1, steps.size())


func objective_events() -> Array:
	var out: Array = []
	for o in current().objectives:
		if not o.done:
			out.append(o.event)
	return out
