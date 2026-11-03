extends TestBase
## Tournament rules (S5): data, bracket, rounds, rematches, skill cuts, save and resume.

const PLAYER := {"name": "Ana", "cls": "mage", "spec": "fire"}


func _store_path() -> String:
	var path := "user://test_tournament.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	return path


func test_data_covers_three_modes_and_four_tiers_with_valid_teams() -> void:
	eq(Tournament.tier_ids(), ["bronze", "silver", "gold", "gladiator"], "4 niveles")
	for mode in [1, 2, 3]:
		var teams := Tournament.teams(mode)
		eq(teams.size(), 12, "12 equipos en %dv%d" % [mode, mode])
		var bosses := teams.filter(func(t): return t.has("boss"))
		eq(bosses.size(), 4, "un jefe por nivel")
		var ids := {}
		for t in teams:
			check(str(t.name).length() <= 16 and str(t.name) != "", "nombre de equipo corto: " + str(t.name))
			eq(t.members.size(), mode, "integrantes = modalidad en " + str(t.name))
			ids[t.id] = true
			for m in t.members:
				check(GameData.playable(str(m.cls)), "clase jugable: " + str(m.cls))
				check(str(m.name).length() <= 16 and str(m.name) != "", "nombre corto: " + str(m.name))
		eq(ids.size(), 12, "ids únicos")
		for tier in Tournament.tier_ids():
			eq(bosses.filter(func(t): return t.boss == tier).size(), 1, "jefe de " + tier)
	var tiers := Tournament.tiers()
	eq(tiers[0].skill, [0.15, 0.2, 0.3], "tabla de Bronce")
	eq(tiers[3].hp_mult, 1.2, "Gladiador: vida +20%")
	eq(tiers[3].dmg_mult, 1.15, "Gladiador: daño +15%")
	eq(tiers[2].rematches, 0, "Oro sin revancha")


func test_bracket_is_seeded_and_places_boss_opposite_the_player() -> void:
	var a := Tournament.new_run(2, "silver", PLAYER, 77)
	var b := Tournament.new_run(2, "silver", PLAYER, 77)
	eq(a.bracket.map(func(t): return t.id), b.bracket.map(func(t): return t.id), "misma semilla, mismo cuadro")
	eq(a.bracket.size(), 8, "8 equipos")
	eq(a.bracket[a.seat].id, "player", "el jugador está en su asiento")
	var ids: Array = a.bracket.map(func(t): return t.id)
	var seen := {}
	for i in ids:
		seen[i] = true
	eq(seen.size(), 8, "sin repetidos")
	var boss_seat := -1
	for i in 8:
		if a.bracket[i].get("boss", "") == "silver":
			boss_seat = i
		elif a.bracket[i].has("boss"):
			check(false, "solo el jefe del nivel entra al cuadro")
	check(boss_seat >= 0, "el jefe del nivel está")
	check((boss_seat >= 4) != (int(a.seat) >= 4), "jefe en la otra mitad: lo ves en la final")
	var other := Tournament.new_run(2, "silver", PLAYER, 78)
	check(other.bracket.map(func(t): return t.id) != ids or other.seat != a.seat, "otra semilla, otro cuadro")


func test_a_cup_is_three_wins_and_the_boss_is_the_final() -> void:
	var run := Tournament.new_run(1, "bronze", PLAYER, 5)
	var names := []
	for r in 3:
		var m := Tournament.next_match(run)
		eq(m.round, r, "ronda %d" % r)
		names.append(m.round_name)
		near(m.skill, Tournament.tier("bronze").skill[r], 0.0001, "skill de la ronda")
		eq(m.boss, r == 2, "el jefe es la final")
		Tournament.report(run, true)
	eq(names, ["Cuartos", "Semifinal", "Final"], "nombres de ronda")
	eq(run.status, "won", "copa ganada")


func test_scripted_list_has_human_allies_and_scaled_rivals() -> void:
	var run := Tournament.new_run(3, "gladiator", {"name": "Ana", "cls": "warrior", "spec": ""}, 9)
	var m := Tournament.next_match(run)
	var s: Array = m.scripted
	eq(s.size(), 6, "3v3")
	eq(s.filter(func(e): return e.get("human", false)).size(), 1, "un humano")
	var red := s.filter(func(e): return e.team == "red")
	var blue := s.filter(func(e): return e.team == "blue")
	eq(red.size(), 3, "3 de tu lado")
	eq(blue.size(), 3, "3 rivales")
	var ally_classes := red.filter(func(e): return not e.get("human", false)).map(func(e): return e.cls)
	eq(ally_classes, Tournament.data().allies.warrior, "aliados por rol")
	for e in blue:
		eq(e.hp_mult, 1.2, "vida +20% rival")
		eq(e.dmg_mult, 1.15, "daño +15% rival")
		near(e.skill, 0.95, 0.0001, "skill rival")
		eq(e.diff, "hard", "dificultad rival")
	for e in red.filter(func(e): return not e.get("human", false)):
		eq(e.get("hp_mult", 1.0), 1.0, "aliados sin bonus")
		check(not e.has("skill"), "aliados con el rango de su dificultad")
	var entries := MatchConfig.scripted_entries(s, [{"peer": 1, "name": "Ana", "cls": "warrior", "spec": "", "pref": "any"}])
	eq(entries.size(), 6, "el guion entra tal cual en MatchConfig")


func test_names_never_clash_with_the_player() -> void:
	var run := Tournament.new_run(1, "bronze", {"name": "Tizón", "cls": "mage", "spec": ""}, 1)
	for r in 3:
		var m := Tournament.next_match(run)
		var names: Array = m.scripted.filter(func(e): return not e.get("human", false)).map(func(e): return str(e.get("name", "")).to_lower())
		var clash: Array = names.filter(func(n): return n == "tizón")
		eq(clash.size(), 0, "ningún bot se llama como vos")
		for e in m.scripted:
			check(str(e.get("name", "x")).length() <= 16, "nombre corto")
		Tournament.report(run, true)
	var team := Tournament.new_run(2, "bronze", {"name": "Ana", "cls": "mage", "spec": ""}, 2)
	var names2 := {}
	for e in Tournament.next_match(team).scripted:
		if not e.get("human", false):
			check(not names2.has(e.name), "sin nombres repetidos: " + str(e.name))
			names2[e.name] = true


func test_bronze_loss_gives_one_free_rematch_then_the_run_ends() -> void:
	var run := Tournament.new_run(1, "bronze", PLAYER, 3)
	var first := Tournament.next_match(run)
	eq(run.rematches_left, 1, "una revancha")
	Tournament.report(run, false)
	eq(run.status, "active", "sigue la run")
	eq(run.rematches_left, 0, "revancha usada")
	var again := Tournament.next_match(run)
	eq(again.round, first.round, "misma ronda")
	eq(again.opponent.id, first.opponent.id, "mismo rival")
	Tournament.report(run, false)
	eq(run.status, "lost", "segunda derrota: fin")
	var gold := Tournament.new_run(1, "gold", PLAYER, 3)
	Tournament.report(gold, false)
	eq(gold.status, "lost", "Oro: una derrota termina la run")


func test_consecutive_losses_cut_skill_by_005_down_to_the_floor() -> void:
	var bronze := Tournament.tier("bronze")
	near(Tournament.effective_skill(bronze, 2, 0), 0.3, 0.0001, "sin derrotas")
	near(Tournament.effective_skill(bronze, 2, 1), 0.25, 0.0001, "una derrota")
	near(Tournament.effective_skill(bronze, 2, 2), 0.2, 0.0001, "dos")
	near(Tournament.effective_skill(bronze, 2, 9), 0.15, 0.0001, "piso: el skill de cuartos")
	near(Tournament.effective_skill(bronze, 0, 5), 0.15, 0.0001, "cuartos ya está en el piso")
	var silver := Tournament.tier("silver")
	near(Tournament.effective_skill(silver, 1, 1), 0.40, 0.0001, "Plata baja y toca el piso 0,4")
	var gold := Tournament.tier("gold")
	near(Tournament.effective_skill(gold, 2, 5), 0.95, 0.0001, "Oro no baja")


func test_displayed_results_are_stable_and_the_boss_always_advances() -> void:
	var run := Tournament.new_run(2, "gold", PLAYER, 21)
	Tournament.report(run, true)
	var snapshot := JSON.stringify(run.rounds)
	var copy: Dictionary = JSON.parse_string(JSON.stringify(run))
	var reread: Array = copy.rounds.map(func(row): return row.map(func(v): return int(v)))
	eq(reread, run.rounds, "se guarda y se lee igual")
	var continued := Tournament.next_match(copy)
	eq(continued.round, 1, "una run recargada sigue donde estaba")
	for w in run.rounds[0]:
		check(int(w) >= 0, "la primera ronda se resolvió completa")
	Tournament.report(run, true)
	var final := Tournament.next_match(run)
	eq(final.round, 2, "final")
	check(final.boss, "el jefe llega a la final")
	var other := Tournament.new_run(2, "gold", PLAYER, 21)
	Tournament.report(other, true)
	eq(JSON.stringify(other.rounds), snapshot, "misma semilla, mismos resultados")


func test_loss_resolves_the_rest_of_the_bracket_for_display() -> void:
	var run := Tournament.new_run(1, "gold", PLAYER, 4)
	Tournament.report(run, false)
	eq(run.status, "lost", "perdida")
	eq(run.rounds[2].size(), 1, "hay campeón")
	check(int(run.rounds[2][0]) >= 0 and int(run.rounds[2][0]) != int(run.seat), "campeón distinto del jugador")


func test_store_unlocks_tiers_by_mode_and_persists() -> void:
	var path := _store_path()
	var s := TournamentStore.new(path)
	check(s.is_unlocked(2, "bronze"), "Bronce abierto")
	check(not s.is_unlocked(2, "silver"), "Plata cerrada")
	check(not s.start_run(2, "silver", PLAYER, 1), "no se puede empezar un nivel cerrado")
	check(s.start_run(2, "bronze", PLAYER, 1), "Bronce arranca")
	for r in 3:
		s.begin_match()
		s.report(true)
	eq(s.run.status, "won", "copa")
	check(s.is_unlocked(2, "silver"), "ganar abre el siguiente")
	check(not s.is_unlocked(1, "silver"), "otra modalidad sigue cerrada")
	var again := TournamentStore.new(path)
	check(again.is_unlocked(2, "silver"), "el desbloqueo sobrevive al reinicio")
	eq(again.cups(2, "bronze"), 1, "copas de Bronce")


func test_save_is_atomic_and_leaves_no_temp_file() -> void:
	var path := _store_path()
	var s := TournamentStore.new(path)
	s.start_run(1, "bronze", PLAYER, 1)
	check(FileAccess.file_exists(path), "archivo escrito")
	check(not FileAccess.file_exists(path + ".tmp"), "sin temporal")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	eq(typeof(parsed), TYPE_DICTIONARY, "JSON válido")
	# a stale temp from a crash never replaces the real file
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	f.store_string("{roto")
	f.close()
	var back := TournamentStore.new(path)
	check(back.has_active_run(), "carga el archivo real, no el temporal")
	back.begin_match()
	check(not FileAccess.file_exists(path + ".tmp"), "el temporal viejo se pisa y se renombra")
	eq(typeof(JSON.parse_string(FileAccess.get_file_as_string(path))), TYPE_DICTIONARY, "sigue válido")


func test_resume_replays_the_same_match_without_penalty() -> void:
	var path := _store_path()
	var s := TournamentStore.new(path)
	s.start_run(1, "bronze", PLAYER, 42)
	var m := s.begin_match()
	var closed := TournamentStore.new(path)  # the game closed mid-match
	check(closed.has_active_run(), "run viva")
	check(closed.has_pending(), "había una partida en curso")
	var m2 := closed.begin_match()
	eq(m2.opponent.id, m.opponent.id, "mismo rival")
	eq(m2.map, m.map, "misma arena")
	near(m2.skill, m.skill, 0.0001, "mismo skill")
	eq(closed.run.rematches_left, 1, "sin penalización")
	eq(closed.streak(1, "bronze"), 0, "sin derrota anotada")
	check(closed.run.status == "active", "sigue activa")


func test_forfeit_counts_as_a_loss_and_streak_lowers_the_next_skill() -> void:
	var path := _store_path()
	var s := TournamentStore.new(path)
	s.start_run(1, "bronze", PLAYER, 8)
	var m := s.begin_match()
	s.forfeit()
	eq(s.streak(1, "bronze"), 1, "una derrota seguida")
	var m2 := s.begin_match()  # free rematch
	near(m2.skill, maxf(0.15, m.skill - 0.05), 0.0001, "el rival baja 0,05 hasta el piso")
	s.report(true)
	eq(s.streak(1, "bronze"), 0, "ganar corta la racha")
	var reloaded := TournamentStore.new(path)
	eq(reloaded.streak(1, "bronze"), 0, "la racha se guarda")


func test_streak_persists_across_runs_and_cuts_the_next_run() -> void:
	var path := _store_path()
	var s := TournamentStore.new(path)
	s.start_run(1, "bronze", PLAYER, 1)
	s.begin_match()
	s.report(false)
	s.begin_match()
	s.report(false)  # run lost
	eq(s.run.status, "lost", "run perdida")
	eq(s.streak(1, "bronze"), 2, "dos derrotas seguidas")
	s.start_run(1, "bronze", PLAYER, 2)
	var m := s.begin_match()
	near(m.skill, 0.15, 0.0001, "cuartos ya en el piso, no baja más")
	s.report(true)
	eq(s.streak(1, "bronze"), 0, "la victoria cortó la racha")
	var semi := s.begin_match()
	near(semi.skill, 0.2, 0.0001, "semifinal con su skill normal")


func test_corrupt_store_falls_back_to_empty() -> void:
	var path := _store_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("no es json")
	f.close()
	var s := TournamentStore.new(path)
	check(not s.has_active_run(), "sin run")
	check(s.is_unlocked(1, "bronze"), "Bronce abierto")
