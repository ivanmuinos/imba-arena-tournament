extends TestBase
## The player's arrangement of the action bar: position on the bar -> canonical ability slot, per kit.

const PATH := "user://test_bar_layouts.json"
const KIT := "mage/fire"


func _fresh() -> BarLayout:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	return BarLayout.new(PATH)


func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_every_kit_starts_in_the_canonical_order() -> void:
	var l := _fresh()
	for pos in BarLayout.size():
		eq(l.slot_at(KIT, pos), pos, "posición %d sin tocar" % pos)
		eq(l.pos_of(KIT, pos), pos, "slot %d sin tocar" % pos)


func test_swap_moves_both_buttons_and_only_that_kit() -> void:
	var l := _fresh()
	check(l.swap(KIT, 0, 4), "el intercambio se aplica")
	eq(l.slot_at(KIT, 0), 4, "la definitiva pasa al primer botón")
	eq(l.slot_at(KIT, 4), 0, "el básico pasa al último")
	eq(l.pos_of(KIT, 4), 0, "pos_of es la inversa de slot_at")
	eq(l.slot_at("warrior", 0), 0, "otro kit no cambia")


func test_swap_rejects_what_is_not_on_the_bar() -> void:
	var l := _fresh()
	check(not l.swap(KIT, 0, 0), "misma posición")
	check(not l.swap(KIT, -1, 2), "posición negativa")
	check(not l.swap(KIT, 0, BarLayout.size()), "fuera de la barra")
	eq(l.order(KIT), [0, 1, 2, 3, 4], "el orden sigue igual")


func test_out_of_range_lookups_pass_through() -> void:
	var l := _fresh()
	l.swap(KIT, 0, 1)
	eq(l.slot_at(KIT, 9), 9, "slot_at fuera de rango")
	eq(l.pos_of(KIT, -1), -1, "pos_of fuera de rango")


func test_layout_survives_a_reload() -> void:
	var l := _fresh()
	l.swap(KIT, 1, 3)
	l.save()
	eq(BarLayout.new(PATH).order(KIT), [0, 3, 2, 1, 4], "se guarda por kit")


func test_reset_returns_to_the_canonical_order() -> void:
	var l := _fresh()
	l.swap(KIT, 1, 3)
	check(l.is_custom(KIT), "queda marcado como cambiado")
	l.reset(KIT)
	check(not l.is_custom(KIT), "vuelve al orden normal")
	eq(l.slot_at(KIT, 1), 1, "reset restablece")


func test_corrupt_files_fall_back_to_the_canonical_order() -> void:
	for text in ["no es json", "[]", "{\"layouts\": 3}"]:
		_write(text)
		eq(BarLayout.new(PATH).order(KIT), [0, 1, 2, 3, 4], "archivo inválido: %s" % text)
	for bad in ["[0,0,1,2,3]", "[0,1,2]", "[0,1,2,3,9]", "[0,1,2,3,-1]", "\"x\"", "[0.5,1,2,3,4]"]:
		_write("{\"_v\":1,\"layouts\":{\"%s\":%s}}" % [KIT, bad])
		eq(BarLayout.new(PATH).order(KIT), [0, 1, 2, 3, 4], "no es permutación: %s" % bad)


func test_json_numbers_load_as_a_usable_permutation() -> void:
	_write("{\"_v\":1,\"layouts\":{\"%s\":[4,3,2,1,0]}}" % KIT)
	var l := BarLayout.new(PATH)
	eq(l.slot_at(KIT, 0), 4, "lee el orden guardado")
	eq(typeof(l.slot_at(KIT, 0)), TYPE_INT, "los números de JSON quedan como enteros")


## Records what a button press would cast instead of sending it.
class SpyView extends MatchView:
	var casts: Array = []
	var focus_casts: Array = []

	func _cast(slot: int) -> bool:
		casts.append(slot)
		return true

	func _cast_on_focus(slot: int) -> bool:
		focus_casts.append(slot)
		return true


func _with_swapped_bar(cb: Callable) -> void:
	var shared := BarLayout.shared()
	shared.swap(KIT, 0, 4)
	cb.call()
	shared.reset(KIT)


func _spy() -> SpyView:
	var view := SpyView.new()
	TestBase.tree.root.add_child(view)
	view.my_cls = "mage"
	view.my_spec = "fire"
	view._active = true
	return view


func test_a_button_casts_the_ability_arranged_on_it() -> void:
	_with_swapped_bar(func():
		var view := _spy()
		view._do_action("slot_0")
		view._do_action("slot_4")
		view._do_action("slot_1")
		eq(view.casts, [4, 0, 1], "la tecla de cada botón lanza lo que tiene ese botón")
		view.free())


func test_shift_casts_the_arranged_ability_on_the_focus() -> void:
	_with_swapped_bar(func():
		var view := _spy()
		var k := InputEventKey.new()
		k.keycode = KEY_1
		k.pressed = true
		k.shift_pressed = true
		view._input(k)
		eq(view.focus_casts, [4], "Shift + botón 1 lanza al foco la definitiva que está ahí")
		view.free())


func test_the_gamepad_casts_the_arranged_ability() -> void:
	_with_swapped_bar(func():
		var view := _spy()
		var b := InputEventJoypadButton.new()
		b.button_index = JOY_BUTTON_X
		b.pressed = true
		view._input(b)
		eq(view.casts, [4], "el mando sigue a la posición")
		view.free())


func _hud() -> Hud:
	var hud := Hud.new()
	TestBase.tree.root.add_child(hud)
	hud.setup([{"id": 1, "team": "red", "cls": "mage", "spec": "fire", "name": "Yo", "bot": false}], 1, "mage", "red", "fire")
	return hud


func test_the_hud_draws_the_arranged_order() -> void:
	_with_swapped_bar(func():
		var hud := _hud()
		var kb := Keybinds.shared()
		eq((hud._slots[4].key as Label).text, kb.slot_label(0), "la definitiva muestra la tecla del botón 1")
		eq((hud._slots[0].key as Label).text.trim_prefix("Auto · "), kb.slot_label(4), "el básico muestra la tecla del último botón")
		check((hud._slots[4].root as Control).global_position.x < (hud._slots[0].root as Control).global_position.x, "la definitiva se dibuja a la izquierda")
		(hud._slots[4].root as Control).mouse_entered.emit()
		eq(hud.hovered_action(), "slot_0", "pasar el mouse informa el botón, para reasignar su tecla")
		eq(hud.tooltip_slot(), 4, "el tooltip es de la habilidad real")
		eq(hud._ability_tip._key.text, kb.slot_label(0), "el tooltip muestra la tecla del botón")
		hud.free())


func test_a_talent_swap_stays_on_the_arranged_button() -> void:
	var swaps := 0
	for cls in GameData.playable_ids():
		for spec in (GameData.spec_ids(cls) if not GameData.spec_ids(cls).is_empty() else [""]):
			var base: Array = GameData.kit(cls, spec).abilities
			var ids: Array = base.map(func(a): return str(a.id))
			var rows := Talents.rows(cls, spec)
			for r in rows.size():
				for i in (rows[r] as Array).size():
					for e in rows[r][i].effects:
						if str(e.op) != "swap":
							continue
						var picks := [-1, -1]
						picks[r] = i
						var after: Array = Talents.apply(GameData.kit(cls, spec), cls, spec, picks).abilities
						eq(str(after[ids.find(str(e.ability))].id), str(e.to), "%s: %s ocupa el lugar de %s" % [Talents.key(cls, spec), e.to, e.ability])
						swaps += 1
	check(swaps > 0, "hay talentos que cambian una habilidad")


func test_every_screen_names_the_ability_on_each_button() -> void:
	_with_swapped_bar(func():
		var fire := GameData.abilities("mage", "fire")
		var menu := GameMenu.new()
		TestBase.tree.root.add_child(menu)
		menu.kit_cls = "mage"
		menu.kit_spec = "fire"
		menu.open()
		menu.show_tab("keys")
		eq((menu._key_names.slot_0 as Label).text, "Definitiva: " + str(fire[4].name), "el botón 1 es la definitiva")
		eq((menu._key_names.slot_4 as Label).text, "5. " + str(fire[0].name), "el botón 5 es el básico")
		menu.free())


func test_macros_read_a_key_as_the_button_it_presses() -> void:
	_with_swapped_bar(func():
		eq(Macro.slot_for(Keybinds.shared().slot_label(0), "mage", "fire"), 4, "la tecla del botón 1 es la definitiva")
		var fire := GameData.abilities("mage", "fire")
		eq(Macro.slot_for(str(fire[4].name), "mage", "fire"), 4, "por nombre sigue siendo la habilidad"))


func test_tutorial_text_names_the_key_of_the_arranged_button() -> void:
	_with_swapped_bar(func():
		var flow := TutorialFlow.new("mage", "fire")
		eq(flow.key_of(4), Keybinds.shared().slot_label(0), "la definitiva está en la tecla del botón 1"))


func test_action_labels_describe_buttons_not_abilities() -> void:
	eq(Keybinds.action_label("slot_0"), "Botón 1", "Keybinds")
	eq(Keybinds.action_label("slot_4"), "Botón 5", "Keybinds: la definitiva puede estar en otro botón")
