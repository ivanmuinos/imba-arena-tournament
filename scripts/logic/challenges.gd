class_name Challenges
extends RefCounted
## The 18 class challenges (data/challenges.json) and the cosmetic rewards (data/rewards.json). Challenges only read what the
## end-of-match message already carries (dmg, kills, deaths, heal of your unit, plus who won), so no ability needs its own code.
## Two kinds: "total" (a stat summed over matches played with the class, or the number of matches / wins) and "match"
## (one match meeting every condition of `when`: win, deaths_max, dmg_min, kills_min, heal_min).

const CHALLENGES_PATH := "res://data/challenges.json"
const REWARDS_PATH := "res://data/rewards.json"

static var _challenges: Array = []
static var _rewards := {}
static var _items := {}


static func all() -> Array:
	if _challenges.is_empty():
		_challenges = JSON.parse_string(FileAccess.get_file_as_string(CHALLENGES_PATH)).challenges
	return _challenges


static func rewards_data() -> Dictionary:
	if _rewards.is_empty():
		_rewards = JSON.parse_string(FileAccess.get_file_as_string(REWARDS_PATH))
		for it in _rewards.items:
			_items[str(it.id)] = it
	return _rewards


static func items() -> Array:
	return rewards_data().items


## Reward item by id ({} when unknown).
static func item(id: String) -> Dictionary:
	rewards_data()
	return _items.get(id, {})


static func get_challenge(id: String) -> Dictionary:
	for c in all():
		if c.id == id:
			return c
	return {}


static func for_class(cls: String) -> Array:
	return all().filter(func(c): return c.cls == cls)


## Does one finished match (your unit's cleaned stats) satisfy a "match" challenge?
static func match_ok(c: Dictionary, won: bool, st: Dictionary) -> bool:
	var w: Dictionary = c.when
	if w.get("win", false) and not won:
		return false
	if w.has("deaths_max") and int(st.deaths) > int(w.deaths_max):
		return false
	if w.has("dmg_min") and int(st.dmg) < int(w.dmg_min):
		return false
	if w.has("kills_min") and int(st.kills) < int(w.kills_min):
		return false
	if w.has("heal_min") and int(st.heal) < int(w.heal_min):
		return false
	return true


## Progress of a "total" challenge after one match.
static func total_gain(c: Dictionary, won: bool, st: Dictionary) -> int:
	match str(c.stat):
		"matches":
			return 1
		"wins":
			return 1 if won else 0
		"dmg", "kills", "heal":
			return int(st[str(c.stat)])
	return 0


## Updates `state` ({id: {progress, done}}) with one match played with `cls` and returns the challenges just completed.
static func apply(state: Dictionary, cls: String, won: bool, st: Dictionary) -> Array:
	var completed: Array = []
	for c in for_class(cls):
		var s: Dictionary = state.get(c.id, {"progress": 0, "done": false})
		if s.done:
			continue
		if c.kind == "total":
			s["progress"] = mini(int(s.progress) + total_gain(c, won, st), int(c.goal))
			s["done"] = int(s.progress) >= int(c.goal)
		elif match_ok(c, won, st):
			s["progress"] = 1
			s["done"] = true
		state[c.id] = s
		if s.done:
			completed.append(c.id)
	return completed
