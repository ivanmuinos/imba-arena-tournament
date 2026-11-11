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


## What a medal asks for, in words ("en menos de 0:25 y sin quemarte"). Gold also needs what silver needs.
static func goal_text(rule: Dictionary, medal: int) -> String:
	if medal <= BRONZE:
		return "completando todos los objetivos"
	var conditions: Dictionary = (rule.get("silver", {}) as Dictionary).duplicate()
	if medal >= GOLD:
		conditions.merge(rule.get("gold", {}), true)
	var parts: Array = []
	for c in conditions:
		var limit := float(conditions[c])
		match str(c):
			"max_time_ms": parts.append("en menos de %s" % time_text(limit))
			"max_taken": parts.append("recibiendo menos de %d de daño" % int(limit))
			"max_mistakes": parts.append("sin errores" if limit <= 0.0 else "con %d errores como mucho" % int(limit))
			"max_downs": parts.append("sin caer" if limit <= 0.0 else "cayendo %d veces como mucho" % int(limit))
			"min_hp_pct": parts.append("con más de %d%% de vida" % int(limit * 100.0))
	if parts.is_empty():
		return "completando todos los objetivos"
	return " y ".join(parts)


## The best medal a run can still earn: time, damage, mistakes and falls only grow, health is not known until the end.
static func still_possible(rule: Dictionary, stats: Dictionary) -> int:
	var hopeful := stats.duplicate()
	hopeful["hp_pct"] = 1.0
	return grade(rule, hopeful)


## One short line for the card while playing: the medal still in reach and the number that decides it ("Oro · 0:12 de 0:25").
static func live_text(rule: Dictionary, stats: Dictionary) -> String:
	var medal := still_possible(rule, stats)
	if medal <= NONE:
		return "Sin medalla: salteaste un paso"
	var conditions: Dictionary = (rule.get("silver", {}) as Dictionary).duplicate()
	if medal >= GOLD:
		conditions.merge(rule.get("gold", {}), true)
	var name := str(NAMES[medal])
	if medal <= BRONZE or conditions.is_empty():
		return "%s · %s" % [name, time_text(float(stats.get("time_ms", 0.0)))]
	if conditions.has("max_time_ms"):
		return "%s · %s de %s" % [name, time_text(float(stats.get("time_ms", 0.0))), time_text(float(conditions.max_time_ms))]
	if conditions.has("max_mistakes"):
		return "%s · sin errores hasta ahora" % name
	if conditions.has("max_taken"):
		return "%s · daño recibido %d de %d" % [name, int(float(stats.get("taken", 0.0))), int(float(conditions.max_taken))]
	if conditions.has("max_downs"):
		return "%s · sin caer hasta ahora" % name
	return name
