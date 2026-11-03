class_name TournamentStore
extends RefCounted
## Tournament progress saved in user://tournament.json: the cups won per mode and tier (they unlock the next tier of that
## mode), the consecutive-loss streak per mode and tier (it lowers the next rival's skill, see Tournament.effective_skill)
## and the run in progress. The file is written to a temp file and renamed, so a crash never leaves it half written.
## A match is marked pending when it starts: closing or crashing leaves it pending and begin_match() hands out the very
## same match again, with no penalty. Only report() and forfeit() count as a result.

const PATH := "user://tournament.json"

var path := PATH
var won := {}      # "mode:tier" -> cups won
var streaks := {}  # "mode:tier" -> consecutive losses
var run := {}      # the current (or last finished) run, {} when none


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


static func key(mode: int, tier_id: String) -> String:
	return "%d:%s" % [mode, tier_id]


func load_file() -> void:
	won = {}
	streaks = {}
	run = {}
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for mode in [1, 2, 3]:
		for t in Tournament.tier_ids():
			var k := key(mode, t)
			var w := int(parsed.get("won", {}).get(k, 0))
			if w > 0:
				won[k] = w
			var s := int(parsed.get("streaks", {}).get(k, 0))
			if s > 0:
				streaks[k] = s
	if typeof(parsed.get("run")) == TYPE_DICTIONARY and _valid_run(parsed.run):
		run = parsed.run


static func _valid_run(r: Dictionary) -> bool:
	return r.has_all(["mode", "tier", "seed", "player", "seat", "bracket", "round", "rounds", "status"]) and typeof(r.bracket) == TYPE_ARRAY and (r.bracket as Array).size() == 8 and Tournament.tier_ids().has(str(r.tier)) and int(r.mode) in [1, 2, 3] and int(r.round) in [0, 1, 2]


func save() -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": 1, "won": won, "streaks": streaks, "run": run}))
	f.close()
	var from := ProjectSettings.globalize_path(tmp)
	var to := ProjectSettings.globalize_path(path)
	if DirAccess.rename_absolute(from, to) != OK:  # some platforms refuse to replace an existing file
		DirAccess.remove_absolute(to)
		DirAccess.rename_absolute(from, to)


func cups(mode: int, tier_id: String) -> int:
	return int(won.get(key(mode, tier_id), 0))


func streak(mode: int, tier_id: String) -> int:
	return int(streaks.get(key(mode, tier_id), 0))


## Bronze is always open; every other tier opens when the previous one of the same mode has a cup.
func is_unlocked(mode: int, tier_id: String) -> bool:
	var i := Tournament.tier_index(tier_id)
	if i < 0:
		return false
	return i == 0 or cups(mode, Tournament.tier_ids()[i - 1]) > 0


func has_active_run() -> bool:
	return not run.is_empty() and Tournament.is_active(run)


func has_pending() -> bool:
	return has_active_run() and not (run.pending as Dictionary).is_empty()


## Starts a new run (replacing any unfinished one without penalty). False when the tier is still locked.
func start_run(mode: int, tier_id: String, player: Dictionary, seed_value: int) -> bool:
	if not is_unlocked(mode, tier_id):
		return false
	run = Tournament.new_run(mode, tier_id, player, seed_value)
	save()
	return true


## The match to play now. The first call marks it pending (and saves); calling again, or after a restart, returns the same one.
func begin_match() -> Dictionary:
	if not has_active_run():
		return {}
	var mode := int(run.mode)
	var tier_id := str(run.tier)
	if (run.pending as Dictionary).is_empty():
		run.pending = {"streak": streak(mode, tier_id)}
		save()
	return Tournament.next_match(run, int(run.pending.get("streak", 0)))


## Result of the pending match. Updates unlocks and the loss streak, and saves.
func report(player_won: bool) -> Dictionary:
	if not has_active_run():
		return {}
	var mode := int(run.mode)
	var tier_id := str(run.tier)
	var k := key(mode, tier_id)
	var res := Tournament.report(run, player_won)
	if player_won:
		streaks.erase(k)
	else:
		streaks[k] = streak(mode, tier_id) + 1
	if str(run.status) == "won":
		won[k] = cups(mode, tier_id) + 1
	save()
	return res


## Giving up counts as a defeat.
func forfeit() -> Dictionary:
	return report(false)


func clear_run() -> void:
	run = {}
	save()
