extends TestBase
## Class companions (visual only): data per class and specialization, where they walk, when they jump back to the
## owner, and that they follow the owner's visibility (stealth, out of sight, death).


func test_every_class_has_a_companion_and_the_mage_one_per_spec() -> void:
	for cls in GameData.classes:
		var d := CompanionView.def_for(cls)
		check(not d.is_empty(), "%s tiene compañero" % cls)
		check(str(d.get("name", "")) != "", "%s: tiene nombre" % cls)
		if d.has("model"):
			check(ResourceLoader.exists(CompanionView.MODELS % str(d.model)), "%s: existe %s" % [cls, d.model])
	eq(CompanionView.def_for("mage", "fire").name, "Fénix", "Fuego: fénix")
	eq(CompanionView.def_for("mage", "frost").name, "Elemental de escarcha", "Escarcha: elemental")
	eq(CompanionView.def_for("warlock").name, "Diablillo vil", "brujo: demonio")
	eq(CompanionView.def_for("nadie"), {}, "clase desconocida: ninguno")


func test_companions_are_on_unless_turned_off() -> void:
	var st := SettingsStore.new()
	eq(st.get_value("companions"), true, "por defecto se muestran")
	eq(st.set_value("companions", false), false, "se pueden ocultar")
	eq(st.set_value("companions", "basura"), true, "un valor inválido vuelve a mostrarlos")


func test_walks_beside_the_owner_and_flyers_slightly_ahead() -> void:
	# facing +Z (rot 0): right is -X in the views' convention (sin rot, cos rot)
	var g := CompanionView.follow_point(Vector2.ZERO, 0.0)
	near(absf(g.x), CompanionView.SIDE, 0.001, "al costado")
	near(g.y, -CompanionView.BACK, 0.001, "un poco atrás")
	var f := CompanionView.follow_point(Vector2.ZERO, 0.0, true)
	check(f.y > 0.0, "el que vuela va un poco adelante (no tapa al jugador desde la cámara)")
	var turned := CompanionView.follow_point(Vector2(5, 5), PI)
	near(turned.distance_to(Vector2(5, 5)), g.length(), 0.001, "gira con el dueño")
	var running := CompanionView.follow_point(Vector2.ZERO, 0.0, false, Vector2(0, 7))
	check(running.y > g.y + 1.5, "corriendo, el objetivo se adelanta para no quedar atrás")


func test_reappears_next_to_the_owner_after_a_blink() -> void:
	check(not CompanionView.should_snap(Vector2.ZERO, Vector2(3, 0)), "3 m: lo alcanza caminando")
	check(CompanionView.should_snap(Vector2.ZERO, Vector2(12, 0)), "12 m (Traslación, Retirada): aparece al lado")


func test_follows_owner_visibility_and_fades_on_death() -> void:
	var c := CompanionView.new()
	c.setup(CompanionView.def_for("hunter"), Color.RED, null)
	var owner := Vector3(10, 0, 4)
	c.track(0.016, 0.0, owner, 0.0, Vector2.ZERO, true, true, 0.0)
	check(c.visible, "visible con su dueño")
	var spot := Vector2(c.position.x, c.position.z)
	near(spot.distance_to(CompanionView.follow_point(Vector2(10, 4), 0.0)), 0.0, 0.01, "aparece directo en su lugar")
	c.track(0.016, 0.1, owner, 0.0, Vector2.ZERO, false, true, 0.0)
	check(not c.visible, "se oculta con el dueño (sigilo, fuera de visión)")
	c.track(0.016, 0.2, Vector3(-20, 0, 0), 0.0, Vector2.ZERO, true, true, 0.0)
	near(Vector2(c.position.x, c.position.z).distance_to(CompanionView.follow_point(Vector2(-20, 0), 0.0)), 0.0, 0.01, "al volver a verse aparece al lado, no cruza el mapa")
	for i in 30:
		c.track(0.05, 0.3 + i * 0.05, Vector3(-20, 0, 0), 0.0, Vector2.ZERO, true, false, 0.0)
	check(not c.visible, "al morir el dueño se desvanece")
	c.track(0.016, 2.0, Vector3(-20, 0, 0), 0.0, Vector2.ZERO, true, true, 0.0)
	check(c.visible, "vuelve con el dueño")
	c.free()


func test_every_companion_builds_headless() -> void:
	for pair in [["hunter", ""], ["warrior", ""], ["rogue", ""], ["priest", ""], ["mage", "fire"], ["mage", "frost"], ["warlock", ""]]:
		var c := CompanionView.new()
		c.setup(CompanionView.def_for(pair[0], pair[1]), Color.BLUE, null)
		c.track(0.016, 0.0, Vector3.ZERO, 0.0, Vector2(3, 0), true, true, 0.0)
		check(c.get_child_count() > 0, "%s %s: tiene modelo" % pair)
		c.free()


func test_reactions_move_it_and_settle_back() -> void:
	var hop := CompanionView.reaction_offset("cast", CompanionView.REACT_S.cast * 0.5)
	check(hop.y > 0.2, "al lanzar un hechizo salta")
	check(CompanionView.reaction_offset("pounce", CompanionView.REACT_S.pounce * 0.5).x > 0.3, "al golpear el dueño se abalanza hacia adelante")
	check(CompanionView.reaction_offset("hurt", CompanionView.REACT_S.hurt * 0.5).x < 0.0, "si le pegan al dueño retrocede")
	check(absf(CompanionView.reaction_offset("cast", CompanionView.REACT_S.cast * 0.5, true).z) > 1.0, "el que vuela gira")
	eq(CompanionView.reaction_offset("cast", 5.0), Vector4(0, 0, 0, 1), "terminada, sin desplazamiento")
	eq(CompanionView.reaction_offset("nada", 0.1), Vector4(0, 0, 0, 1), "reacción desconocida: nada")


func test_react_plays_once_then_returns_to_its_spot() -> void:
	var c := CompanionView.new()
	c.setup(CompanionView.def_for("hunter"), Color.RED, null)
	c.track(0.016, 0.0, Vector3.ZERO, 0.0, Vector2.ZERO, true, true, 0.0)
	var rest := c.position
	c.react("cast")
	c.track(0.2, 0.2, Vector3.ZERO, 0.0, Vector2.ZERO, true, true, 0.0)
	check(c.position.y > rest.y + 0.1, "en el aire a mitad del salto")
	for i in 10:
		c.track(0.1, 0.3 + i * 0.1, Vector3.ZERO, 0.0, Vector2.ZERO, true, true, 0.0)
	near(c.position.distance_to(rest), 0.0, 0.01, "vuelve a su lugar, sin quedar corrido")
	c.react("pounce")
	c.track(0.15, 1.5, Vector3.ZERO, 0.0, Vector2.ZERO, true, true, 0.0)
	var lunged := c.position
	c.react("pounce")  # demasiado pronto: no reinicia
	c.track(0.25, 1.75, Vector3.ZERO, 0.0, Vector2.ZERO, true, true, 0.0)
	near(Vector2(c.position.x, c.position.z).distance_to(Vector2(rest.x, rest.z)), 0.0, 0.05, "un segundo golpe enseguida no la repite")
	check(Vector2(lunged.x, lunged.z).distance_to(Vector2(rest.x, rest.z)) > 0.3, "el primero sí se abalanzó")
	c.free()


func test_no_reactions_while_hidden_or_dead() -> void:
	var c := CompanionView.new()
	c.setup(CompanionView.def_for("warlock"), Color.RED, null)
	c.track(0.016, 0.0, Vector3.ZERO, 0.0, Vector2.ZERO, false, true, 0.0)
	c.react("hurt")
	c.track(0.1, 0.1, Vector3.ZERO, 0.0, Vector2.ZERO, true, true, 0.0)
	near(Vector2(c.position.x, c.position.z).distance_to(CompanionView.follow_point(Vector2.ZERO, 0.0, true)), 0.0, 0.01, "oculto (sigilo) no reacciona")
	c.free()


func test_companions_are_switched_off_for_now() -> void:
	check(not CompanionView.enabled(), "las mascotas están apagadas hasta que rindan")
