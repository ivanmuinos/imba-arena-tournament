class_name RankedStore
extends RefCounted
## The player's own ranked numbers per bracket ({mmr, games, wins}), saved in user://ranked.json and mirrored to the
## Steam leaderboards by RankedService. A ranked match is written down as a loss when it starts and replaced by the real
## result when it ends: quitting or disconnecting mid-match counts as a loss.

const PATH := "user://ranked.json"

var path := PATH
var data := {}  # "2v2" -> {mmr, games, wins}
var pending := {}  # {bracket, loss_delta, team, foe}: the match in progress


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


func load_file() -> void:
	data = {}
	pending = {}
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for mode in Ranked.BRACKETS:
		var key := Ranked.bracket_key(mode)
		var r = parsed.get("ratings", {}).get(key)
		if typeof(r) == TYPE_DICTIONARY:
			data[key] = {"mmr": Ranked.clamp_mmr(int(r.get("mmr", Ranked.START))), "games": maxi(int(r.get("games", 0)), 0), "wins": maxi(int(r.get("wins", 0)), 0)}
	if typeof(parsed.get("pending")) == TYPE_DICTIONARY:
		pending = parsed.pending


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"ratings": data, "pending": pending}))


func rating(mode: int) -> Dictionary:
	return data.get(Ranked.bracket_key(mode), {"mmr": Ranked.START, "games": 0, "wins": 0}).duplicate()


## Takes a rating from elsewhere (Steam) when it has seen more matches than ours.
func merge(mode: int, r: Dictionary) -> bool:
	if int(r.get("games", 0)) <= int(rating(mode).games):
		return false
	data[Ranked.bracket_key(mode)] = {"mmr": Ranked.clamp_mmr(int(r.mmr)), "games": int(r.games), "wins": int(r.get("wins", 0))}
	save()
	return true


## A ranked match started: from now on leaving counts as a loss.
func begin(mode: int, team_avg: float, foe_avg: float) -> void:
	var r := rating(mode)
	pending = {"bracket": mode, "team": team_avg, "foe": foe_avg, "loss": Ranked.delta(team_avg, foe_avg, false, int(r.games))}
	save()


## The match ended: applies the result. Returns {mode, delta, before, after, games, league_before, league_after}.
func finish(won: bool) -> Dictionary:
	if pending.is_empty():
		return {}
	var mode := int(pending.bracket)
	var r := rating(mode)
	var d := Ranked.delta(float(pending.team), float(pending.foe), won, int(r.games))
	pending = {}
	return _apply(mode, r, d, won)


## A match that was never finished (the game closed or the connection dropped): it is a loss.
func settle_abandoned() -> Dictionary:
	if pending.is_empty():
		return {}
	var mode := int(pending.bracket)
	var d := int(pending.loss)
	pending = {}
	return _apply(mode, rating(mode), d, false)


func _apply(mode: int, r: Dictionary, d: int, won: bool) -> Dictionary:
	var before := int(r.mmr)
	var lb := Ranked.league(before, int(r.games))
	r.mmr = Ranked.clamp_mmr(before + d)
	r.games = int(r.games) + 1
	r.wins = int(r.wins) + (1 if won else 0)
	data[Ranked.bracket_key(mode)] = r
	save()
	return {"mode": mode, "delta": int(r.mmr) - before, "before": before, "after": int(r.mmr), "games": r.games, "wins": r.wins,
		"won": won, "league_before": lb, "league_after": Ranked.league(int(r.mmr), int(r.games))}
