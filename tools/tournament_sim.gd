extends SceneTree
## Headless tournament calibration with a bot standing in for the player.
##   godot --headless --path . --script res://tools/tournament_sim.gd -- --n=10 --modes=1,2,3 --tiers=bronze,silver,gold,gladiator --player=normal --player-skill=0.55 --seed=1
## For every mode x tier x round it plays `n` real scripted matches (the exact ones Tournament.next_match builds, with the
## tier's rival skill, HP and damage) and counts the proxy player's wins. The player's class cycles through the playable
## classes; allies and rivals come from the tournament data. Output: one `RESULT {json}` line:
## {"cells": {"mode|tier|round": {n, wins, unfinished, total_s, fight_s}}, "player_skill", "n"}.
## A bot is a rough stand-in for a human (no kiting, no coordination): read the numbers as a relative scale, not as what a
## person will win.

const STEP := 1000.0 / 60.0
const LIMIT_MS := 12.0 * 60000.0


func _init() -> void:
	GameData.ensure_loaded()
	var args := {"n": "10", "modes": "1,2,3", "tiers": "bronze,silver,gold,gladiator", "player": "normal", "player-skill": "0.55", "seed": "1"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var classes: Array = GameData.playable_ids()
	var cells := {}
	var n := int(args.n)
	for mode_s in str(args.modes).split(","):
		var mode := int(mode_s)
		for tier_id in str(args.tiers).split(","):
			for r in Tournament.ROUNDS:
				var cell := {"n": 0, "wins": 0, "unfinished": 0, "total_s": 0.0, "fight_s": 0.0}
				for i in n:
					var seed_value := int(args.seed) * 100003 + mode * 10007 + Tournament.tier_index(tier_id) * 1009 + r * 101 + i
					var player_cls: String = classes[(i + r) % classes.size()]
					var run := Tournament.new_run(mode, tier_id, {"name": "Proxy", "cls": player_cls, "spec": ""}, seed_value)
					for k in r:  # get to round r without playing the earlier ones
						Tournament.report(run, true)
					var m := Tournament.next_match(run)
					var script: Array = m.scripted
					script[0]["diff"] = str(args.player)
					script[0]["skill"] = float(args["player-skill"])
					var entries := MatchConfig.scripted_entries(script, [])
					var won := _play(mode, entries, m.map, str(args.player), cell)
					cell.n += 1
					if won == 1:
						cell.wins += 1
				cells["%d|%s|%d" % [mode, tier_id, r]] = cell
	print("RESULT ", JSON.stringify({"cells": cells, "player_skill": float(args["player-skill"]), "n": n}))
	quit()


## 1 when the player's team (red) wins, 0 when it loses, -1 when nobody finished within the limit.
func _play(mode: int, entries: Array, map_id: String, diff: String, cell: Dictionary) -> int:
	var start := 1_000_000.0
	var now := start
	var match_ := ArenaMatch.new(mode, entries, now, diff, map_id)
	var fight_ticks := 0
	while not match_.done and match_.phase != "over" and now < start + LIMIT_MS:
		now += STEP
		match_.tick(now)
		if match_.phase == "fight":
			fight_ticks += 1
	if match_.phase != "over" and not match_.done:
		cell.unfinished += 1
		return -1
	cell.total_s += (now - start) / 1000.0
	cell.fight_s += fight_ticks * STEP / 1000.0
	return 1 if match_.score.red > match_.score.blue else 0
