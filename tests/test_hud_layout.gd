extends TestBase


func test_ability_help_explains_target_and_ground_confirmation() -> void:
	check(UiTip.usage_line({"id": "meteor"}, "R").contains("clic izquierdo"), "zona requiere confirmar")
	check(UiTip.usage_line({"id": "heal"}, "2").contains("vos"), "sanación sin aliado va a vos")
	check(UiTip.usage_line({"id": "strike"}, "1").contains("activar"), "autoataque es un interruptor")
	check(UiTip.usage_line({"id": "fireball"}, "1").contains("enemigo"), "hechizo requiere objetivo")


func test_spectator_keeps_choice_cycles_and_falls_back_without_enemies() -> void:
	var units := [{"id": 1, "team": "red", "alive": false}, {"id": 2, "team": "red", "alive": true}, {"id": 3, "team": "red", "alive": true}, {"id": 4, "team": "blue", "alive": true}]
	eq(MatchView.spectate_id(units, 1, "red", -1), 2, "primer aliado vivo")
	eq(MatchView.spectate_id(units, 1, "red", 3), 3, "mantiene elección")
	eq(MatchView.spectate_id(units, 1, "red", 3, true), 2, "Tab vuelve al primero")
	units[1].alive = false
	eq(MatchView.spectate_id(units, 1, "red", 2), 3, "cambia si muere")
	units[2].alive = false
	eq(MatchView.spectate_id(units, 1, "red", 3), -1, "nunca revela enemigos")
	var roster := [{"id": 2, "team": "red"}, {"id": 4, "team": "blue"}]
	eq(MatchView.spectate_id([{"id": 2, "alive": true}, {"id": 4, "alive": true}], 1, "red", -1, false, roster), 2, "snapshot real no incluye team: resolver por roster")


func test_death_presentation_resets_on_respawn() -> void:
	var hud := Hud.new()
	tree.root.add_child(hud)
	hud.set_spectator(true, "Aliado")
	check(hud._spirit.visible and hud._spectator.visible, "pantalla espiritual y ayuda")
	check(hud._spectator.text.contains("Aliado"), "nombre observado")
	hud.set_spectator(false, "")
	check(not hud._spirit.visible and not hud._spectator.visible, "vuelve a normal al revivir")
	hud.free()
## HUD scaling: layout is designed for 1280x720 and scaled to the window.


func test_ui_scale_follows_window_and_is_clamped() -> void:
	near(Hud.ui_scale_for(Vector2(1280, 720)), 1.0, 1e-6, "tamaño de diseño")
	near(Hud.ui_scale_for(Vector2(1600, 900)), 1.25, 1e-6, "1600x900")
	near(Hud.ui_scale_for(Vector2(800, 450)), 0.625, 1e-6, "800x450")
	near(Hud.ui_scale_for(Vector2(3840, 2160)), 2.0, 1e-6, "máximo")
	near(Hud.ui_scale_for(Vector2(300, 200)), 0.5, 1e-6, "mínimo")
	near(Hud.ui_scale_for(Vector2(2000, 720)), 1.0, 1e-6, "manda el lado más chico")


func test_screen_to_ui_divides_by_scale() -> void:
	eq(Hud.screen_to_ui(Vector2(800, 450), 2.0), Vector2(400, 225), "coordenadas de pantalla -> HUD")


func test_menu_content_stays_1280_wide_and_centered_on_ultrawide() -> void:
	var b := MenuScreen.content_box(Vector2(2560, 1080))
	near(b.size.x, 1280.0, 1e-6, "ancho de diseño en 21:9")
	near(b.position.x, (2560.0 - 1280.0 * 1.5) / 2.0, 1e-6, "centrado (escala 1.5)")
	var c := MenuScreen.content_box(Vector2(5120, 1440))
	near(c.size.x, 1280.0, 1e-6, "ancho de diseño en 32:9")
	near(c.position.x + c.size.x * Hud.ui_scale_for(Vector2(5120, 1440)) / 2.0, 2560.0, 1e-3, "el centro del contenido es el centro de la ventana")
	var d := MenuScreen.content_box(Vector2(1600, 900))
	near(d.position.x, 0.0, 1e-6, "16:9 usa toda la ventana")
	var e := MenuScreen.content_box(Vector2(1600, 1000))
	near(e.size.x, 1280.0, 1e-6, "16:10 también")
	check(e.size.y > 720.0, "y aprovecha el alto extra")


func test_health_bar_colours_are_enemy_red_ally_green() -> void:
	check(Hud.HP_ENEMY.r > 0.8 and Hud.HP_ENEMY.g < 0.3 and Hud.HP_ENEMY.b < 0.3, "enemigos en rojo")
	check(Hud.HP_ALLY.g > Hud.HP_ALLY.r and Hud.HP_ALLY.g > Hud.HP_ALLY.b, "aliados en verde")
	var src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	check(not src.contains("TEAM_COL[r.team])\n") and not src.contains("else TEAM_COL[r.team])"), "la barra de vida ya no usa el color de equipo")


func test_cast_tracker_reports_start_complete_and_interrupt() -> void:
	var t := CastTracker.new()
	eq(t.update(null), "", "nada")
	eq(t.update({"slot": 1, "total": 1400.0, "left": 1300.0}), "start", "empieza")
	eq(t.update({"slot": 1, "total": 1400.0, "left": 900.0}), "", "sigue")
	near(t.progress(), 1.0 - 900.0 / 1400.0, 1e-6, "progreso")
	t.update({"slot": 1, "total": 1400.0, "left": 40.0})
	eq(t.update(null), "complete", "terminó")
	t.update({"slot": 2, "total": 1000.0, "left": 800.0})
	t.update({"slot": 2, "total": 1000.0, "left": 500.0})
	eq(t.update(null), "interrupted", "se cortó a la mitad")
	eq(t.update(null), "", "una sola vez")


func test_cursor_kinds_sizes_and_art() -> void:
	eq(CursorKit.kind_for("", 0.0, 0.0, false), "arrow", "sin nada: puntero")
	eq(CursorKit.kind_for("enemy", 5.0, 20.0, false), "enemy", "enemigo a tiro: espada")
	eq(CursorKit.kind_for("enemy", 25.0, 20.0, false), "enemy_far", "enemigo fuera de alcance: variante 'no puedo'")
	eq(CursorKit.kind_for("friend", 5.0, 24.0, false), "friend", "aliado: mano")
	eq(CursorKit.kind_for("friend", 30.0, 24.0, false), "friend_far", "aliado lejos")
	eq(CursorKit.kind_for("enemy", 99.0, 0.0, true), "ground", "retículo manda")
	check(CursorKit.size_for(Vector2(1280, 720)) == 26 and CursorKit.size_for(Vector2(3200, 1800)) == 52, "tamaño proporcional a la escala de la interfaz (1x y Retina)")
	check(CursorKit.size_for(Vector2(300, 200)) == 24 and CursorKit.size_for(Vector2(8000, 4000)) == 52 and CursorKit.size_for(Vector2(1600, 900)) == 33, "con piso y techo")
	for k in CursorKit.KINDS:
		var img := CursorKit.render(k, 64)
		check(img.get_width() == 64 and img.get_height() == 64, "%s: 64 px" % k)
		var opaque := 0
		for y in 64:
			for x in 64:
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
		check(opaque > 150, "%s: tiene dibujo (%d px)" % [k, opaque])
		check(CursorKit.HOTSPOT.has(k.replace("_far", "")) or CursorKit.HOTSPOT.has(k), "%s: tiene punto activo" % k)
