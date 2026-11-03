class_name TournamentInfo
extends RefCounted
## What the tournament screen and the hub show, as plain data (pure, tested): tier cards, bracket columns, the "continue"
## line, the account level and the challenge rows. The screens only lay these out.


static func mode_name(mode: int) -> String:
	return "%dv%d" % [mode, mode]


## "Rivales: +20% vida y +15% daño" for tiers with a bonus ("" otherwise): shown on the card so it is never a surprise.
static func bonus_text(tier_id: String) -> String:
	var t := Tournament.tier(tier_id)
	var hp := roundi((float(t.hp_mult) - 1.0) * 100.0)
	var dmg := roundi((float(t.dmg_mult) - 1.0) * 100.0)
	if hp <= 0 and dmg <= 0:
		return ""
	return "Rivales: +%d%% vida y +%d%% daño" % [hp, dmg]


## {id, name, locked, cups, status, bonus, optional} of one tier in one mode.
static func tier_card(store: TournamentStore, mode: int, tier_id: String) -> Dictionary:
	var t := Tournament.tier(tier_id)
	var locked := not store.is_unlocked(mode, tier_id)
	var status := ""
	if locked:
		var prev := Tournament.tier(Tournament.tier_ids()[maxi(Tournament.tier_index(tier_id) - 1, 0)])
		status = "Bloqueado: ganá la copa de %s %s." % [prev.name, mode_name(mode)]
	else:
		var r := int(t.rematches)
		status = "Revancha gratis: %d" % r if r > 0 else "Sin revancha"
	return {"id": tier_id, "name": str(t.name), "locked": locked, "cups": store.cups(mode, tier_id), "status": status, "bonus": bonus_text(tier_id), "optional": bool(t.get("optional", false))}


## The bracket of a run as 3 columns of matches: [{a, b, winner (-1 not played, 0 or 1), mine}]. Teams that have not
## arrived yet show "?". An empty list when there is no run.
static func bracket_columns(run: Dictionary) -> Array:
	if run.is_empty() or not run.has("bracket"):
		return []
	var cols: Array = []
	for r in Tournament.ROUNDS:
		var seats := Tournament.participants(run, r)
		var col: Array = []
		for m in seats.size() / 2:
			var a := int(seats[m * 2])
			var b := int(seats[m * 2 + 1])
			var w := int(run.rounds[r][m])
			col.append({
				"a": _team_name(run, a), "b": _team_name(run, b),
				"winner": -1 if w < 0 else (0 if w == a else 1),
				"mine": a == int(run.seat) or b == int(run.seat),
			})
		cols.append(col)
	return cols


static func _team_name(run: Dictionary, seat: int) -> String:
	return "?" if seat < 0 else str(run.bracket[seat].name)


## Hub card line for a run in progress ("" when there is none): tier, mode, round and the next rival.
static func continue_text(store: TournamentStore) -> String:
	if not store.has_active_run():
		return ""
	var m := Tournament.next_match(store.run, store.streak(int(store.run.mode), str(store.run.tier)))
	return "%s %s · %s vs %s" % [Tournament.tier(str(store.run.tier)).name, mode_name(int(store.run.mode)), m.round_name, str(m.opponent.name)]


## "Nivel 3 · 120 / 160 XP" (or "Nivel 20 · MÁX").
static func level_text(profile: ProfileStore) -> String:
	var p := profile.progress()
	if p.maxed:
		return "Nivel %d · MÁX" % p.level
	return "Nivel %d · %d / %d XP" % [p.level, p.into, p.need]


## Rows for the challenges of one class: [{id, name, desc, progress_text, done, reward}].
static func challenge_rows(profile: ProfileStore, cls: String) -> Array:
	var rows: Array = []
	for c in Challenges.for_class(cls):
		var st := profile.challenge_state(str(c.id))
		var text := "Completado" if (st.done and c.kind == "match") else "%d/%d" % [st.progress, int(c.goal) if c.kind == "total" else 1]
		if st.done and c.kind == "total":
			text = "%d/%d" % [int(c.goal), int(c.goal)]
		rows.append({"id": str(c.id), "name": str(c.name), "desc": str(c.desc), "progress_text": text, "done": st.done, "reward": "Premio: %s" % str(Challenges.item(str(c.reward)).name)})
	return rows
