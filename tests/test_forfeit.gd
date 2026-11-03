extends TestBase
## Forfeit panel (S9): when Esc opens it, what it says, and that its buttons emit the right signals.


func test_esc_opens_only_when_there_is_nothing_else_to_cancel() -> void:
	check(ForfeitPanel.esc_opens(false, false, false, true), "Esc sin nada que cancelar abre el panel")
	check(not ForfeitPanel.esc_opens(true, false, false, true), "primero se cancela el hechizo en el suelo")
	check(not ForfeitPanel.esc_opens(false, true, false, true), "primero se corta el lanzamiento")
	check(not ForfeitPanel.esc_opens(false, false, true, true), "primero se suelta el objetivo")
	check(not ForfeitPanel.esc_opens(false, false, false, false), "práctica y online: sin panel")


func test_message_says_it_counts_as_a_loss_in_the_tournament() -> void:
	check(ForfeitPanel.message(true).contains("derrota"), "torneo: cuenta como derrota")
	check(ForfeitPanel.message(true).contains("torneo"), "menciona el torneo")
	check(not ForfeitPanel.message(false).contains("torneo"), "contra bots normales no habla del torneo")


func test_buttons_emit_and_hide() -> void:
	var p := ForfeitPanel.new()
	tree.root.add_child(p)
	var got: Array = []
	p.confirmed.connect(func(): got.append("yes"))
	p.cancelled.connect(func(): got.append("no"))
	p.open("x")
	check(p.visible, "abierto")
	p.confirm_button.pressed.emit()
	eq(got, ["yes"], "confirmar")
	check(not p.visible, "se cierra al confirmar")
	p.open("x")
	p.stay_button.pressed.emit()
	eq(got, ["yes", "no"], "seguir peleando")
	p.queue_free()
