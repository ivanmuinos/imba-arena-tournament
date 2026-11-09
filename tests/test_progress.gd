extends TestBase
## Account progression (docs/progresion-talentos-sinergias.md): XP per match, champion levels, talent rows.


func test_xp_per_match_follows_the_design() -> void:
	eq(Progress.match_xp(true, 0, 0, false, false), 100, "ganar: 100")
	eq(Progress.match_xp(false, 0, 0, false, false), 40, "perder: 40")
	eq(Progress.match_xp(false, 250, 50, false, false), 70, "+1 por cada 10 de daño o curación")
	eq(Progress.match_xp(false, 99999, 0, false, false), 100, "el desempeño suma hasta 60")
	eq(Progress.match_xp(true, 0, 0, true, false), 200, "primera victoria del día: doble")
	eq(Progress.match_xp(false, 0, 0, true, false), 40, "una derrota no usa la primera victoria")
	eq(Progress.match_xp(true, 0, 0, false, true), 50, "contra bots: la mitad")


func test_levels_need_more_xp_as_they_go_and_stop_at_20() -> void:
	eq(Progress.xp_to_next(1), 400, "1 -> 2: unas 4 partidas")
	eq(Progress.xp_to_next(19), 1200, "19 -> 20: unas 12 partidas")
	check(Progress.xp_to_next(10) > Progress.xp_to_next(9), "cada nivel cuesta más")
	eq(Progress.xp_to_next(20), 0, "el 20 es el máximo")
	eq(Progress.add_xp({"level": 1, "xp": 350}, 100), {"level": 2, "xp": 50}, "sube y guarda el resto")
	eq(int(Progress.add_xp({"level": 1, "xp": 0}, 100000).level), 20, "mucha XP de golpe llega al 20 y no más")
	eq(Progress.add_xp({"level": 99, "xp": -5}, 0), {"level": 20, "xp": 0}, "valores fuera de rango se corrigen")


func test_talent_rows_and_rank_points_open_with_the_level() -> void:
	eq(Progress.talent_rows(4), 0, "nivel 4: sin talentos")
	eq(Progress.talent_rows(5), 1, "nivel 5: fila 1")
	eq(Progress.talent_rows(14), 2, "nivel 14: dos filas")
	eq(Progress.talent_rows(20), 4, "nivel 20: las cuatro")
	eq(Progress.rank_points(1), 0, "nivel 1: sin rangos")
	eq(Progress.rank_points(20), 10, "nivel 20: 10 rangos para repartir")


func test_store_saves_levels_per_champion_and_the_first_win_of_the_day() -> void:
	var path := "user://test_progress.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var st := ProgressStore.new(path)
	eq(st.level("mage"), 1, "un campeón nuevo arranca en 1")
	var r := st.award("mage", true, 0, 0, false, "2026-11-03")
	eq(r.gain, 200, "primera victoria del día: doble")
	check(r.first_win, "lo informa")
	eq(st.award("mage", true, 0, 0, false, "2026-11-03").gain, 100, "la segunda del día ya no")
	eq(st.award("mage", true, 0, 0, false, "2026-11-04").gain, 200, "al otro día vuelve")
	var again := ProgressStore.new(path)
	eq(again.level("mage"), 2, "se guarda: 500 XP = nivel 2")
	eq(again.level("warrior"), 1, "cada campeón tiene su nivel")
	eq(st.award("nadie", true, 0, 0, false, "x"), {}, "una clase que no existe no suma nada")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_end_screen_shows_the_level_up() -> void:
	var end := EndScreen.new()
	TestBase.tree.root.add_child(end)
	end.show_progress({"cls": "mage", "gain": 296, "level_before": 4, "level_after": 5, "xp": 120, "xp_next": 450, "first_win": true, "vs_bots": false})
	check(end._prog.visible, "se ve el panel")
	check(end._prog_title.text.contains("NIVEL 5") and end._prog_title.text.contains("SUBISTE"), "nivel nuevo")
	check(end._prog_gain.text.contains("+296 XP") and not end._prog_gain.text.contains("talentos"), "XP, sin hablar de talentos mientras estén apagados")
	end.show_progress({})
	check(not end._prog.visible, "sin datos, se oculta")
	end.free()
