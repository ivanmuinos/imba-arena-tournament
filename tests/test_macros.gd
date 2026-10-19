extends TestBase
## Macros: parsing (commands, [@focus], ability names with or without accents), the store and its key bindings.


func test_parse_focus_cast_and_chains() -> void:
	var m := Macro.parse("#Oveja\n/cast [@focus] polimorfia", "mage", "fire")
	eq(m.name, "Oveja", "el comentario nombra la macro")
	eq(m.lines.size(), 1, "una línea")
	eq(m.lines[0].at, "focus", "al foco")
	eq(m.lines[0].slots, [3], "Polimorfia es la 4ta habilidad")
	var chain := Macro.parse("/cast Patada\n/cast Puñalada", "rogue")
	eq(chain.lines.map(func(l): return l.slots[0]), [5, 0], "dos /cast encadenados")
	var seq := Macro.parse("/castsequence Golpe mortal, Seccionar", "warrior")
	eq(seq.lines[0].slots, [1, 3], "secuencia")
	eq(Macro.parse("/cast Pualada", "rogue").errors.size(), 1, "nombre desconocido: error")
	eq(Macro.slot_for("PUNALADA", "rogue"), 0, "sin tildes ni mayúsculas")
	eq(Macro.slot_for("Q", "rogue"), 2, "por tecla")
	eq(Macro.slot_for("eviscerate", "rogue"), 1, "por id")
	var misc := Macro.parse("/focus\n/target focus\n/clearfocus\n/stopcasting\n/bailar\n/cast [@luna] Patada", "rogue")
	eq(misc.lines.map(func(l): return l.cmd), ["focus", "target", "clearfocus", "stopcasting"], "comandos de foco")
	eq(misc.errors.size(), 2, "comando y condición desconocidos")


func test_store_keeps_one_macro_per_key() -> void:
	var path := "user://test_macros.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var s := MacroStore.new(path)
	eq(s.macros.size(), MacroStore.COUNT, "6 macros")
	eq(s.index_for_key("Ctrl+2"), 1, "Ctrl+2 por defecto")
	eq(s.index_for_key("Ctrl+6"), -1, "una macro vacía no se dispara")
	s.set_macro(5, "Ctrl+2", "/focus")
	eq(s.index_for_key("Ctrl+2"), 5, "la tecla pasa a la otra macro")
	eq(s.macros[1].key, "", "y la anterior queda sin tecla")
	s.save()
	eq(MacroStore.new(path).macros[5].text, "/focus", "queda guardada")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
