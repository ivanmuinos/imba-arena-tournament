extends TestBase
## "Cómo jugar": the step machine is built from each class kit and only advances when the player does the action.

func _run_to(flow: TutorialFlow, id: String) -> void:
	var guard := 0
	while flow.current().id != id and guard < 40:
		guard += 1
		var s := flow.current()
		if s.manual:
			flow.next()
		else:
			for o in s.objectives.duplicate():
				flow.push(o.event)


func test_every_class_and_spec_builds_a_complete_tutorial() -> void:
	for cls in GameData.classes:
		var specs: Array = GameData.spec_ids(cls)
		for sp in (specs if not specs.is_empty() else [""]):
			var f := TutorialFlow.new(cls, sp)
			var ids: Array = f.steps.map(func(s): return s.id)
			for need in ["welcome", "move", "camera", "target", "basic", "abilities", "los", "control", "debuffs", "ult", "rounds", "done"]:
				check(ids.has(need), "%s/%s: paso %s" % [cls, sp, need])
			var texts := ""
			for s in f.steps:
				texts += s.title + s.text
				check(s.title != "" and s.text != "", "%s/%s: texto en %s" % [cls, sp, s.id])
				for o in s.objectives:
					texts += o.text
					check(o.event != "", "%s/%s: objetivo con evento (%s)" % [cls, sp, o.id])
			check(not texts.contains("  "), "%s/%s: sin espacios dobles" % [cls, sp])


func test_steps_only_advance_when_the_player_does_the_action() -> void:
	var f := TutorialFlow.new("mage", "fire")
	eq(f.current().id, "welcome", "empieza con la bienvenida")
	f.push("moved")
	eq(f.current().id, "welcome", "una acción que no se pidió no avanza")
	f.next()
	eq(f.current().id, "move", "pasó a moverse")
	f.push("moved")
	eq(f.current().id, "move", "falta saltar")
	check(f.current().objectives[0].done and not f.current().objectives[1].done, "tilde sólo en lo hecho")
	f.push("jumped")
	eq(f.current().id, "camera", "completó el paso")
	f.push("zoom")
	f.push("cam_rmb")
	eq(f.current().id, "camera", "faltan objetivos")
	f.push("cam_lmb")
	eq(f.current().id, "target", "cámara completa")


func test_info_steps_wait_for_continue_and_events_are_ignored_there() -> void:
	var f := TutorialFlow.new("warrior")
	_run_to(f, "rounds")
	eq(f.current().id, "rounds", "llegó al flujo de partida")
	f.push("moved")
	eq(f.current().id, "rounds", "las informativas no avanzan solas")
	f.next()
	eq(f.current().id, "done", "continuar avanza")
	check(f.current().get("final", false), "paso final")
	f.next()
	check(f.is_done(), "terminó")
	check(not f.push("moved"), "ya no reacciona")


func test_kit_specific_steps_follow_the_class() -> void:
	var warrior := TutorialFlow.new("warrior")
	var mage := TutorialFlow.new("mage", "fire")
	var priest := TutorialFlow.new("priest")
	var ids := func(f: TutorialFlow) -> Array: return f.steps.map(func(s): return s.id)
	check(ids.call(warrior).has("basic") and warrior.steps[4].objectives[0].event == "auto_on", "el guerrero practica el auto-ataque")
	check(mage.steps[4].objectives[0].event == "cast:fireball", "el mago lanza bola de fuego")
	check(ids.call(mage).has("cast"), "el mago tiene barra de lanzamiento")
	check(not ids.call(warrior).has("cast"), "el guerrero no tiene hechizos con cast")
	check(not ids.call(mage).has("ground"), "el mago sólo tiene zona en la definitiva: no hay paso aparte")
	var hunter := TutorialFlow.new("hunter")
	check(ids.call(hunter).has("ground"), "el cazador coloca la trampa en el suelo: paso de zona")
	var ctrl := func(f: TutorialFlow) -> Dictionary:
		for s in f.steps:
			if s.id == "control":
				return s
		return {}
	eq(ctrl.call(warrior).objectives[0].event, "interrupt", "el guerrero interrumpe con Golpe de escudo")
	eq(ctrl.call(priest).objectives[0].event, "cc", "el sacerdote practica control (no interrumpe)")
	var ab := func(f: TutorialFlow) -> Dictionary:
		for s in f.steps:
			if s.id == "abilities":
				return s
		return {}
	eq(ab.call(priest).objectives.size(), 5, "cinco habilidades en el paso de habilidades")
	check(str(ab.call(priest).objectives[0].text).contains("Sanación"), "usa los nombres reales de la clase")
	check(str(ab.call(priest).objectives[0].text).contains("aliado"), "avisa de las curas a aliados")


func test_ultimate_step_grants_the_ult_and_events_use_real_ability_ids() -> void:
	var f := TutorialFlow.new("rogue")
	var ult: Dictionary = {}
	for s in f.steps:
		if s.id == "ult":
			ult = s
	eq(ult.on_enter, "ult", "la definitiva se deja lista")
	eq(ult.objectives[0].event, "cast:%s" % GameData.ability("rogue", 6).id, "evento con el id real")


func test_skip_and_progress() -> void:
	var f := TutorialFlow.new("hunter")
	eq(f.progress().x, 1.0, "paso 1")
	f.next()
	f.next()
	eq(f.current().id, "camera", "saltar un paso con objetivos")
	check(f.progress().x == 3.0 and f.progress().y == float(f.steps.size()), "progreso")


func test_short_trims_long_descriptions() -> void:
	eq(TutorialFlow.short("Una frase. Otra frase."), "Una frase.", "primera oración")
	check(TutorialFlow.short("x".repeat(300)).length() <= 120, "recorta")


func test_practice_panel_row_texts_and_number_format() -> void:
	var rows := [{"id": "fireball", "dmg": 12345, "pct": 61.6, "hits": 5, "crits": 2, "casts": 6}, {"id": "burn", "dmg": 70, "pct": 0.35, "hits": 2, "crits": 0, "casts": 0}]
	var t := PracticePanel.row_texts(rows, "mage", "fire")
	eq(t[0], ["Bola de fuego", "12 345", "62%", "6", "2"], "fila con nombre real, miles y porcentaje")
	eq(t[1][0], "Quemadura", "las quemaduras tienen nombre")
	eq(PracticePanel._n(999), "999", "sin separador")
	eq(PracticePanel._n(1234567), "1 234 567", "separador de miles")


func test_teaches_trinket_focus_macros_and_keybinds_with_the_real_keys() -> void:
	var f := TutorialFlow.new("rogue")
	var ids: Array = f.steps.map(func(s): return s.id)
	for id in ["trinket", "keys"]:
		check(ids.has(id), "paso %s" % id)
	eq(ids.has("focus"), MacroStore.ENABLED, "el paso de foco y macros sólo con macros activadas")
	var t: Dictionary = f.steps[ids.find("trinket")]
	eq(t.on_enter, "stun", "te aturde para que uses el abalorio")
	check(str(t.objectives[0].text).contains(Keybinds.shared().label("trinket")), "muestra la tecla del abalorio")
	if MacroStore.ENABLED:
		var events: Array = f.steps[ids.find("focus")].objectives.map(func(o): return o.event)
		eq(events, ["focus_set", "tab_target", "macro_cast"], "marcar foco, cambiar de objetivo, macro al foco")
	check(ids.find("keys") < ids.find("rounds"), "antes del resumen de la partida")
