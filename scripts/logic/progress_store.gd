class_name ProgressStore
extends RefCounted
## The player's champion levels ({cls: {level, xp}}) and the day of their last win, saved in user://progress.json.
## Local for now: where progress lives for good (Steam, host validation) is still an open decision in
## docs/progresion-talentos-sinergias.md.

const PATH := "user://progress.json"

static var _shared: ProgressStore = null

var path := PATH
var champions := {}  # cls -> {level, xp}
var last_win_day := ""  # "YYYY-MM-DD"


static func shared() -> ProgressStore:
	if _shared == null:
		_shared = ProgressStore.new()
	return _shared


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


func load_file() -> void:
	GameData.ensure_loaded()
	champions = {}
	last_win_day = ""
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var ch = parsed.get("champions", {})
	if typeof(ch) == TYPE_DICTIONARY:
		for cls in ch:
			if typeof(ch[cls]) == TYPE_DICTIONARY and GameData.classes.has(str(cls)):
				champions[str(cls)] = Progress.add_xp(ch[cls], 0)  # clamps hand-edited values back into range
	last_win_day = str(parsed.get("last_win_day", ""))


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"champions": champions, "last_win_day": last_win_day}))


## {level, xp} of a champion (level 1 when never played).
func champion(cls: String) -> Dictionary:
	return champions.get(cls, {"level": 1, "xp": 0}).duplicate()


func level(cls: String) -> int:
	return int(champion(cls).level)


## A match ended: gives the champion its XP and saves. `today` = "YYYY-MM-DD".
## Returns {cls, gain, level_before, level_after, xp, xp_next, first_win} for the end screen.
func award(cls: String, won: bool, dmg: float, heal: float, vs_bots: bool, today: String) -> Dictionary:
	GameData.ensure_loaded()
	if not GameData.classes.has(cls):
		return {}
	var first_win := won and last_win_day != today
	var gain := Progress.match_xp(won, dmg, heal, first_win, vs_bots)
	var before := champion(cls)
	var after := Progress.add_xp(before, gain)
	champions[cls] = after
	if won:
		last_win_day = today
	save()
	return {"cls": cls, "gain": gain, "level_before": int(before.level), "level_after": int(after.level), "xp": int(after.xp),
		"xp_next": Progress.xp_to_next(int(after.level)), "first_win": first_win, "vs_bots": vs_bots}
