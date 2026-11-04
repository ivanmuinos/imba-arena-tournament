extends TestBase
## Medals of the Academia and the progress that keeps them.

const PATH := "user://test_academy.json"
const RULE := {"silver": {"max_time_ms": 60000.0}, "gold": {"max_time_ms": 30000.0, "max_mistakes": 0}}


func _fresh(seen := false) -> AcademyStore:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	return AcademyStore.new(PATH, seen)


func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run(ms: float, mistakes := 0, skipped := 0) -> Dictionary:
	return {"skipped": skipped, "time_ms": ms, "mistakes": mistakes, "taken": 0.0, "downs": 0, "hp_pct": 1.0}


func test_medals_grade_a_run() -> void:
	eq(AcademyMedals.grade(RULE, _run(20000.0)), AcademyMedals.GOLD, "rápido y sin errores")
	eq(AcademyMedals.grade(RULE, _run(20000.0, 1)), AcademyMedals.SILVER, "rápido con un error")
	eq(AcademyMedals.grade(RULE, _run(45000.0)), AcademyMedals.SILVER, "tiempo medio")
	eq(AcademyMedals.grade(RULE, _run(90000.0)), AcademyMedals.BRONZE, "terminar siempre da bronce")
	eq(AcademyMedals.grade(RULE, _run(20000.0, 0, 1)), AcademyMedals.NONE, "saltear un paso no da medalla")


func test_every_condition_can_fail_a_medal() -> void:
	var cases := [
		[{"max_time_ms": 10.0}, {"time_ms": 11.0}],
		[{"max_taken": 10.0}, {"taken": 11.0}],
		[{"max_mistakes": 1}, {"mistakes": 2}],
		[{"max_downs": 0}, {"downs": 1}],
		[{"min_hp_pct": 0.6}, {"hp_pct": 0.5}],
	]
	for c in cases:
		var bad: Dictionary = c[1]
		eq(AcademyMedals.grade({"gold": c[0]}, bad), AcademyMedals.BRONZE, "falla %s" % str(c[0]))
	eq(AcademyMedals.grade({"gold": {"max_taken": 10.0, "min_hp_pct": 0.6}}, {"taken": 10.0, "hp_pct": 0.6}), AcademyMedals.GOLD, "justo en el límite alcanza")
	eq(AcademyMedals.grade({"gold": {"max_taken": 10.0}}, {}), AcademyMedals.BRONZE, "un dato que falta no regala la medalla")
	eq(AcademyMedals.grade({"gold": {"algo_raro": 1}}, _run(1.0)), AcademyMedals.BRONZE, "una condición desconocida no regala la medalla")


func test_gold_needs_silver_rules_too() -> void:
	var rule := {"silver": {"max_mistakes": 0}, "gold": {"max_time_ms": 100.0}}
	eq(AcademyMedals.grade(rule, _run(50.0, 1)), AcademyMedals.BRONZE, "oro exige también lo de plata")


func test_a_lesson_without_a_rule_is_simply_done() -> void:
	eq(AcademyMedals.grade({}, _run(99999.0, 9)), AcademyMedals.GOLD, "sin regla: hecha es hecha")
	eq(AcademyMedals.grade({}, _run(1.0, 0, 1)), AcademyMedals.NONE, "salteada no")


func test_the_flow_keeps_the_stats_of_a_run() -> void:
	var f := LessonFlow.new("x", "X", "c", "s")
	f.mistake_keys = ["self_break"]
	f.add_step("a", "A", "", [StepFlow.obj("o", "o", "go")])
	f.add_step("b", "B", "", [], {"final": true})
	f.tick(100.0)
	f.note_event({"e": "cc_break", "by": 1}, 1)
	f.note_event({"e": "cc_break", "by": 2}, 1)
	f.note_event({"e": "dmg", "t": 1, "by": 2, "amt": 30.0}, 1)
	f.note_event({"e": "dmg", "t": 2, "by": 1, "amt": 99.0}, 1)
	f.note_event({"e": "down", "t": 1}, 1)
	f.note_event({"e": "down", "t": 2}, 1)
	var s := f.stats(0.75)
	eq(s.time_ms, 100.0, "tiempo")
	eq(s.mistakes, 1, "solo errores propios y de la lista")
	eq(s.taken, 30.0, "solo el daño recibido")
	eq(s.downs, 1, "solo tus caídas")
	eq(s.hp_pct, 0.75, "vida al terminar")
	eq(s.skipped, 0, "sin saltos")


func test_the_store_keeps_the_best_of_every_try() -> void:
	var a := _fresh()
	eq(a.medal("moverse"), 0, "sin jugar")
	check(not a.played("moverse"), "sin jugar")
	check(a.record("moverse", AcademyMedals.SILVER, 40000.0), "primera medalla: es nuevo récord")
	check(not a.record("moverse", AcademyMedals.BRONZE, 90000.0), "peor: no es récord")
	eq(a.medal("moverse"), AcademyMedals.SILVER, "guarda la mejor medalla")
	eq(a.best_ms("moverse"), 40000.0, "y el mejor tiempo")
	a.record("moverse", AcademyMedals.SILVER, 30000.0)
	eq(a.best_ms("moverse"), 30000.0, "un tiempo mejor se guarda")
	a.record("moverse", AcademyMedals.NONE, 1.0)
	eq(a.best_ms("moverse"), 30000.0, "un intento con pasos salteados no cuenta como tiempo")
	eq(a.plays("moverse"), 4, "cuenta los intentos")
	check(a.save(), "guarda")
	var b := AcademyStore.new(PATH, false)
	eq(b.medal("moverse"), AcademyMedals.SILVER, "sobrevive a recargar")
	eq(b.best_ms("moverse"), 30000.0, "el tiempo también")
	eq(b.plays("moverse"), 4, "y los intentos")


func test_a_skipped_try_still_counts_as_seen() -> void:
	var a := _fresh()
	check(not a.record("camara", AcademyMedals.NONE, 5.0), "sin medalla no hay récord")
	check(a.played("camara"), "pero la lección queda vista")
	eq(a.medal("camara"), 0, "sin medalla")


func test_existing_players_are_not_offered_it_again() -> void:
	check(not _fresh(false).offered, "jugador nuevo: se le ofrece")
	check(_fresh(true).offered, "ya vio el tutorial viejo: no")
	var a := _fresh(false)
	a.mark_offered()
	a.save()
	check(AcademyStore.new(PATH, false).offered, "rechazar la oferta se recuerda")
	_write("{\"_v\":1,\"offered\":false,\"lessons\":{}}")
	check(not AcademyStore.new(PATH, true).offered, "con archivo manda el archivo")


func test_corrupt_files_never_break_or_cheat() -> void:
	for text in ["no es json", "[]", "{\"lessons\": 3}"]:
		_write(text)
		var a := AcademyStore.new(PATH, false)
		eq(a.medal("moverse"), 0, "archivo inválido: %s" % text)
	_write("{\"_v\":1,\"lessons\":{\"moverse\":{\"medal\":99,\"best_ms\":-5,\"plays\":-1},\"otra\":\"x\",\"vieja\":{\"medal\":2,\"best_ms\":10,\"plays\":1}}}")
	var c := AcademyStore.new(PATH, false)
	eq(c.medal("moverse"), AcademyMedals.GOLD, "una medalla imposible se recorta")
	eq(c.best_ms("moverse"), 0.0, "tiempo negativo se descarta")
	eq(c.plays("moverse"), 0, "intentos negativos se descartan")
	eq(c.medal("otra"), 0, "entrada inválida se ignora")
	eq(c.medal("vieja"), AcademyMedals.SILVER, "una lección que ya no está en el catálogo se conserva")


func test_closing_words_say_what_you_earned() -> void:
	check(AcademyMedals.result_text(AcademyMedals.GOLD, 65000.0, true).contains("oro"), "nombra la medalla")
	check(AcademyMedals.result_text(AcademyMedals.GOLD, 65000.0, true).contains("1:05"), "y el tiempo")
	check(AcademyMedals.result_text(AcademyMedals.BRONZE, 1000.0, true).contains("mejor"), "avisa un récord")
	check(not AcademyMedals.result_text(AcademyMedals.BRONZE, 1000.0, false).contains("mejor"), "y no lo inventa")
	check(AcademyMedals.result_text(AcademyMedals.NONE, 1000.0, false).contains("Salteaste"), "sin medalla explica por qué")


func test_every_lesson_has_a_reachable_gold() -> void:
	var f := AcademyCatalog.lesson("moverse", "mage", "fire")
	eq(AcademyMedals.grade(f.medal_rule, f.stats(1.0)), AcademyMedals.GOLD, "una corrida rápida y limpia llega al oro")
	f.active_ms = 10000000.0
	eq(AcademyMedals.grade(f.medal_rule, f.stats(1.0)), AcademyMedals.BRONZE, "una muy lenta se queda en bronce")

