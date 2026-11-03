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
