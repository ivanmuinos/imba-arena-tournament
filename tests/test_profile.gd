extends TestBase
## Profile (S7): per-class stats, cups, 18 challenges, rewards, equipment and the account level.


func _path() -> String:
	var path := "user://test_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	return path


func _stats(dmg := 0, kills := 0, deaths := 0, heal := 0) -> Dictionary:
	return {"id": 1, "dmg": dmg, "kills": kills, "deaths": deaths, "heal": heal}


func test_data_has_18_challenges_3_per_playable_class_with_valid_rewards() -> void:
	var list := Challenges.all()
	eq(list.size(), 18, "18 desafíos")
	var per := {}
	var ids := {}
	for c in list:
		per[c.cls] = int(per.get(c.cls, 0)) + 1
		ids[c.id] = true
		check(GameData.playable(str(c.cls)), "clase jugable: " + str(c.cls))
		check(Challenges.item(str(c.reward)).has("id"), "recompensa existente: " + str(c.reward))
		check(["total", "match"].has(str(c.kind)), "tipo válido")
		if c.kind == "total":
			check(["matches", "wins", "dmg", "kills", "heal"].has(str(c.stat)), "solo campos de end.stats: " + str(c.stat))
			check(int(c.goal) > 0, "meta positiva")
		else:
			for k in c.when:
				check(["win", "deaths_max", "dmg_min", "kills_min", "heal_min"].has(k), "condición válida: " + k)
	eq(ids.size(), 18, "ids únicos")
	eq(per.size(), 6, "6 clases")
	for cls in per:
		eq(per[cls], 3, "3 desafíos de " + cls)


func test_every_level_up_has_a_reward_and_items_are_well_formed() -> void:
	var max_level := ProfileStore.max_level()
	for lv in range(2, max_level + 1):
		check(Challenges.item(ProfileStore.level_reward(lv)).has("id"), "recompensa en el nivel %d" % lv)
	for it in Challenges.items():
		check(["title", "ring", "recolor"].has(str(it.kind)), "tipo de cosmético: " + str(it.kind))
		check(str(it.name) != "", "con nombre")
		if it.kind == "recolor":
			check(GameData.playable(str(it.cls)), "recoloreado de clase jugable")
		if it.kind == "ring":
			check(str(it.value).begins_with("#"), "color de anillo")


func test_level_curve_is_data_driven_and_about_ten_levels_in_two_hours() -> void:
	eq(ProfileStore.level_for_xp(0), 1, "arranca en 1")
	eq(ProfileStore.xp_to_reach(1), 0, "nivel 1 sin XP")
	check(ProfileStore.xp_to_reach(2) > 0, "el nivel 2 pide XP")
	var prev := 0
	for lv in range(2, ProfileStore.max_level() + 1):
		var need := ProfileStore.xp_to_reach(lv)
		check(need > prev, "la curva crece en el nivel %d" % lv)
		eq(ProfileStore.level_for_xp(need), lv, "justo en el umbral %d" % lv)
		eq(ProfileStore.level_for_xp(need - 1), lv - 1, "un punto antes")
		prev = need
	eq(ProfileStore.level_for_xp(99999999), ProfileStore.max_level(), "tope de nivel")
	# 2 h at 3.6 min per match = 33 matches; torneo con 2 de cada 3 ganadas
	var xp := 0.0
	for i in 33:
		xp += ProfileStore.xp_for("tournament", i % 3 != 2)
	var lv := ProfileStore.level_for_xp(int(xp))
	check(lv >= 9 and lv <= 11, "~10 niveles en 2 horas (nivel %d con %d XP)" % [lv, int(xp)])


func test_xp_sources_win_more_and_practice_gives_none() -> void:
	for src in ["bot", "tournament", "online"]:
		check(ProfileStore.xp_for(src, true) > ProfileStore.xp_for(src, false), "ganar da más: " + src)
		check(ProfileStore.xp_for(src, false) > 0, "perder también da XP: " + src)
	eq(ProfileStore.xp_for("practice", true), 0, "los muñecos no dan XP")
	eq(ProfileStore.xp_for("???", true), 0, "origen desconocido: nada")
	var s := ProfileStore.new(_path())
	var res := s.record_match("practice", "mage", true, _stats(5000, 3, 0, 0), 2)
	eq(res.xp, 0, "sin XP")
	eq(s.xp, 0, "perfil sin cambios")
	eq(s.class_stats("mage").matches, 0, "ni estadísticas")
	check(s.challenge_state("mage_1").progress == 0, "ni desafíos")


func test_record_match_accumulates_class_stats_and_level_ups_unlock_rewards() -> void:
	var path := _path()
	var s := ProfileStore.new(path)
	var res := s.record_match("bot", "mage", true, _stats(900, 1, 0, 0), 1)
	eq(res.xp, ProfileStore.xp_for("bot", true), "XP de una victoria contra bot")
	eq(s.class_stats("mage").matches, 1, "una partida")
	eq(s.class_stats("mage").wins, 1, "una victoria")
	eq(s.class_stats("mage").dmg, 900, "daño")
	eq(s.class_stats("rogue").matches, 0, "otras clases intactas")
	var levels := 0
	var granted: Array = []
	for i in 12:
		var r := s.record_match("tournament", "mage", true, _stats(100), 2)
		for up in r.level_ups:
			levels += 1
			granted.append(up.reward)
			check(s.is_unlocked(str(up.reward)), "la recompensa queda desbloqueada")
	check(levels >= 3, "subió de nivel varias veces")
	eq(s.level(), ProfileStore.level_for_xp(s.xp), "el nivel sale de la XP")
	eq(granted.size(), levels, "una recompensa por nivel")
	var back := ProfileStore.new(path)
	eq(back.xp, s.xp, "la XP se guarda")
	eq(back.class_stats("mage").matches, 13, "estadísticas guardadas")
	check(back.is_unlocked(granted[0]), "desbloqueos guardados")


func test_total_challenge_progress_completes_and_rewards_once() -> void:
	var s := ProfileStore.new(_path())
	var done_at := -1
	for i in 4:
		var r := s.record_match("bot", "warrior", false, _stats(10), 1)
		if r.completed.has("warrior_1") and done_at < 0:
			done_at = i + 1
	eq(done_at, 3, "'Primeros pasos' a la tercera partida")
	check(s.is_unlocked("title_warrior"), "recompensa: título")
	eq(s.challenge_state("warrior_1").progress, 3, "el progreso se frena en la meta")
	check(s.challenge_state("warrior_1").done, "completado")
	var again := s.record_match("bot", "warrior", true, _stats(10), 1)
	check(not again.completed.has("warrior_1"), "no se completa dos veces")
	var other := s.record_match("bot", "mage", true, _stats(10), 1)
	check(s.challenge_state("mage_1").progress == 1, "cada clase tiene su progreso")
	check(not s.challenge_state("warrior_2").done, "otros desafíos siguen")


func test_match_challenge_needs_all_its_conditions() -> void:
	var s := ProfileStore.new(_path())
	var r := s.record_match("bot", "mage", true, _stats(300, 1, 1, 0), 1)  # won but died
	check(not r.completed.has("mage_3"), "murió: no cuenta")
	r = s.record_match("bot", "mage", false, _stats(300, 0, 0, 0), 1)  # lost without dying (e.g. timeout)
	check(not r.completed.has("mage_3"), "perdió: no cuenta")
	r = s.record_match("bot", "mage", true, _stats(300, 1, 0, 0), 1)
	check(r.completed.has("mage_3"), "ganó sin morir")
	check(s.is_unlocked("recolor_mage"), "recoloreado de Mago")
	var rogue := ProfileStore.new(_path())
	var r1 := rogue.record_match("bot", "rogue", false, _stats(699), 1)
	check(not r1.completed.has("rogue_2"), "699 no alcanza")
	var r2 := rogue.record_match("bot", "rogue", false, _stats(700), 1)
	check(r2.completed.has("rogue_2"), "700 en una partida")


func test_first_title_comes_before_twelve_minutes() -> void:
	# 3 matches x 3.6 min = 10.8 min: the first class challenge must be done by the third match of any class
	for cls in GameData.playable_ids():
		var s := ProfileStore.new(_path())
		var got := false
		for i in 3:
			if s.record_match("bot", cls, false, _stats(), 1).completed.has("%s_1" % cls):
				got = true
		check(got, "primer título de " + cls + " en 3 partidas")
		check(s.unlocked.any(func(id): return str(id).begins_with("title_")), "es un título")


func test_challenges_ignore_non_class_matches_and_bad_numbers() -> void:
	var s := ProfileStore.new(_path())
	s.record_match("bot", "not-a-class", true, _stats(10), 1)
	eq(s.xp, 0, "clase desconocida: nada")
	s.record_match("bot", "mage", true, {"dmg": -50, "kills": "x", "deaths": 1e12, "heal": null}, 1)
	var cs := s.class_stats("mage")
	eq(cs.dmg, 0, "daño negativo ignorado")
	eq(cs.kills, 0, "texto ignorado")
	check(cs.deaths < 100000, "valor desmedido acotado")


func test_cups_and_equipment_are_validated_and_saved() -> void:
	var path := _path()
	var s := ProfileStore.new(path)
	s.record_cup(2, "bronze")
	s.record_cup(2, "bronze")
	eq(s.cups("2:bronze"), 2, "copas")
	s.unlocked.append("title_mage")
	check(s.equip("title", "title_mage"), "equipa un título desbloqueado")
	check(not s.equip("title", "title_priest"), "no equipa algo bloqueado")
	check(not s.equip("ring", "title_mage"), "ni en la ranura equivocada")
	s.unlocked.append("recolor_mage")
	check(s.equip("recolor", "recolor_mage"), "recoloreado")
	eq(s.equipped.recolor.mage, "recolor_mage", "queda por clase")
	s.save()
	var back := ProfileStore.new(path)
	eq(back.cups("2:bronze"), 2, "copas guardadas")
	eq(back.equipped.title, "title_mage", "equipado guardado")
	check(not back.equip("title", "no_existe"), "id desconocido")
	check(back.unequip("title"), "desequipa")
	eq(back.equipped.title, "", "sin título")


func test_corrupt_or_tampered_profile_is_sanitized() -> void:
	var path := _path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"v": 1, "xp": -5, "classes": {"mage": {"matches": -2, "dmg": "x"}, "fake": {"matches": 9}}, "unlocked": ["title_mage", "nope", 7], "equipped": {"title": "title_priest", "ring": "", "recolor": {"mage": "title_mage"}}}))
	f.close()
	var s := ProfileStore.new(path)
	eq(s.xp, 0, "XP negativa")
	eq(s.class_stats("mage").matches, 0, "estadística negativa")
	check(not s.class_stats("fake").has("x") and s.class_stats("fake").matches == 0, "clase inventada ignorada")
	eq(s.unlocked, ["title_mage"], "solo ids conocidos")
	eq(s.equipped.title, "", "no se equipa lo que no tenés")
	check(not s.equipped.recolor.has("mage"), "recoloreado inválido descartado")
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("{{{")
	junk.close()
	eq(ProfileStore.new(path).xp, 0, "archivo roto: perfil vacío")


func test_save_is_atomic() -> void:
	var path := _path()
	var s := ProfileStore.new(path)
	s.record_match("bot", "mage", true, _stats(1), 1)
	check(FileAccess.file_exists(path), "guardado")
	check(not FileAccess.file_exists(path + ".tmp"), "sin temporal")


func test_xp_progress_for_the_hub() -> void:
	var s := ProfileStore.new(_path())
	var p := s.progress()
	eq(p.level, 1, "nivel 1")
	eq(p.into, 0, "0 XP en el nivel")
	eq(p.need, ProfileStore.xp_to_reach(2), "falta lo del nivel 2")
	s.xp = ProfileStore.xp_to_reach(2) + 10
	p = s.progress()
	eq(p.level, 2, "nivel 2")
	eq(p.into, 10, "10 dentro del nivel")
	s.xp = ProfileStore.xp_to_reach(ProfileStore.max_level()) + 500
	check(s.progress().maxed, "nivel máximo")
