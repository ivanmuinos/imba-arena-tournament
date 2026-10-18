class_name MatchConfig
extends RefCounted
## Menu/lobby settings -> sanitized config and the entries an ArenaMatch is built from
## (port of the matchmaking part of server/index.ts).

const BOT_NAMES := ["Ignis", "Ceniza", "Brasa", "Obsidiana", "Fénix", "Ascua", "Pómez", "Vulcano", "Azufre", "Escoria"]
const DIFFS := ["easy", "normal", "hard"]
const MAX_NAME := 16


static func sanitize_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c >= 32 and c != 127:
			out += raw[i]
	out = out.strip_edges().substr(0, MAX_NAME).strip_edges()
	return out if out != "" else "Aventurero"


static func class_ids() -> Array:
	GameData.ensure_loaded()
	return GameData.classes.keys()


## Anything the user/network can send, forced into valid values.
static func normalize(c: Dictionary) -> Dictionary:
	GameData.ensure_loaded()
	var cls := str(c.get("cls", "mage"))
	var diff := str(c.get("diff", "normal"))
	var map_id := str(c.get("map", "random"))
	var pref := str(c.get("pref", "any"))
	var cls_ok := cls if GameData.classes.has(cls) else "mage"
	return {
		"name": sanitize_name(str(c.get("name", ""))),
		"cls": cls_ok,
		"spec": GameData.normalize_spec(cls_ok, str(c.get("spec", ""))),
		"mode": 3 if int(c.get("mode", 2)) == 3 else 2,
		"diff": diff if DIFFS.has(diff) else "normal",
		"map": map_id if (GameData.maps.has(map_id) or map_id == "random" or map_id == "test") else "random",
		"pref": pref if pref in ["any", "red", "blue"] else "any",
	}


## humans: [{peer, name, cls, pref}]. Returns [{name, cls, team, peer}] with bots in the free slots.
static func build_entries(mode: int, humans: Array, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var teams := {"red": [], "blue": []}
	var other := func(t: String) -> String: return "blue" if t == "red" else "red"
	for h in humans:
		if h.pref != "any":
			var t: String = h.pref if teams[h.pref].size() < mode else other.call(h.pref)
			teams[t].append(h)
	# Players without a preference are split so humans face each other.
	for h in humans:
		if h.pref == "any":
			var t := "red" if teams.red.size() <= teams.blue.size() else "blue"
			if teams[t].size() >= mode:
				t = other.call(t)
			teams[t].append(h)
	var used: Array = humans.map(func(h): return h.name)
	var bots: Array = BOT_NAMES.filter(func(n): return not used.has(n))
	for i in range(bots.size() - 1, 0, -1):  # shuffle
		var j := rng.randi_range(0, i)
		var tmp = bots[i]
		bots[i] = bots[j]
		bots[j] = tmp
	var classes := class_ids()
	var entries: Array = []
	for team in ["red", "blue"]:
		for h in teams[team]:
			entries.append({"name": h.name, "cls": h.cls, "spec": GameData.normalize_spec(h.cls, str(h.get("spec", ""))), "team": team, "peer": h.peer})
		for i in range(teams[team].size(), mode):
			var bot_cls: String = classes[rng.randi() % classes.size()]
			var bot_specs := GameData.spec_ids(bot_cls)
			entries.append({"name": bots.pop_back() if not bots.is_empty() else "Bot%d" % i, "cls": bot_cls, "spec": bot_specs[rng.randi() % bot_specs.size()] if not bot_specs.is_empty() else "", "team": team, "peer": 0})
	return entries
