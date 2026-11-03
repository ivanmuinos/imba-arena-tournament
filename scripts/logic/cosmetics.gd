class_name Cosmetics
extends RefCounted
## What the views draw from the local player's equipped rewards (title, ring colour, class recolor). main.gd sets `profile`;
## without one (tests, dedicated server) nothing is applied. Cosmetics are local only: other players are never recolored.

static var profile: ProfileStore = null


static func title() -> String:
	if profile == null or str(profile.equipped.title) == "":
		return ""
	return str(Challenges.item(str(profile.equipped.title)).get("name", ""))


## Colour of the equipped ring, or `fallback` when none.
static func ring_color(fallback: Color) -> Color:
	if profile == null or str(profile.equipped.ring) == "":
		return fallback
	var v := str(Challenges.item(str(profile.equipped.ring)).get("value", ""))
	return Color(v) if v.begins_with("#") else fallback


## Item id of the recolor equipped for `cls` ("" when none).
static func skin_for(cls: String) -> String:
	return "" if profile == null else str(profile.equipped.recolor.get(cls, ""))


## {hue, sat, val} of a recolor item ({} when unknown).
static func tint(item_id: String) -> Dictionary:
	var t = Challenges.item(item_id).get("tint", {})
	return t if typeof(t) == TYPE_DICTIONARY else {}


## What CharacterRig merges over the class for the skin equipped on `cls`: the tint replaces the class's recolor (never stacks); {} for none.
static func rig_skin(cls: String) -> Dictionary:
	var id := skin_for(cls)
	var t := tint(id) if id != "" else {}
	return {} if t.is_empty() else {"id": id, "recolor": t}
