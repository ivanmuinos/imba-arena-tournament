class_name Macro
extends RefCounted
## WoW-style macros, parsed once and run by the match view. One command per line:
##   /cast [@focus] Polimorfia     the ability (name, id or slot key) on the focus, without changing your target
##   /cast [@target] / [@player]   on the target (the default) or yourself
##   /cast A                       several /cast lines: those off the global cooldown go out together, the rest queue
##   /castsequence A, B, C         one step per press (back to the first after RESET_MS without pressing)
##   /focus                        your target becomes your focus;  /clearfocus  drops it
##   /target focus                 selects your focus;  /stopcasting  cancels the cast in progress
## Lines starting with # are comments (the first one names the macro).

const RESET_MS := 6000.0
const COMMANDS := ["cast", "castsequence", "focus", "clearfocus", "target", "stopcasting"]

## Shown in the editor.
const HELP := """/cast [@focus] Polimorfia — al foco sin cambiar de objetivo
/cast Patada  +  /cast Puñalada — encadena: lo que no usa GCD sale junto, lo demás se encola
/castsequence Golpe mortal, Seccionar — un paso por toque
/focus — tu objetivo pasa a ser tu foco · /clearfocus · /target focus · /stopcasting
[@target] (por defecto) · [@focus] · [@player]"""


## {name, lines: [{cmd, at, slots: [int], arg}], errors: [String]}. `cls`/`spec` resolve ability names to slots.
static func parse(text: String, cls: String, spec := "") -> Dictionary:
	var out := {"name": "", "lines": [], "errors": []}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "":
			continue
		if line.begins_with("#"):
			if out.name == "":
				out.name = line.substr(1).strip_edges()
			continue
		if not line.begins_with("/"):
			out.errors.append("No es un comando: %s" % line)
			continue
		var sp := line.find(" ")
		var cmd := (line.substr(1) if sp < 0 else line.substr(1, sp - 1)).to_lower()
		var rest := "" if sp < 0 else line.substr(sp + 1).strip_edges()
		if not cmd in COMMANDS:
			out.errors.append("Comando desconocido: /%s" % cmd)
			continue
		var at := "target"
		if rest.begins_with("["):
			var close := rest.find("]")
			if close < 0:
				out.errors.append("Falta ]: %s" % line)
				continue
			var cond := rest.substr(1, close - 1).strip_edges().to_lower()
			rest = rest.substr(close + 1).strip_edges()
			if cond in ["@focus", "@foco"]:
				at = "focus"
			elif cond in ["@player", "@yo"]:
				at = "player"
			elif cond in ["@target", ""]:
				at = "target"
			else:
				out.errors.append("Condición desconocida: [%s]" % cond)
				continue
		var entry := {"cmd": cmd, "at": at, "slots": [], "arg": rest.to_lower()}
		if cmd in ["cast", "castsequence"]:
			var names := [rest] if cmd == "cast" else Array(rest.split(","))
			for n in names:
				var slot := slot_for(str(n).strip_edges(), cls, spec)
				if slot < 0:
					out.errors.append("No conozco la habilidad \"%s\"" % str(n).strip_edges())
				else:
					entry.slots.append(slot)
			if entry.slots.is_empty():
				continue
		out.lines.append(entry)
	return out


## Ability slot from its name (any case, accents optional), its id, or its key ("1", "2", "Q"...). -1 if unknown.
static func slot_for(name: String, cls: String, spec := "") -> int:
	var want := _fold(name)
	if want == "":
		return -1
	var keys: Array = GameData.C.SLOT_KEYS
	for i in keys.size():
		if _fold(str(keys[i])) == want:
			return i
	var abilities: Array = GameData.abilities(cls, spec)
	for i in abilities.size():
		if _fold(str(abilities[i].name)) == want or _fold(str(abilities[i].id)) == want:
			return i
	return -1


static func _fold(s: String) -> String:
	var t := s.strip_edges().to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		t = t.replace(pair[0], pair[1])
	return t


## The key a macro is bound to, as Godot spells it ("Ctrl+1"), from a key event.
static func key_name(event: InputEventKey) -> String:
	return OS.get_keycode_string(event.get_keycode_with_modifiers())
