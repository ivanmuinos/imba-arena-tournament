extends TestBase
## Tournament screen data (S10): tier cards, bracket columns, hub "continue" text, level text, Gladiador bonus.

const PLAYER := {"name": "Ana", "cls": "mage", "spec": "fire"}


func _store() -> TournamentStore:
	var path := "user://test_ti_tournament.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	return TournamentStore.new(path)


func test_tier_cards_show_locks_cups_and_rematches() -> void:
	var s := _store()
	var b := TournamentInfo.tier_card(s, 1, "bronze")
	check(not b.locked, "Bronce abierto")
	eq(b.cups, 0, "sin copas")
	check(str(b.status).contains("Revancha"), "Bronce avisa su revancha: " + str(b.status))
	var g := TournamentInfo.tier_card(s, 1, "silver")
	check(g.locked, "Plata bloqueada")
	check(str(g.status).contains("Bronce"), "dice qué falta ganar: " + str(g.status))
	s.won["1:bronze"] = 2
	var b2 := TournamentInfo.tier_card(s, 1, "bronze")
	eq(b2.cups, 2, "copas del nivel")
	check(not TournamentInfo.tier_card(s, 1, "silver").locked, "Plata se abre")
	check(TournamentInfo.tier_card(s, 2, "silver").locked, "las modalidades no comparten desbloqueos")


func test_gladiator_bonus_is_visible_and_other_tiers_have_none() -> void:
	check(TournamentInfo.bonus_text("gladiator").contains("20%"), "vida +20%")
	check(TournamentInfo.bonus_text("gladiator").contains("15%"), "daño +15%")
	eq(TournamentInfo.bonus_text("bronze"), "", "Bronce sin bonus")
	check(str(TournamentInfo.tier_card(_store(), 1, "gladiator").bonus).contains("20%"), "la tarjeta lo muestra")


func test_bracket_columns_have_4_2_1_matches_with_winners() -> void:
	var run := Tournament.new_run(1, "bronze", PLAYER, 3)
	var cols := TournamentInfo.bracket_columns(run)
	eq(cols.size(), 3, "3 rondas")
	eq([cols[0].size(), cols[1].size(), cols[2].size()], [4, 2, 1], "4, 2 y 1 partidas")
	eq(cols[1][0].a, "?", "todavía no se sabe quién llega")
	var mine: Dictionary = cols[0].filter(func(m): return m.mine)[0]
	check(mine.a == "Ana" or mine.b == "Ana", "el jugador figura en su partida")
	Tournament.report(run, true)
	cols = TournamentInfo.bracket_columns(run)
	mine = cols[0].filter(func(m): return m.mine)[0]
	var won_side: String = mine.a if mine.winner == 0 else mine.b
	eq(won_side, "Ana", "ganó la ronda 1")
	check(cols[1].any(func(m): return m.a == "Ana" or m.b == "Ana"), "avanza a semifinal")
	eq(TournamentInfo.bracket_columns({}).size(), 0, "sin run no hay cuadro")


func test_continue_text_names_the_next_rival() -> void:
	var s := _store()
	eq(TournamentInfo.continue_text(s), "", "sin run no hay tarjeta")
	s.start_run(2, "bronze", PLAYER, 11)
	var t := TournamentInfo.continue_text(s)
	check(t.contains("Bronce") and t.contains("2v2"), "nivel y modalidad: " + t)
	check(t.contains(str(Tournament.next_match(s.run).opponent.name)), "nombra al rival: " + t)
	s.run.status = "lost"
	eq(TournamentInfo.continue_text(s), "", "run terminada: sin tarjeta")


func test_level_text_shows_level_and_xp() -> void:
	var p := ProfileStore.new("user://test_ti_profile.json")
	p.xp = 0
	check(TournamentInfo.level_text(p).contains("Nivel 1"), "nivel 1")
	check(TournamentInfo.level_text(p).contains("/ %d" % ProfileStore.need_for(1)), "XP necesaria")
	p.xp = ProfileStore.xp_to_reach(ProfileStore.max_level())
	check(TournamentInfo.level_text(p).contains("MÁX"), "tope")


func test_challenge_rows_report_progress_and_reward() -> void:
	var p := ProfileStore.new("user://test_ti_profile.json")
	p.challenges = {"mage_1": {"progress": 2, "done": false}, "mage_3": {"progress": 1, "done": true}}
	var rows := TournamentInfo.challenge_rows(p, "mage")
	eq(rows.size(), 3, "3 desafíos")
	eq(rows[0].progress_text, "2/3", "progreso total")
	check(rows[2].done, "hecho")
	eq(rows[2].progress_text, "Completado", "desafío de partida completado")
	check(str(rows[0].reward).contains(str(Challenges.item("title_mage").name)), "recompensa nombrada")
