extends SceneTree
## Headless bot-vs-bot balance simulation.
##   godot --headless --path . --script res://tools/balance_sim.gd -- --n=200 --modes=2,3 --maps=bridge,pillars,tomb,living --seed=1 [--out=user://balance.json]
## Each match draws two random teams (classes with repetition) and plays out with bots on a map. Per class we count
## appearances and wins (a class on a team of 3 counts once per copy). Teams are randomised red/blue so spawn side is neutral.
## Output: JSON on stdout (last line) with overall, per-mode, per-map and 2v2 pairing tables.

const STEP := 1000.0 / 60.0


func _init() -> void:
	GameData.ensure_loaded()
	var args := {"n": "100", "modes": "2,3", "maps": "bridge,pillars,tomb,living", "seed": "1", "diff": "normal"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args.seed)
	var classes: Array = GameData.classes.keys()
	var stats := {}    # key -> [wins, games]
	var total_matches := 0
	var draws := 0
	var durations: Array = []   # fight time per match in seconds (prep and between-round pauses excluded)
	var n := int(args.n)
	if args.has("duel"):
		_duels(args, rng)
		return
	for mode_s in str(args.modes).split(","):
		var mode := int(mode_s)
		for map_id in str(args.maps).split(","):
			for i in n:
				var red: Array = []
				var blue: Array = []
				var rspec: Array = []
				var bspec: Array = []
				for k in mode:
					var rc: String = classes[rng.randi() % classes.size()]
					var bc: String = classes[rng.randi() % classes.size()]
					red.append(rc)
					blue.append(bc)
					var rs := GameData.spec_ids(rc)
					var bs := GameData.spec_ids(bc)
					rspec.append(rs[rng.randi() % rs.size()] if not rs.is_empty() else "")
					bspec.append(bs[rng.randi() % bs.size()] if not bs.is_empty() else "")
				var entries := []
				for k in mode:
					entries.append({"name": "r%d" % k, "cls": red[k], "spec": rspec[k], "team": "red"})
				for k in mode:
					entries.append({"name": "b%d" % k, "cls": blue[k], "spec": bspec[k], "team": "blue"})
				var now := 1_000_000.0
				var m := ArenaMatch.new(mode, entries, now, str(args.diff), map_id)
				var limit := now + 12 * 60_000
				while not m.done and now < limit:
					now += STEP
					m.tick(now)
				total_matches += 1
				durations.append((now - 1_000_000.0) / 1000.0 - 20.0 - 10.0 * float(m.round_n))
				var winner := ""
				if m.done:
					winner = "red" if m.score.red > m.score.blue else "blue"
				else:
					draws += 1
					if args.has("debug"):
						var d := []
						for u in m.units:
							d.append("%s/%s%s hp=%d alive=%s pos=(%.0f,%.0f) stun=%s" % [u.cls, u.spec_id, "" if u.brain != null else "(h)", u.hp, str(u.alive), u.x, u.z, str(now < u.stun_until)])
						print("STALL ", map_id, " round=", m.round_n, " score=", m.score, " ", d)
					continue
				for side in [["red", red], ["blue", blue]]:
					var won: bool = winner == side[0]
					var specs: Array = rspec if side[0] == "red" else bspec
					for ci in (side[1] as Array).size():
						var c: String = side[1][ci]
						var labels: Array = [c]
						if specs[ci] != "":
							labels.append("%s-%s" % [c, specs[ci]])
						for lab in labels:
							for key in ["all", "mode%d" % mode, "map_" + map_id]:
								_add(stats, "%s|%s" % [key, lab], won)
					if mode == 2:
						var pair: Array = (side[1] as Array).duplicate()
						pair.sort()
						_add(stats, "pair|%s+%s" % [pair[0], pair[1]], won)
	print("RESULT ", JSON.stringify({"matches": total_matches, "unfinished": draws, "stats": stats, "durations": durations}))
	quit()


func _add(stats: Dictionary, key: String, won: bool) -> void:
	var e: Array = stats.get(key, [0, 0])
	e[0] += 1 if won else 0
	e[1] += 1
	stats[key] = e


## 1v1 matchup matrix: every ordered pair of class/spec variants, `n` duels per map (best of 3 like a real match).
## RESULT JSON: {"duel": {"A|B": [wins of A, games]}, "ttk": {"A|B": [seconds until the first death, games]}}
func _duels(args: Dictionary, rng: RandomNumberGenerator) -> void:
	var variants: Array = []
	for c in GameData.classes:
		var sp := GameData.spec_ids(c)
		if sp.is_empty():
			variants.append([c, ""])
		else:
			for s in sp:
				variants.append([c, s])
	var duel := {}
	var ttk := {}
	for map_id in str(args.maps).split(","):
		for a in variants:
			for b in variants:
				for i in int(args.n):
					var swap := rng.randf() < 0.5
					var entries := [
						{"name": "A", "cls": a[0], "spec": a[1], "team": "blue" if swap else "red"},
						{"name": "B", "cls": b[0], "spec": b[1], "team": "red" if swap else "blue"}]
					var now := 1_000_000.0
					var m := ArenaMatch.new(2, entries, now, str(args.diff), map_id)
					var limit := now + 12 * 60_000
					var first := -1.0
					while not m.done and now < limit:
						now += STEP
						m.tick(now)
						if first < 0.0 and m.units.any(func(u): return not u.alive):
							first = (now - m.fight_start) / 1000.0
					if not m.done:
						continue
					var a_team: String = "blue" if swap else "red"
					var won: bool = (m.score.red > m.score.blue) == (a_team == "red")
					var key := "%s%s|%s%s" % [a[0], "-" + a[1] if a[1] != "" else "", b[0], "-" + b[1] if b[1] != "" else ""]
					_add(duel, key, won)
					var t: Array = ttk.get(key, [0.0, 0])
					t[0] += maxf(first, 0.0)
					t[1] += 1
					ttk[key] = t
	print("RESULT ", JSON.stringify({"duel": duel, "ttk": ttk}))
	quit()
