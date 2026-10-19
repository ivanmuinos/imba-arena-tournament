extends TestBase
## Ranked: Elo between team averages, placement, leagues, fair team split, and the local store (a match left halfway
## counts as a loss).


func test_elo_favours_the_underdog_and_placement_moves_more() -> void:
	near(Ranked.expected(1500, 1500), 0.5, 0.001, "parejos: 50%")
	check(Ranked.expected(1700, 1500) > 0.7, "200 puntos más: favorito")
	eq(Ranked.delta(1500, 1500, true, 10), 12, "ganar parejo: +12")
	eq(Ranked.delta(1500, 1500, false, 10), -12, "perder parejo: -12")
	check(Ranked.delta(1400, 1600, true, 10) > Ranked.delta(1600, 1400, true, 10), "ganarle a uno mejor da más")
	check(Ranked.delta(1500, 1500, true, 0) > Ranked.delta(1500, 1500, true, 10), "en calibración se mueve más")
	eq(Ranked.delta(3000, 1000, true, 10), 1, "aunque sea esperado, ganar suma algo")


func test_leagues_after_placement() -> void:
	eq(Ranked.league(1500, 2).id, "placement", "antes de 5 partidas: calibrando")
	check(str(Ranked.league(1500, 2).name).contains("2/5"), "muestra el progreso")
	eq(Ranked.league(1200, 5).id, "bronze", "1200: bronce")
	eq(Ranked.league(1500, 5).id, "silver", "1500: plata")
	eq(Ranked.league(1560, 9).id, "gold", "1560: oro")
	eq(Ranked.league(2400, 30).id, "gladiator", "2400: gladiador")


func test_split_teams_keeps_averages_close() -> void:
	var ps := [{"peer": 1, "mmr": 2000}, {"peer": 2, "mmr": 1000}, {"peer": 3, "mmr": 1600}, {"peer": 4, "mmr": 1400}]
	var t := Ranked.split_teams(ps, 2)
	check(t[1] != t[3] and t[1] == t[2], "2000 con 1000, 1600 con 1400")
	var six := []
	for i in 6:
		six.append({"peer": i + 1, "mmr": 1200 + i * 100})
	var t3 := Ranked.split_teams(six, 3)
	var red := six.filter(func(p): return t3[p.peer] == "red").map(func(p): return p.mmr)
	eq(red.size(), 3, "3 por equipo")
	check(absf(Ranked.average(red) - 1450.0) < 40.0, "promedios casi iguales")
	var duel := Ranked.split_teams([{"peer": 5, "mmr": 1500}, {"peer": 9, "mmr": 1700}], 1)
	check(duel[5] != duel[9], "1v1: uno de cada lado")


func test_search_window_widens_with_time() -> void:
	eq(Ranked.window(0.0), Ranked.SEARCH_WINDOW, "al principio, rivales parecidos")
	check(Ranked.window(30.0) > Ranked.window(0.0), "esperando se abre")
	eq(Ranked.window(9999.0), Ranked.SEARCH_WINDOW_MAX, "con tope")


func test_store_applies_results_and_counts_abandon_as_loss() -> void:
	var path := "user://test_ranked.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var s := RankedStore.new(path)
	eq(s.rating(2).mmr, Ranked.START, "arranca en 1500")
	s.begin(2, 1500.0, 1500.0)
	var r := s.finish(true)
	eq(r.delta, 24, "calibración: ganar parejo +24")
	eq(s.rating(2).games, 1, "una partida")
	eq(s.rating(3).games, 0, "los otros brackets no cambian")
	s.begin(3, 1500.0, 1500.0)
	var again := RankedStore.new(path)  # the game closed mid-match
	var lost := again.settle_abandoned()
	eq(lost.delta, -24, "abandonar cuenta como derrota")
	eq(again.rating(3).wins, 0, "sin victoria")
	eq(again.settle_abandoned(), {}, "una sola vez")
	check(again.merge(2, {"mmr": 1800, "games": 7, "wins": 6}), "Steam con más partidas manda")
	check(not again.merge(2, {"mmr": 900, "games": 3, "wins": 0}), "con menos, no")
	eq(RankedStore.new(path).rating(2).mmr, 1800, "queda guardado")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
