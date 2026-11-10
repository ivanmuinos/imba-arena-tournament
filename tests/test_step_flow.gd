extends TestBase
## The small state machine under the tutorial and the Academia lessons.


func _flow() -> StepFlow:
	var f := StepFlow.new()
	f.add_step("a", "A", "texto", [StepFlow.obj("x", "Hacé x", "ev:x"), StepFlow.obj("y", "Hacé y", "ev:y")])
	f.add_step("b", "B", "informativo", [])
	f.add_step("c", "C", "contar", [StepFlow.obj("n", "Tres veces", "ev:n", 3)])
	return f


func test_a_step_needs_every_objective() -> void:
	var f := _flow()
	check(f.push("ev:x"), "marca el objetivo")
	eq(f.current().id, "a", "falta otro")
	check(not f.push("ev:x"), "repetir no cambia nada")
	check(not f.push("otro"), "un evento ajeno tampoco")
	eq(f.objective_events(), ["ev:y"], "lo que falta")
	check(f.push("ev:y"), "el segundo")
	eq(f.current().id, "b", "avanza solo")


func test_an_info_step_waits_for_next() -> void:
	var f := _flow()
	f.next()
	check(f.current().manual, "sin objetivos es manual")
	check(not f.push("ev:n"), "no reacciona a eventos")
	f.next()
	eq(f.current().id, "c", "avanza con next")


func test_an_objective_can_need_several_events() -> void:
	var f := _flow()
	f.next()
	f.next()
	check(f.push("ev:n"), "uno cuenta")
	eq(f.current().objectives[0].n, 1, "lleva la cuenta")
	check(not f.current().objectives[0].done, "todavía no")
	f.push("ev:n")
	f.push("ev:n")
	check(f.current().objectives[0].done, "a la tercera")


func test_the_last_step_finishes_the_flow() -> void:
	var f := _flow()
	f.next()
	f.next()
	eq(f.progress(), Vector2(3, 3), "último paso")
	check(not f.is_done(), "todavía abierto")
	for i in 3:
		f.push("ev:n")
	check(f.is_done(), "terminó")
	check(not f.push("ev:x"), "ya no reacciona")
	f.next()
	check(f.is_done(), "next no rompe nada")
