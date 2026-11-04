class_name AcademyMedals
extends RefCounted
## The medal a lesson run earns. Finishing every objective gives bronze; silver and gold add the conditions of the lesson's rule,
## and gold also needs silver's. Skipping a step earns nothing. A lesson with no rule (a guided menu, say) is simply done or not.

const NONE := 0
const BRONZE := 1
const SILVER := 2
const GOLD := 3
const NAMES := ["Sin medalla", "Bronce", "Plata", "Oro"]
const COLORS := [Color("#6f655d"), Color("#c9824a"), Color("#c8d0d8"), Color("#ffc15a")]


static func grade(rule: Dictionary, stats: Dictionary) -> int:
	if int(stats.get("skipped", 0)) > 0:
		return NONE
	if rule.is_empty():
		return GOLD
	if not _passes(rule.get("silver", {}), stats):
		return BRONZE
	return GOLD if rule.has("gold") and _passes(rule.gold, stats) else SILVER if rule.has("silver") else BRONZE


static func _passes(conditions: Dictionary, stats: Dictionary) -> bool:
	for c in conditions:
		if not _meets(str(c), float(conditions[c]), stats):
			return false
	return true


## A stat the run did not report, or a condition nobody knows, never gives the medal away.
static func _meets(condition: String, limit: float, stats: Dictionary) -> bool:
	var stat := {"max_time_ms": "time_ms", "max_taken": "taken", "max_mistakes": "mistakes", "max_downs": "downs", "min_hp_pct": "hp_pct"}.get(condition, "") as String
	if stat == "" or not stats.has(stat):
		return false
	return float(stats[stat]) >= limit if condition.begins_with("min_") else float(stats[stat]) <= limit


static func time_text(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%d:%02d" % [total / 60, total % 60]


## The closing words of a run, with its medal and whether it beat the player's best.
static func result_text(medal: int, ms: float, best: bool) -> String:
	if medal <= NONE:
		return "Salteaste algún paso, así que esta vez no hay medalla. Repetila completa para ganar una."
	var line := "Medalla de [b]%s[/b] en %s." % [str(NAMES[clampi(medal, 0, GOLD)]).to_lower(), time_text(ms)]
	return line + (" ¡Es tu mejor resultado!" if best else "")
