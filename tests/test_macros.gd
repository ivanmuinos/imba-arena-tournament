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


func test_store_saves_texts_and_keybinds_keep_one_action_per_key() -> void:
	var path := "user://test_macros.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var s := MacroStore.new(path)
	eq(s.macros.size(), MacroStore.COUNT, "6 macros")
	eq(s.title(1), "Oveja al foco", "nombre del comentario")
	check(s.is_empty(5), "la 6ta viene vacía")
	s.set_text(5, "/focus")
	s.save()
	eq(MacroStore.new(path).macros[5].text, "/focus", "queda guardada")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var kpath := "user://test_keybinds.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(kpath))
	var k := Keybinds.new(kpath)
	eq(k.action_for("Q"), "slot_2", "Q: habilidad 3 por defecto")
	eq(k.action_for("Ctrl+2"), "macro_2", "Ctrl+2: macro 2")
	eq(k.bind("slot_2", "Ctrl+2"), "macro_2", "reasignar quita la tecla a la otra acción")
	eq(k.key_of("macro_2"), "", "la macro queda sin tecla")
	eq(k.slot_label(2), "Ctrl+2", "la barra muestra la tecla nueva")
	eq(k.label("jump"), "Espacio", "nombre amigable")
	k.save()
	eq(Keybinds.new(kpath).action_for("Ctrl+2"), "slot_2", "queda guardado")
	k.reset()
	eq(k.action_for("Q"), "slot_2", "restablecer")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(kpath))
