class_name LessonScenarios
extends RefCounted
## What each Academia lesson puts in the arena. Only the local host reads this: the client hears about doors and plates through
## the snapshot and about units through the roster.
##
## A scenario: {id, start: [x, z], doors: mask, active: [plate...], damp: bool, units: [...], triggers: [...]}.
## Plate numbers: room * 4 + 0 left, 1 right, 2 near the exit, 3 near the entrance (GameMap._build_academy).
## Unit kinds (all need key, x, z; `dormant` makes them wait for a ["spawn", key]):
##   crate   breaks for good; `hp`
##   target  a training dummy that never breaks; cls, name
##   actor   a real fighter with no AI, driven by its `script`; cls, spec, name, hp_mult
##   bot     a real fighter with the normal AI; cls, spec, name, skill, diff, hp_mult, dmg_mult
## Triggers (see LessonStage): {on: "plate:N" | "dead:key" | "dead:prefix*" | "cue:N" | "start", do: [[action, args...]...]}.

const SCENARIOS := {
	"move_1": {
		"id": "move_1",
		"start": [0.0, 48.0],
		"doors": 0,
		"active": [0],
		"units": [],
		"triggers": [
			{"on": "cue:1", "do": [["activate", 1]]},
			{"on": "cue:2", "do": [["activate", 2]]},
			{"on": "cue:3", "do": [["open", 0], ["activate", 7]]},
		],
	},
}


static func scenario(id: String) -> Dictionary:
	return SCENARIOS.get(id, {})


## Entries for ArenaMatch: the player first, then every unit of the scenario.
static func entries(sc: Dictionary, player_name: String, cls: String, spec := "", peer := 1, talents: Array = []) -> Array:
	var out: Array = [{"name": player_name, "cls": cls, "spec": spec, "talents": talents, "team": "red", "peer": peer}]
	for u in sc.get("units", []):
		var e := {"lesson_key": str(u.key), "x": float(u.x), "z": float(u.z), "team": str(u.get("team", "blue")), "peer": 0, "name": str(u.get("name", "Caja"))}
		match str(u.kind):
			"crate":
				e.merge({"cls": "mage", "spec": "fire", "dummy": "crate", "hp": float(u.get("hp", 30.0)), "mortal": true})
			"target":
				e.merge({"cls": str(u.get("cls", "warrior")), "spec": str(u.get("spec", "")), "dummy": "target", "hp": PracticeYard.HP})
			"actor":
				e.merge({"cls": str(u.cls), "spec": str(u.get("spec", "")), "no_brain": true, "mortal": true, "hp_mult": float(u.get("hp_mult", 1.0)), "dmg_mult": float(u.get("dmg_mult", 1.0))})
			"bot":
				e.merge({"cls": str(u.cls), "spec": str(u.get("spec", "")), "mortal": true, "diff": str(u.get("diff", "easy")), "skill": float(u.get("skill", 0.2)), "hp_mult": float(u.get("hp_mult", 1.0)), "dmg_mult": float(u.get("dmg_mult", 1.0))})
		out.append(e)
	return out
