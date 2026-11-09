class_name ProgressStore
extends RefCounted
## The player's champion levels ({cls: {level, xp}}), their talent picks ({Talents.key: [row picks]}) and the day of
## their last win, saved in user://progress.json (VERSION 2 added the talents; a version 1 file loads as is).
## Local for now: where progress lives for good (Steam, host validation) is still an open decision in
## docs/progresion-talentos-sinergias.md.

const PATH := "user://progress.json"
const VERSION := 2

static var _shared: ProgressStore = null

var path := PATH
var champions := {}  # cls -> {level, xp}
var last_win_day := ""  # "YYYY-MM-DD"
var picks := {}  # Talents.key(cls, spec) -> [one pick per row, -1 = none]


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
	picks = {}
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
	var tp = parsed.get("talents", {})
	if typeof(tp) == TYPE_DICTIONARY:
		for k in tp:
			var parts := str(k).split("/")
			var cls := parts[0]
			var spec := parts[1] if parts.size() > 1 else ""
			if GameData.classes.has(cls) and Talents.key(cls, spec) == str(k):
				picks[str(k)] = Talents.sanitize(cls, spec, tp[k])


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"_v": VERSION, "champions": champions, "last_win_day": last_win_day, "talents": picks}))


## {level, xp} of a champion (level 1 when never played).
func champion(cls: String) -> Dictionary:
	return champions.get(cls, {"level": 1, "xp": 0}).duplicate()


func level(cls: String) -> int:
	return int(champion(cls).level)


## Talent picks of a kit, with the rows its level has not unlocked yet left out (-1).
func talents(cls: String, spec := "") -> Array:
	GameData.ensure_loaded()
	if not GameData.classes.has(cls):
		return Talents.normalize(cls, spec, [])
	return Talents.normalize(cls, spec, picks.get(Talents.key(cls, spec), []), Progress.talent_rows(level(cls)))


## Picks choice `i` of `row` for the kit and saves (-1 clears it). False when the row is locked or `i` is not a choice.
func set_talent(cls: String, spec: String, row: int, i: int) -> bool:
	GameData.ensure_loaded()
	if not GameData.classes.has(cls) or row < 0 or row >= mini(Talents.ROWS, Progress.talent_rows(level(cls))):
		return false
	if i >= 0 and Talents.talent(cls, spec, row, i).is_empty():
		return false
	var k := Talents.key(cls, spec)
	var cur := Talents.sanitize(cls, spec, picks.get(k, []))
	cur[row] = i
	picks[k] = cur
	save()
	return true


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
