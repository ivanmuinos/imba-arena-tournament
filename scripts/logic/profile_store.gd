class_name ProfileStore
extends RefCounted
## The player's profile in user://profile.json: stats per class, cups, challenge progress, unlocked and equipped cosmetics
## and the account level. XP comes from every finished match against bots, in the tournament or online, more for wins;
## practice dummies give none. The level only unlocks rewards (one per level-up): it never takes part in matchmaking.
## The curve and the XP per match live in data/rewards.json. Everything read from disk is sanitized.

const PATH := "user://profile.json"
const STATS := ["matches", "wins", "losses", "dmg", "kills", "deaths", "heal"]
## Largest value one match may add to a stat (a tampered or buggy number never wrecks the totals).
const MATCH_CAP := 50000

var path := PATH
var xp := 0
var classes := {}      # cls -> {matches, wins, losses, dmg, kills, deaths, heal}
var cup_counts := {}   # "mode:tier" -> cups won
var challenges := {}   # challenge id -> {progress, done}
var unlocked: Array = []
var equipped := {"title": "", "ring": "", "recolor": {}}  # recolor: cls -> item id


func _init(p_path := PATH) -> void:
	path = p_path
	load_file()


# ---------------------------------------------------------------- level curve

static func max_level() -> int:
	return int(Challenges.rewards_data().curve.max_level)


## XP needed to go from `level` to the next one.
static func need_for(level: int) -> int:
	var c: Dictionary = Challenges.rewards_data().curve
	return mini(int(c.max_need), roundi(float(c.base) * pow(float(c.growth), level - 1)))


## Total XP at which `level` starts.
static func xp_to_reach(level: int) -> int:
	var total := 0
	for l in range(1, mini(level, max_level())):
		total += need_for(l)
	return total


static func level_for_xp(points: int) -> int:
	var level := 1
	var left := maxi(points, 0)
	while level < max_level() and left >= need_for(level):
		left -= need_for(level)
		level += 1
	return level


## XP of one finished match: `source` is "bot", "tournament" or "online" (anything else, practice included, gives none).
static func xp_for(source: String, won: bool) -> int:
	var table: Dictionary = Challenges.rewards_data().xp.get(source, {})
	return int(table.get("win" if won else "loss", 0))


## Item granted when reaching `level` ("" when there is none).
static func level_reward(level: int) -> String:
	return str(Challenges.rewards_data().level_rewards.get(str(level), ""))


func level() -> int:
	return level_for_xp(xp)


## {level, into (XP inside the level), need (XP the level asks, 0 at the top), maxed}.
func progress() -> Dictionary:
	var lv := level()
	var maxed := lv >= max_level()
	return {"level": lv, "into": xp - xp_to_reach(lv), "need": 0 if maxed else need_for(lv), "maxed": maxed}


# ---------------------------------------------------------------- persistence

func load_file() -> void:
	xp = 0
	classes = {}
	cup_counts = {}
	challenges = {}
	unlocked = []
	equipped = {"title": "", "ring": "", "recolor": {}}
	if not FileAccess.file_exists(path):
		return
	var p = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(p) != TYPE_DICTIONARY:
		return
	xp = maxi(int(p.get("xp", 0)), 0)
	var raw_classes = p.get("classes", {})
	if typeof(raw_classes) == TYPE_DICTIONARY:
		for cls in raw_classes:
			if GameData.playable(str(cls)) and typeof(raw_classes[cls]) == TYPE_DICTIONARY:
				var st := {}
				for k in STATS:
					st[k] = maxi(_num(raw_classes[cls].get(k, 0), 1 << 40), 0)
				classes[str(cls)] = st
	var raw_cups = p.get("cups", {})
	if typeof(raw_cups) == TYPE_DICTIONARY:
		for k in raw_cups:
			var parts := str(k).split(":")
			if parts.size() == 2 and parts[0] in ["1", "2", "3"] and Tournament.tier_ids().has(parts[1]) and int(raw_cups[k]) > 0:
				cup_counts[str(k)] = int(raw_cups[k])
	var raw_ch = p.get("challenges", {})
	if typeof(raw_ch) == TYPE_DICTIONARY:
		for id in raw_ch:
			var c := Challenges.get_challenge(str(id))
			if not c.is_empty() and typeof(raw_ch[id]) == TYPE_DICTIONARY:
				var goal: int = int(c.goal) if c.kind == "total" else 1
				var prog := clampi(int(raw_ch[id].get("progress", 0)), 0, goal)
				challenges[str(id)] = {"progress": prog, "done": bool(raw_ch[id].get("done", false)) and prog >= goal}
	var raw_unlocked = p.get("unlocked", [])
	if typeof(raw_unlocked) == TYPE_ARRAY:
		for id in raw_unlocked:
			if typeof(id) == TYPE_STRING and not Challenges.item(id).is_empty() and not unlocked.has(id):
				unlocked.append(id)
	var raw_eq = p.get("equipped", {})
	if typeof(raw_eq) == TYPE_DICTIONARY:
		for slot in ["title", "ring"]:
			var id := str(raw_eq.get(slot, ""))
			if _can_equip(slot, id):
				equipped[slot] = id
		var rec = raw_eq.get("recolor", {})
		if typeof(rec) == TYPE_DICTIONARY:
			for cls in rec:
				var id := str(rec[cls])
				if _can_equip("recolor", id) and str(Challenges.item(id).cls) == str(cls):
					equipped.recolor[str(cls)] = id


func save() -> void:
	AtomicFile.write_text(path, JSON.stringify({"v": 1, "xp": xp, "classes": classes, "cups": cup_counts, "challenges": challenges, "unlocked": unlocked, "equipped": equipped}))


static func _num(v, cap: int) -> int:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return 0
	return clampi(int(v), -cap, cap)


# ---------------------------------------------------------------- stats

func class_stats(cls: String) -> Dictionary:
	var out := {}
	for k in STATS:
		out[k] = int(classes.get(cls, {}).get(k, 0))
	return out


func cups(key: String) -> int:
	return int(cup_counts.get(key, 0))


func record_cup(mode: int, tier_id: String) -> void:
	var k := TournamentStore.key(mode, tier_id)
	cup_counts[k] = cups(k) + 1
	save()


func challenge_state(id: String) -> Dictionary:
	var s: Dictionary = challenges.get(id, {})
	return {"progress": int(s.get("progress", 0)), "done": bool(s.get("done", false))}


## One finished match of the local player. `stats` is their entry of the end message ({dmg, kills, deaths, heal}).
## Returns {xp, level_before, level_after, level_ups: [{level, reward}], completed: [challenge ids], rewards: [item ids]}.
## Practice (or an unknown source or class) changes nothing.
func record_match(source: String, cls: String, won: bool, stats: Dictionary, _mode := 0) -> Dictionary:
	var gained := xp_for(source, won)
	var out := {"xp": 0, "level_before": level(), "level_after": level(), "level_ups": [], "completed": [], "rewards": []}
	if gained <= 0 or not GameData.playable(cls):
		return out
	var st := {}
	for k in ["dmg", "kills", "deaths", "heal"]:
		st[k] = clampi(_num(stats.get(k, 0), MATCH_CAP), 0, MATCH_CAP)
	var cs := class_stats(cls)
	cs.matches += 1
	cs.wins += 1 if won else 0
	cs.losses += 0 if won else 1
	for k in ["dmg", "kills", "deaths", "heal"]:
		cs[k] += st[k]
	classes[cls] = cs
	for id in Challenges.apply(challenges, cls, won, st):
		out.completed.append(id)
		_unlock(str(Challenges.get_challenge(id).reward), out)
	var before := level()
	xp += gained
	var after := level()
	for lv in range(before + 1, after + 1):
		var reward := level_reward(lv)
		out.level_ups.append({"level": lv, "reward": reward})
		_unlock(reward, out)
	out.xp = gained
	out.level_after = after
	save()
	return out


func _unlock(id: String, out: Dictionary) -> void:
	if id == "" or Challenges.item(id).is_empty() or unlocked.has(id):
		return
	unlocked.append(id)
	out.rewards.append(id)


# ---------------------------------------------------------------- cosmetics

func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func _can_equip(slot: String, id: String) -> bool:
	var it := Challenges.item(id)
	return not it.is_empty() and str(it.kind) == slot and unlocked.has(id)


## Equips an unlocked item in its slot ("title", "ring" or "recolor", this last one per class).
func equip(slot: String, id: String) -> bool:
	if not _can_equip(slot, id):
		return false
	if slot == "recolor":
		equipped.recolor[str(Challenges.item(id).cls)] = id
	else:
		equipped[slot] = id
	save()
	return true


func unequip(slot: String, cls := "") -> bool:
	if slot == "recolor":
		if not equipped.recolor.has(cls):
			return false
		equipped.recolor.erase(cls)
	elif equipped.has(slot) and str(equipped[slot]) != "":
		equipped[slot] = ""
	else:
		return false
	save()
	return true
