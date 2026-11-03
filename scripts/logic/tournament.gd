class_name Tournament
extends RefCounted
## Tournament rules (pure logic, no I/O): an 8-team single-elimination cup (quarters, semifinal, final), 3 modes x 4 tiers
## (data/tournament.json). A run is a plain Dictionary so it can be saved as JSON:
## {v, mode, tier, seed, player, seat, bracket, round, rounds, rematches_left, status, history, pending}.
## `rounds[r]` holds the winning seat of every match of round r (-1 = not played yet). Only the player's matches are
## really played; the others are rolled, seeded, and only shown. The tier's boss always wins its displayed matches, so
## it is the final (it sits in the half of the bracket opposite the player).

const DATA_PATH := "res://data/tournament.json"
const ROUNDS := 3
const PLAYER_ID := "player"
const MAX_NAME := 16

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return _data


static func tiers() -> Array:
	return data().tiers


static func tier_ids() -> Array:
	return tiers().map(func(t): return t.id)


static func tier(id: String) -> Dictionary:
	for t in tiers():
		if t.id == id:
			return t
	return tiers()[0]


## Index of a tier in the unlock order (-1 when unknown).
static func tier_index(id: String) -> int:
	return tier_ids().find(id)


static func teams(mode: int) -> Array:
	return data().modes[str(clampi(mode, 1, 3))].teams


## Skill of the rival in a round: the tier's table minus `streak` consecutive losses x streak_cut, never below the tier's
## floor (its quarterfinal skill). Tiers without streak_cut (Oro, Gladiador) never go down.
static func effective_skill(t: Dictionary, round_n: int, streak: int) -> float:
	var table: Array = t.skill
	var base := float(table[clampi(round_n, 0, table.size() - 1)])
	var cut := float(t.get("streak_cut", 0.0))
	if cut <= 0.0 or streak <= 0:
		return base
	return snappedf(maxf(float(table[0]), base - cut * streak), 0.0001)


static func new_run(mode: int, tier_id: String, player: Dictionary, seed_value: int) -> Dictionary:
	var m := clampi(mode, 1, 3)
	var t := tier(tier_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var all: Array = teams(m)
	var boss: Dictionary = all.filter(func(x): return x.get("boss", "") == t.id)[0]
	var regular: Array = all.filter(func(x): return not x.has("boss"))
	_shuffle(regular, rng)
	var seat := rng.randi() % 8
	var boss_seat := (4 if seat < 4 else 0) + rng.randi() % 4
	var me := {"id": PLAYER_ID, "name": str(player.get("name", "")), "members": [{"name": str(player.get("name", "")), "cls": str(player.get("cls", "mage")), "spec": str(player.get("spec", ""))}]}
	var bracket: Array = []
	var next := 0
	for i in 8:
		if i == seat:
			bracket.append(me)
		elif i == boss_seat:
			bracket.append(boss)
		else:
			bracket.append(regular[next])
			next += 1
	return {
		"v": 1, "mode": m, "tier": t.id, "seed": seed_value,
		"player": {"name": str(player.get("name", "")), "cls": str(player.get("cls", "mage")), "spec": str(player.get("spec", ""))},
		"seat": seat, "bracket": bracket, "round": 0,
		"rounds": [[-1, -1, -1, -1], [-1, -1], [-1]],
		"rematches_left": int(t.rematches), "status": "active", "history": [], "pending": {},
	}


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


static func is_active(run: Dictionary) -> bool:
	return str(run.get("status", "")) == "active"


## Seats still playing round r (all 8 in the first one).
static func participants(run: Dictionary, r: int) -> Array:
	if r == 0:
		return [0, 1, 2, 3, 4, 5, 6, 7]
	return (run.rounds[r - 1] as Array).map(func(s): return int(s))


static func opponent_seat(run: Dictionary, r: int) -> int:
	var pos := int(run.seat) >> r
	return int(participants(run, r)[pos ^ 1])


## Everything the shell needs to play the current match: round, rival, effective skill, arena and the `scripted` list
## for GameServer cfg.scripted. Deterministic for a given run state and streak, so a resumed match is the same one.
static func next_match(run: Dictionary, streak := 0) -> Dictionary:
	var r := int(run.round)
	var t := tier(str(run.tier))
	var opp: Dictionary = run.bracket[opponent_seat(run, r)]
	var skill := effective_skill(t, r, streak)
	var mode := int(run.mode)
	var script: Array = [{"human": true, "team": "red", "name": run.player.name, "cls": run.player.cls, "spec": run.player.spec}]
	var allies: Array = data().allies.get(str(run.player.cls), ["priest", "warrior"])
	var ally_names: Array = data().ally_names
	for i in mode - 1:
		script.append({"name": ally_names[(int(run.seed) + i * 5 + r) % ally_names.size()], "cls": allies[i % allies.size()], "spec": "", "team": "red", "diff": t.ally_diff})
	for mem in opp.members:
		script.append({"name": mem.name, "cls": mem.cls, "spec": str(mem.get("spec", "")), "team": "blue", "diff": t.diff, "skill": skill, "hp_mult": float(t.hp_mult), "dmg_mult": float(t.dmg_mult)})
	_unique_names(script, str(run.player.name))
	return {
		"round": r, "round_name": data().rounds[r], "tier": t.id, "mode": mode, "opponent": opp,
		"boss": opp.get("boss", "") == t.id, "skill": skill, "hp_mult": float(t.hp_mult), "dmg_mult": float(t.dmg_mult),
		"rematches_left": int(run.rematches_left), "streak": streak,
		"map": GameMap.pick_id(int(run.seed) * 31 + r * 7 + (run.history as Array).size()),
		"scripted": script,
	}


## Bots never share a name with the player or each other: the later one gets " II", " III"...
static func _unique_names(script: Array, player_name: String) -> void:
	var used := {player_name.to_lower(): true}
	for e in script:
		if e.get("human", false):
			continue
		var base := str(e.name)
		var n := 1
		var name := base
		while used.has(name.to_lower()):
			n += 1
			var suffix := " " + "I".repeat(n)
			name = base.substr(0, MAX_NAME - suffix.length()) + suffix
		used[name.to_lower()] = true
		e["name"] = name


## Applies the result of the current match. Returns {status, round, won}. A loss with a free rematch left keeps the run
## on the same round (the same opponent, replayed); any other loss ends the run.
static func report(run: Dictionary, won: bool) -> Dictionary:
	if not is_active(run):
		return {"status": run.status, "round": int(run.round), "won": won}
	var r := int(run.round)
	var opp := opponent_seat(run, r)
	(run.history as Array).append({"round": r, "opponent": run.bracket[opp].id, "won": won})
	run.pending = {}
	if won:
		_resolve_round(run, r, true)
		if r >= ROUNDS - 1:
			run.status = "won"
		else:
			run.round = r + 1
	elif int(run.rematches_left) > 0:
		run.rematches_left = int(run.rematches_left) - 1
	else:
		_resolve_round(run, r, false)
		for later in range(r + 1, ROUNDS):
			_resolve_round(run, later, false, true)
		run.status = "lost"
	return {"status": run.status, "round": int(run.round), "won": won}


## Fills the winners of round r. The player's own match takes `player_won`; the rest are displayed rolls (seeded per
## match, so saving and reloading never changes them). With `no_player` every match is a roll.
static func _resolve_round(run: Dictionary, r: int, player_won: bool, no_player := false) -> void:
	var seats := participants(run, r)
	var mine := (int(run.seat) >> r) >> 1
	for m in seats.size() / 2:
		var a := int(seats[m * 2])
		var b := int(seats[m * 2 + 1])
		var winner := a
		if not no_player and m == mine:
			var me := int(run.seat)
			winner = me if player_won else (b if a == me else a)
		else:
			winner = _roll(run, r, m, a, b)
		run.rounds[r][m] = winner


static func _roll(run: Dictionary, r: int, m: int, a: int, b: int) -> int:
	var tier_id := str(run.tier)
	if run.bracket[a].get("boss", "") == tier_id:
		return a
	if run.bracket[b].get("boss", "") == tier_id:
		return b
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run.seed) * 1000 + r * 10 + m
	return a if rng.randf() < 0.5 else b
