extends TestBase
## Tournament session (S8): glue between a finished match, the run store and the profile.

const PLAYER := {"name": "Ana", "cls": "mage", "spec": "fire"}
const STATS := {"id": 1, "dmg": 900, "kills": 1, "deaths": 0, "heal": 0}


func _clean(path: String) -> String:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	return path


func _session() -> TournamentSession:
	var store := TournamentStore.new(_clean("user://test_ts_tournament.json"))
	var prof := ProfileStore.new(_clean("user://test_ts_profile.json"))
	return TournamentSession.new(store, prof)


func test_start_and_begin_give_a_scripted_server_cfg() -> void:
	var s := _session()
	check(s.start(1, "bronze", PLAYER, 5), "Bronce siempre abierto")
	var m := s.begin()
	eq(m.round, 0, "arranca en cuartos")
	var cfg := s.server_cfg()
	eq(cfg.mode, 1, "modalidad")
	eq(cfg.map, m.map, "mapa del torneo")
	eq(cfg.scripted, m.scripted, "lista guionada")
	check(not (cfg.scripted as Array).is_empty(), "hay unidades")


func test_locked_tier_does_not_start() -> void:
	var s := _session()
	check(not s.start(1, "gold", PLAYER, 5), "Oro bloqueado")
	check(not s.active(), "sin run")


func test_win_advances_and_pays_tournament_xp() -> void:
	var s := _session()
	s.start(1, "bronze", PLAYER, 5)
	s.begin()
	var r := s.finish(true, STATS)
	eq(r.kind, "next", "gana y sigue")
	eq(s.store.run.round, 1, "pasa a semifinal")
	eq(r.rec.xp, ProfileStore.xp_for("tournament", true), "XP de torneo")
	eq(s.profile.class_stats("mage").matches, 1, "estadísticas de la clase")
	check(not r.next.is_empty() and r.next.round == 1, "próximo rival: semifinal")
	check(r.button != "", "texto del botón")
	check(r.lines.size() > 0, "resumen")


func test_loss_with_rematch_and_forfeit_counts_as_loss() -> void:
	var s := _session()
	s.start(1, "bronze", PLAYER, 5)
	s.begin()
	var r := s.finish(false, STATS)
	eq(r.kind, "rematch", "Bronce da revancha")
	eq(s.store.streak(1, "bronze"), 1, "racha")
	s.begin()
	r = s.finish(false, STATS, true)
	eq(r.kind, "out", "rendirse sin revancha termina la run")
	eq(s.store.run.status, "lost", "run perdida")
	check(not s.active(), "ya no hay run activa")


func test_cup_won_records_cup_in_both_stores_and_unlocks_next_tier() -> void:
	var s := _session()
	s.start(1, "bronze", PLAYER, 5)
	var last := {}
	for i in 3:
		s.begin()
		last = s.finish(true, STATS)
	eq(last.kind, "cup", "copa")
	eq(s.store.cups(1, "bronze"), 1, "copa en el torneo")
	eq(s.profile.cups("1:bronze"), 1, "copa en el perfil")
	eq(last.unlocked_tier, "silver", "abre Plata")
	check(s.store.is_unlocked(1, "silver"), "Plata abierta")


func test_bot_result_uses_bot_source_and_practice_gives_nothing() -> void:
	var prof := ProfileStore.new(_clean("user://test_ts_profile.json"))
	var r := TournamentSession.record_bot(prof, "warrior", true, STATS)
	eq(r.xp, ProfileStore.xp_for("bot", true), "XP contra bots")
	eq(prof.class_stats("warrior").wins, 1, "victoria contada")
	eq(TournamentSession.reward_lines(r).size() >= 1, true, "línea de XP")
	var none := prof.record_match("practice", "warrior", true, STATS)
	eq(none.xp, 0, "la práctica no da nada")


func test_reward_lines_mention_level_up_and_items() -> void:
	var prof := ProfileStore.new(_clean("user://test_ts_profile.json"))
	prof.xp = ProfileStore.xp_to_reach(2) - 1
	var r := TournamentSession.record_bot(prof, "mage", true, STATS)
	var text := "\n".join(TournamentSession.reward_lines(r))
	check(text.contains("NIVEL 2"), "avisa el nivel: " + text)
	check(text.contains(str(Challenges.item("title_lv2").name)), "nombra la recompensa: " + text)


func test_resume_keeps_the_same_pending_match() -> void:
	var path := _clean("user://test_ts_tournament.json")
	var a := TournamentSession.new(TournamentStore.new(path), ProfileStore.new(_clean("user://test_ts_profile.json")))
	a.start(2, "bronze", PLAYER, 9)
	var m1 := a.begin()
	var b := TournamentSession.new(TournamentStore.new(path), a.profile)
	check(b.active() and b.store.has_pending(), "retoma con partida pendiente")
	eq(b.begin().scripted, m1.scripted, "misma partida")


func test_server_forfeit_local_ends_the_match_with_the_player_losing() -> void:
	var script := [
		{"human": true, "team": "red"},
		{"name": "Jefe", "cls": "warrior", "team": "blue", "diff": "easy"}]
	var server := GameServer.new({"mode": 1, "map": "bridge", "scripted": script})
	check(not server.forfeit_local(), "sin partida no hay nada que rendir")
	var link := LoopbackTransport.pair()
	server.attach(link[0], true)
	var client := GameClient.new()
	client.attach(link[1], {"name": "Ana", "cls": "mage", "pref": "red"})
	var ends: Array = []
	client.match_ended.connect(func(m): ends.append(m))
	for i in 4:
		server.process(16.0)
		client.poll(16.0)
	server.start_match(true)
	for i in 4:
		server.process(16.0)
		client.poll(16.0)
	check(server.forfeit_local(), "se rinde")
	for i in 4:
		server.process(16.0)
		client.poll(16.0)
	eq(ends.size(), 1, "un mensaje de fin")
	eq(ends[0].winner, "blue", "gana el rival")
	check(not server.forfeit_local(), "no se puede rendir dos veces")
