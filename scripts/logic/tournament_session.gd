class_name TournamentSession
extends RefCounted
## One tournament in progress as the shell sees it: starts or resumes the run, hands out the scripted match, and turns a
## finished match into a run result plus profile rewards. Pure logic over TournamentStore and ProfileStore (no UI, no scene).
## Practice never reaches this class; normal offline bot matches only use the static `record_bot`.

var store: TournamentStore
var profile: ProfileStore
var current := {}  # the match being played (Tournament.next_match)


func _init(p_store: TournamentStore, p_profile: ProfileStore) -> void:
	store = p_store
	profile = p_profile


func active() -> bool:
	return store.has_active_run()


func start(mode: int, tier_id: String, player: Dictionary, seed_value: int) -> bool:
	return store.start_run(mode, tier_id, player, seed_value)


## The match to play now (marks it pending, so closing the game replays the same one).
func begin() -> Dictionary:
	current = store.begin_match()
	return current


## What GameServer needs for the current match.
func server_cfg() -> Dictionary:
	return {"mode": int(current.mode), "diff": "normal", "map": str(current.map), "scripted": current.scripted}


func mode() -> int:
	return int(store.run.get("mode", current.get("mode", 1)))


func tier_id() -> String:
	return str(store.run.get("tier", current.get("tier", "bronze")))


## Applies a finished (or given up) match. `stats` is the local player's entry of the end message.
## Returns {kind: next|cup|rematch|out, won, status, rec, next, unlocked_tier, button, lines}.
func finish(won: bool, stats: Dictionary, forfeited := false) -> Dictionary:
	var m := mode()
	var t := tier_id()
	var cls := str(store.run.player.cls)
	var res := store.forfeit() if forfeited else store.report(won)
	var rec := profile.record_match("tournament", cls, won, stats, m)
	var unlocked := ""
	if str(res.status) == "won":
		var first := store.cups(m, t) == 1
		profile.record_cup(m, t)
		var ids := Tournament.tier_ids()
		var i := ids.find(t)
		if first and i >= 0 and i + 1 < ids.size():
			unlocked = str(ids[i + 1])
	var kind := "out"
	if str(res.status) == "won":
		kind = "cup"
	elif str(res.status) == "active":
		kind = "next" if won else "rematch"
	var next := {}
	if kind == "next" or kind == "rematch":
		next = Tournament.next_match(store.run, store.streak(m, t))
	var out := {"kind": kind, "won": won, "status": str(res.status), "rec": rec, "next": next, "unlocked_tier": unlocked}
	out["button"] = button_text(kind)
	out["lines"] = summary_lines(out)
	return out


static func button_text(kind: String) -> String:
	match kind:
		"next":
			return "SIGUIENTE RONDA"
		"rematch":
			return "REVANCHA"
	return "VOLVER AL TORNEO"


## Spanish lines for the end screen: what the run did, the next rival, then XP, level and rewards.
static func summary_lines(r: Dictionary) -> Array:
	var lines: Array = []
	match str(r.kind):
		"cup":
			lines.append("¡COPA CONSEGUIDA!")
			if str(r.get("unlocked_tier", "")) != "":
				lines.append("Se abrió el nivel %s." % Tournament.tier(str(r.unlocked_tier)).name)
		"next":
			lines.append("Avanzás a la ronda: %s." % str(r.next.round_name))
		"rematch":
			lines.append("Perdiste, pero tenés una revancha gratis.")
		"out":
			lines.append("Quedaste eliminado del torneo.")
	if not (r.get("next", {}) as Dictionary).is_empty():
		var n: Dictionary = r.next
		var boss := " (jefe)" if bool(n.boss) else ""
		lines.append("Próximo rival: %s%s." % [str(n.opponent.name), boss])
	lines.append_array(reward_lines(r.rec))
	return lines


## XP, level, level-ups, completed challenges and new items of one ProfileStore.record_match result.
static func reward_lines(rec: Dictionary) -> Array:
	var lines: Array = []
	if int(rec.xp) <= 0:
		return lines
	lines.append("+%d XP · Nivel %d" % [int(rec.xp), int(rec.level_after)])
	for up in rec.level_ups:
		lines.append("¡SUBISTE AL NIVEL %d!" % int(up.level))
	for id in rec.completed:
		lines.append("Desafío completado: %s" % str(Challenges.get_challenge(str(id)).name))
	for id in rec.rewards:
		var it := Challenges.item(str(id))
		lines.append("Desbloqueaste: %s (%s)" % [str(it.name), {"title": "título", "ring": "anillo", "recolor": "color de clase"}.get(str(it.kind), "")])
	return lines


## Profile record of a normal offline match against bots (practice must not call this).
static func record_bot(profile: ProfileStore, cls: String, won: bool, stats: Dictionary) -> Dictionary:
	return profile.record_match("bot", cls, won, stats)
