class_name LessonScenarios
extends RefCounted
## What each Academia lesson puts in the arena. Only the local host reads this: the client hears about doors and plates through
## the snapshot and about units through the roster.
##
## `map`: "valley" plays it in the open valley instead of the hall of rooms.
## A scenario: {id, start: [x, z], doors: mask, active: [plate...], damp: bool, units: [...], triggers: [...]}.
## Plate numbers: room * 4 + 0 left, 1 right, 2 near the exit, 3 near the entrance (GameMap._build_academy).
## Unit kinds (all need key, x, z; `dormant` makes them wait for a ["spawn", key]):
##   crate   breaks for good; `hp`
##   target  a training dummy that never breaks; cls, name
##   ally    a dummy on the player's side, to heal and shield; cls, name, hp
##   actor   a real fighter with no AI, driven by its `script`; cls, spec, name, hp_mult
##   bot     a real fighter with the normal AI; cls, spec, name, skill, diff, hp_mult, dmg_mult
## Triggers (see LessonStage): {on: "plate:N" | "dead:key" | "dead:prefix*" | "cue:N" | "start", do: [[action, args...]...]}.
## A trigger with `again: true` fires every time (cues of quests that can be repeated).
## Actions: reset_plates [n...] (not active nor stepped on), open/close door, activate plate, spawn key, stun ms, ult, gem kind x z, nocd bool, cast key ability,
## note name (tells the lesson "note:name"), hurt key fraction.
## `fresh_dr`: its units never build diminishing returns (a lesson that needs many tries at one control).
## `watch`: [{hidden_from: key, ms, note}] tells the lesson once the player hid from that unit for that long.

const BIG := 30.0  # health multiplier of a unit nobody is meant to kill

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
	"cam_1": {
		"id": "cam_1", "start": [0.0, 45.0], "doors": 0, "active": [], "units": [],
		"triggers": [{"on": "cue:1", "do": [["activate", 3]]}],
	},
	"target_1": {
		"id": "target_1", "start": [0.0, 48.0], "doors": 0, "active": [],
		"units": [
			{"key": "c1", "kind": "crate", "x": -1.0, "z": 40.0, "hp": 45.0},
			{"key": "c2", "kind": "crate", "x": 4.0, "z": 41.0, "hp": 45.0},
			{"key": "c3", "kind": "crate", "x": 9.0, "z": 40.0, "hp": 45.0},
		],
		"triggers": [],
	},
	"skills_1": {
		"id": "skills_1", "start": [0.0, 48.0], "doors": 0, "active": [],
		"units": [{"key": "t1", "kind": "target", "cls": "warrior", "name": "Muñeco", "x": 0.0, "z": 41.0}],
		"triggers": [{"on": "cue:5", "do": [["ult"]]}],
	},
	"skills_1_ally": {
		"id": "skills_1_ally", "start": [0.0, 48.0], "doors": 0, "active": [],
		"units": [
			{"key": "t1", "kind": "target", "cls": "warrior", "name": "Muñeco", "x": 0.0, "z": 41.0},
			{"key": "a1", "kind": "ally", "cls": "warrior", "name": "Aliado herido", "x": 6.0, "z": 45.0, "hp": 600.0},
		],
		"triggers": [{"on": "start", "do": [["hurt", "a1", 0.4]]}, {"on": "cue:5", "do": [["ult"], ["hurt", "a1", 0.4]]}],
	},
	"cast_1": {
		"id": "cast_1", "start": [0.0, 48.0], "doors": 0, "active": [],
		"units": [
			{"key": "t1", "kind": "target", "cls": "warrior", "name": "Muñeco", "x": 0.0, "z": 41.0},
			{"key": "e1", "kind": "actor", "cls": "warrior", "name": "Pegador", "x": 8.0, "z": 40.0, "hp_mult": BIG, "dmg_mult": 0.2, "dormant": true, "script": [{"do": "chase_melee"}]},
		],
		"triggers": [{"on": "cue:1", "do": [["spawn", "e1"]]}],
	},
	"cast_2": {
		"id": "cast_2", "start": [0.0, 48.0], "doors": 0, "active": [],
		"units": [{"key": "e1", "kind": "actor", "cls": "mage", "spec": "fire", "name": "Hechicero", "x": 0.0, "z": 41.0, "hp_mult": BIG, "dmg_mult": 0.2, "dormant": true,
			"script": [{"do": "hold_position"}, {"do": "cast_loop", "ability": "pyro", "every": 2600.0}]}],
		"triggers": [{"on": "cue:1", "do": [["spawn", "e1"]]}],
	},
	"cc_1": {
		"id": "cc_1", "start": [0.0, 48.0], "doors": 0, "active": [],
		"units": [{"key": "e1", "kind": "actor", "cls": "warrior", "name": "Sparring", "x": 0.0, "z": 42.0, "hp_mult": BIG, "script": [{"do": "hold_position"}]}],
		"triggers": [{"on": "start", "do": [["nocd", true]]}],
	},
	"trinket_1": {
		"id": "trinket_1", "start": [0.0, 48.0], "doors": 0, "active": [],
		"units": [{"key": "t1", "kind": "target", "cls": "warrior", "name": "Muñeco", "x": 0.0, "z": 41.0}],
		"triggers": [{"on": "cue:1", "do": [["stun", 6000.0]]}],
	},
	"kick_1": {
		"id": "kick_1", "start": [0.0, 48.0], "doors": 0, "active": [], "fresh_dr": true,
		"units": [{"key": "e1", "kind": "actor", "cls": "mage", "spec": "fire", "name": "Hechicero", "x": 0.0, "z": 42.0, "hp_mult": BIG, "dmg_mult": 0.15, "dormant": true,
			"script": [{"do": "hold_position"}, {"do": "cast_loop", "ability": "pyro", "every": 2500.0}]}],
		"triggers": [{"on": "start", "do": [["nocd", true]]}, {"on": "cue:1", "do": [["spawn", "e1"]]}],
	},
	"los_1": {
		"id": "los_1", "start": [0.0, -6.0], "doors": 0, "active": [],
		"units": [{"key": "e1", "kind": "actor", "cls": "mage", "spec": "fire", "name": "Hechicero", "x": 0.0, "z": -15.5, "hp_mult": BIG, "dmg_mult": 0.6, "dormant": true,
			"script": [{"do": "hold_position"}, {"do": "cast_loop", "ability": "fireball", "every": 1600.0}]}],
		"watch": [{"hidden_from": "e1", "ms": 1200.0, "note": "hidden"}],
		"triggers": [{"on": "cue:1", "do": [["spawn", "e1"]]}],
	},
	"focus_1": {
		"id": "focus_1", "start": [0.0, 48.0], "doors": 0, "active": [],
		"units": [
			{"key": "e1", "kind": "actor", "cls": "priest", "name": "Sanador", "x": 1.0, "z": 41.0, "hp_mult": BIG, "script": [{"do": "hold_position"}]},
			{"key": "e2", "kind": "actor", "cls": "warrior", "name": "Guerrero", "x": 8.0, "z": 41.0, "hp_mult": BIG, "script": [{"do": "hold_position"}]},
		],
		"triggers": [],
	},
	"ground_1": {
		"id": "ground_1", "start": [0.0, -11.0], "doors": 8, "active": [18], "units": [],
		"triggers": [{"on": "cue:1", "do": [["gem", "haste", -10.0, -31.0]]}],
	},
	"valley_free": {
		"id": "valley_free", "map": "valley", "start": [0.0, 57.0], "doors": 0, "active": [],
		"units": [
			{"key": "t1", "kind": "target", "cls": "warrior", "name": "Muñeco", "x": -42.0, "z": 22.0},
			{"key": "t2", "kind": "target", "cls": "warrior", "name": "Muñeco", "x": -36.0, "z": 21.0},
			{"key": "t3", "kind": "target", "cls": "mage", "spec": "fire", "name": "Muñeco", "x": -39.0, "z": 31.0},
			{"key": "c1", "kind": "crate", "x": -32.0, "z": 28.0, "hp": 45.0},
			{"key": "c2", "kind": "crate", "x": -31.0, "z": 24.0, "hp": 45.0},
			{"key": "c3", "kind": "crate", "x": -45.0, "z": 28.0, "hp": 45.0},
		],
		# Cues of the valley's quests (AcademyValley). `again`: a quest can be repeated in the same visit.
		"triggers": [
			{"on": "cue:1", "again": true, "do": [["reset_plates", [7, 8, 9, 11]], ["activate", 7]]},
			{"on": "cue:2", "again": true, "do": [["activate", 8]]},
			{"on": "cue:3", "again": true, "do": [["activate", 9]]},
			{"on": "cue:4", "again": true, "do": [["activate", 11]]},
			{"on": "cue:5", "again": true, "do": [["reset_plates", [10]], ["activate", 10]]},
			{"on": "cue:6", "again": true, "do": [["reset_plates", [1]], ["activate", 1], ["spawn", "c1"], ["spawn", "c2"], ["spawn", "c3"]]},
		],
	},
	"duel_1": {
		"id": "duel_1", "start": [0.0, -42.5], "doors": 0, "active": [],
		"units": [{"key": "rival", "kind": "bot", "cls": "warrior", "name": "Brasa", "x": 0.0, "z": -51.5, "diff": "easy", "skill": 0.15, "hp_mult": 0.6, "dmg_mult": 0.6, "dormant": true}],
		"triggers": [{"on": "cue:1", "do": [["spawn", "rival"]]}, {"on": "dead:rival", "do": [["note", "won"]]}],
	},
}


static func scenario(id: String) -> Dictionary:
	return SCENARIOS.get(id, {})


## The map a scenario is played on.
static func map_of(sc: Dictionary) -> String:
	return GameMap.VALLEY_ID if str(sc.get("map", "")) == GameMap.VALLEY_ID else GameMap.ACADEMY_ID


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
			"ally":
				e.merge({"cls": str(u.get("cls", "warrior")), "spec": str(u.get("spec", "")), "dummy": "target", "hp": float(u.get("hp", 400.0)), "team": "red"}, true)
			"actor":
				e.merge({"cls": str(u.cls), "spec": str(u.get("spec", "")), "no_brain": true, "mortal": true, "hp_mult": float(u.get("hp_mult", 1.0)), "dmg_mult": float(u.get("dmg_mult", 1.0))})
			"bot":
				e.merge({"cls": str(u.cls), "spec": str(u.get("spec", "")), "mortal": true, "diff": str(u.get("diff", "easy")), "skill": float(u.get("skill", 0.2)), "hp_mult": float(u.get("hp_mult", 1.0)), "dmg_mult": float(u.get("dmg_mult", 1.0))})
		out.append(e)
	return out
