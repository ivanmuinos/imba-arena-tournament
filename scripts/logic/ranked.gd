class_name Ranked
extends RefCounted
## Ranked rules, no I/O: rating per bracket (1v1, 2v2, 3v3), Elo between team averages, WoW-style leagues after a few
## placement matches, and the fairest team split for a full ranked lobby. RankedService keeps and syncs the numbers.

const BRACKETS := [1, 2, 3]
const START := 1500
const MIN_MMR := 0
const MAX_MMR := 5000
## The first matches move the rating a lot so a new player lands where they belong quickly.
const PLACEMENT := 5
const K_PLACEMENT := 48.0
const K := 24.0
## A ranked lobby only takes players within this much of its host's rating at first, widening the longer it waits.
const SEARCH_WINDOW := 200
const SEARCH_WIDEN_PER_S := 10.0
const SEARCH_WINDOW_MAX := 800

## [min rating, id, name, colour]; the highest one at or under the rating applies.
const LEAGUES := [
	[0, "bronze", "Bronce", "#b07a4a"],
	[1350, "silver", "Plata", "#c4ccd6"],
	[1550, "gold", "Oro", "#ffc94a"],
	[1750, "platinum", "Platino", "#5fe0c8"],
	[1950, "diamond", "Diamante", "#7fb8ff"],
	[2150, "gladiator", "Gladiador", "#ff7a3a"],
]


static func bracket_key(mode: int) -> String:
	return "%dv%d" % [mode, mode]


## Chance that a team rated `a` beats a team rated `b`.
static func expected(a: float, b: float) -> float:
	return 1.0 / (1.0 + pow(10.0, (b - a) / 400.0))


## Rating change for one player: their team's average against the other's. `games` already played in this bracket.
static func delta(my_team: float, their_team: float, won: bool, games: int) -> int:
	var k := K_PLACEMENT if games < PLACEMENT else K
	var d := roundi(k * ((1.0 if won else 0.0) - expected(my_team, their_team)))
	if d == 0:
		d = 1 if won else -1  # a match always counts for something
	return d


static func clamp_mmr(v: int) -> int:
	return clampi(v, MIN_MMR, MAX_MMR)


static func placed(games: int) -> bool:
	return games >= PLACEMENT


## {id, name, color} of a rating, or the placement state ("Calibrando 2/5") before the placement matches are done.
static func league(mmr: int, games: int) -> Dictionary:
	if not placed(games):
		return {"id": "placement", "name": "Calibrando %d/%d" % [games, PLACEMENT], "color": "#a99c8f"}
	var best: Array = LEAGUES[0]
	for l in LEAGUES:
		if mmr >= int(l[0]):
			best = l
	return {"id": best[1], "name": best[2], "color": best[3]}


## Rating gap a waiting lobby accepts after `waited_s` seconds.
static func window(waited_s: float) -> int:
	return mini(SEARCH_WINDOW + int(waited_s * SEARCH_WIDEN_PER_S), SEARCH_WINDOW_MAX)


static func average(list: Array) -> float:
	if list.is_empty():
		return float(START)
	var t := 0.0
	for v in list:
		t += float(v)
	return t / list.size()


## Splits 2·mode players {peer, mmr} into red and blue with the closest team averages (exhaustive: at most 6 players).
## Returns {peer: "red"|"blue"}.
static func split_teams(players: Array, mode: int) -> Dictionary:
	var n := players.size()
	var best_mask := 0
	var best_gap := INF
	for mask in range(1 << n):
		if _bits(mask) != mode:
			continue
		if (mask & 1) == 0:  # mirror splits are the same split: keep the first player on red
			continue
		var red: Array = []
		var blue: Array = []
		for i in n:
			(red if (mask >> i) & 1 else blue).append(int(players[i].mmr))
		var gap := absf(average(red) - average(blue))
		if gap < best_gap:
			best_gap = gap
			best_mask = mask
	var out := {}
	for i in n:
		out[players[i].peer] = "red" if (best_mask >> i) & 1 else "blue"
	return out


static func _bits(v: int) -> int:
	var c := 0
	while v != 0:
		c += v & 1
		v >>= 1
	return c
