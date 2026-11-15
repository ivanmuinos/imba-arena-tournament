extends TestBase
## Efectos de hechizos: chispas estiradas, humo de verdad (no puntos brillantes), destello de impacto y el círculo de
## runas bajo quien castea.


func _fx() -> Array:
	var world := ArenaWorld.new()
	tree.root.add_child(world)
	world.setup(GameMap.create("test"))
	var fx := FxManager.new()
	tree.root.add_child(fx)
	fx.setup(world)
	return [fx, world]


func _emitting(pool: Array) -> int:
	return pool.filter(func(s): return (s.node as CPUParticles3D).emitting).size()


func test_textures_for_flare_and_smoke_are_soft_sprites() -> void:
	for tex in [Textures.flare(), Textures.smoke_puff(), Textures.spark()]:
		var img: Image = tex.get_image()
		check(img.get_pixel(img.get_width() / 2, img.get_height() / 2).a > 0.6, "centro visible")
		check(img.get_pixel(0, 0).a < 0.02, "esquinas transparentes: sin borde cuadrado")


func test_sparks_are_streaks_along_their_flight_and_smoke_is_not_additive() -> void:
	var a := _fx()
	var fx: FxManager = a[0]
	fx.sparks(Vector3(0, 1, 0), 10, 8.0, Color.WHITE, 0.4)
	eq(_emitting(fx._spark_pool), 1, "las chispas usan su propio grupo de partículas")
	var sp: CPUParticles3D = fx._spark_pool[0].node
	check(sp.get_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY), "estiradas en la dirección en que vuelan")
	fx.smoke(Vector3(0, 1, 0), 4, 1.0, Color(0.2, 0.2, 0.2), 1.0)
	eq(_emitting(fx._smoke_pool), 1, "el humo usa su propio grupo")
	var mat := ((fx._smoke_pool[0].node as CPUParticles3D).mesh as QuadMesh).material as StandardMaterial3D
	eq(mat.blend_mode, BaseMaterial3D.BLEND_MODE_MIX, "el humo tapa lo de atrás en vez de brillar")
	a[0].free()
	a[1].free()


func test_big_fire_impact_has_sparks_and_smoke_but_a_small_hit_stays_subtle() -> void:
	var a := _fx()
	var fx: FxManager = a[0]
	fx.impact("fire", Vector3(0, 1, 0), 0.42, false)
	eq(_emitting(fx._smoke_pool), 0, "un golpe chico no levanta humo")
	fx.impact("fire", Vector3(0, 1, 0), 1.2, false)
	check(_emitting(fx._spark_pool) >= 1, "una explosión tira chispas")
	check(_emitting(fx._smoke_pool) >= 1, "y deja humo")
	a[0].free()
	a[1].free()


func test_dash_dust_is_smoke_not_glowing_dots() -> void:
	var a := _fx()
	var fx: FxManager = a[0]
	fx.dash(0.0, 0.0)
	check(_emitting(fx._smoke_pool) >= 1, "el polvo al aterrizar es humo")
	a[0].free()
	a[1].free()


func test_cast_circle_fades_in_and_tracks_the_cast() -> void:
	near(UnitView.cast_circle(0.0, 0.0).alpha, 0.0, 1e-6, "arranca invisible")
	check(UnitView.cast_circle(0.1, 100.0).alpha > 0.0 and UnitView.cast_circle(0.1, 100.0).alpha < 1.0, "aparece de a poco")
	near(UnitView.cast_circle(0.5, 600.0).alpha, 1.0, 1e-6, "pleno a los 0,25 s")
	check(UnitView.cast_circle(0.0, 0.0).scale < UnitView.cast_circle(0.5, 600.0).scale, "se abre al aparecer")
	near(UnitView.cast_circle(0.7, 900.0).progress, 0.7, 1e-6, "marca cuánto falta del casteo")


func test_damage_over_time_shows_on_the_body_by_school() -> void:
	var l := DotFx.layers_for({"burn": 3000})
	check(l.burn > 0.0 and l.poison == 0.0 and l.curse == 0.0, "quemado: solo llamas")
	l = DotFx.layers_for({"poison": 3000, "corruption": 8000})
	check(l.poison > 0.0 and l.curse > 0.0, "veneno y maldición a la vez")
	var one: float = DotFx.layers_for({"corruption": 8000}).curse
	var three: float = DotFx.layers_for({"corruption": 8000, "agony": 8000, "soulrot": 8000}).curse
	check(three > one, "cada maldición suma: la Putrefacción es la más densa")
	check(three <= 2.0, "con un tope")
	var cover_one := DotFx.amount_for("curse", one, 1.0) * pow(DotFx.size_for("curse", one), 2.0)
	var cover_three := DotFx.amount_for("curse", three, 1.0) * pow(DotFx.size_for("curse", three), 2.0)
	check(DotFx.size_for("curse", three) < DotFx.size_for("curse", one), "apiladas, cada sombra es más chica")
	check(cover_three < cover_one * 1.4, "y en total no tapan al personaje")
	var dead := DotFx.layers_for({"burn": 3000, "agony": 8000}, false)
	check(dead.burn == 0.0 and dead.curse == 0.0, "un muerto no arde")


func test_dot_layers_scale_with_quality_but_never_vanish() -> void:
	var alta := DotFx.amount_for("burn", 1.0, 1.0)
	var baja := DotFx.amount_for("burn", 1.0, 0.3)
	check(alta > baja, "menos partículas en calidad baja")
	check(baja >= 2, "pero se siguen viendo")
	eq(DotFx.amount_for("burn", 0.0, 1.0), 0, "apagada no emite")


func test_dot_fx_turns_layers_on_and_off() -> void:
	var d := DotFx.new()
	tree.root.add_child(d)
	d.sync({"burn": 3000}, true)
	check(d.is_on("burn"), "arde mientras dura la quemadura")
	check(not d.is_on("curse"), "sin maldiciones no hay sombras")
	d.sync({}, true)
	check(not d.is_on("burn"), "se apaga al terminar")
	d.sync({"burn": 3000}, false)
	check(not d.is_on("burn"), "ni al morir")
	d.free()


func test_a_shot_turns_its_caster_toward_where_it_flies() -> void:
	var v := UnitView.new()
	v.entry = {"cls": "mage"}
	v.facing_override = 0.0  # looking where the camera looks
	v.face_cast(PI / 2.0)
	check(is_equal_approx(v.facing(), PI / 2.0), "mira hacia donde sale el disparo")
	var hand := v.hand_position() - v.position
	check(hand.x > 0.3, "la mano queda delante, del lado del disparo, no detrás")
	v._cast_face_t = 0.0
	check(is_equal_approx(v.facing(), 0.0), "después vuelve a seguir la cámara")
	v.free()


func test_a_fresh_spell_has_no_tail_behind_its_caster() -> void:
	near(FxManager.tail_scale(0.0, 5.6), 0.001, 0.0001, "al salir de la mano no tiene cola")
	near(FxManager.tail_scale(2.8, 5.6), 0.5, 0.001, "crece con lo que voló")
	eq(FxManager.tail_scale(20.0, 5.6), 1.0, "y se queda en su largo")
	# the drawn tail (length * scale * stretch) never reaches back past the hand
	var stretch := 2.5
	var flown_world := 3.0
	check(5.6 * FxManager.tail_scale(flown_world / stretch, 5.6) * stretch <= flown_world + 0.001, "la cola no pasa la mano")


func test_a_hit_squashes_the_body_and_it_bounces_back() -> void:
	var s0 := UnitView.squash(0.0, 0.15)
	check(s0.x < 1.0 and s0.y > 1.0, "al golpe se aplasta y se ensancha")
	check(UnitView.squash(0.0, 0.26).x < s0.x, "un crítico aplasta más")
	var bounced := false
	var t := 0.0
	while t < UnitView.SQUASH_S:
		if UnitView.squash(t, 0.15).x > 1.0:
			bounced = true
		t += 0.01
	check(bounced, "rebota: se estira un poco después de aplastarse")
	eq(UnitView.squash(UnitView.SQUASH_S, 0.15), Vector2.ONE, "y vuelve a su forma")


func test_every_magic_school_has_its_own_impact_sound() -> void:
	for school in ["fire", "frost", "arcane", "shadow", "holy", "nature"]:
		var ev := AudioBank.spell_hit(school)
		check(ev != "hitSpell" and AudioBank.LAYERS.has(ev), "%s suena distinto al golpear" % school)
		for layer in AudioBank.LAYERS[ev]:
			check(AudioBank.SAMPLE_GROUPS.has(layer[0]), "%s usa grabaciones que existen" % ev)
	eq(AudioBank.spell_hit("physical"), "hitSpell", "una escuela sin sonido propio usa el genérico")


func test_weapon_blows_are_told_apart_from_shots_and_spells() -> void:
	check(AudioBank.is_weapon("warrior", "strike"), "el Golpe del Guerrero es un arma")
	check(AudioBank.is_weapon("paladin", "crusader"), "el Cruzado del Paladín también, aunque sea sagrado")
	check(not AudioBank.is_weapon("hunter", "shot"), "un disparo no")
	check(not AudioBank.is_weapon("mage", "fireball"), "un hechizo no")
	check(not AudioBank.is_weapon("warrior", "nada"), "lo desconocido no")
	for layer in AudioBank.LAYERS["hitBlade"]:
		check(AudioBank.SAMPLE_GROUPS.has(layer[0]), "el golpe de filo usa grabaciones que existen")


func test_weapon_sparks_fly_out_the_far_side() -> void:
	var d := FxManager.spray_dir(Vector2(0, 0), Vector2(0, 2))
	check(d.z > 0.8 and d.y > 0.0, "salen para el lado opuesto al atacante y un poco hacia arriba")
	d = FxManager.spray_dir(Vector2(5, 0), Vector2(2, 0))
	check(d.x < -0.8, "desde cualquier lado")
	eq(FxManager.spray_dir(Vector2.ONE, Vector2.ONE), Vector3.UP, "encima del objetivo, hacia arriba")


func test_hit_pause_only_for_blows_that_involve_me() -> void:
	eq(MatchView.hit_pause_ms("hit", true, 1, 2, 1), 60.0, "mi crítico frena la imagen")
	eq(MatchView.hit_pause_ms("hit", true, 2, 1, 1), 60.0, "un crítico que recibo también")
	eq(MatchView.hit_pause_ms("hit", false, 1, 2, 1), 0.0, "un golpe común no")
	eq(MatchView.hit_pause_ms("hit", true, 3, 4, 1), 0.0, "el crítico de otros no: en un 3v3 tartamudearía")
	check(MatchView.hit_pause_ms("death", false, 1, 2, 1) > 60.0, "matar pesa más que un crítico")
	check(MatchView.hit_pause_ms("death", false, 2, 1, 1) > 0.0, "morir también")
	eq(MatchView.hit_pause_ms("death", false, 3, 4, 1), 0.0, "las muertes ajenas no")
	eq(MatchView.hit_pause_ms("hit", true, 1, 2, -1), 0.0, "espectando sin unidad propia, nunca")


func test_freezing_holds_particles_and_lets_them_go() -> void:
	var v := UnitView.new()
	v.entry = {"cls": "mage"}
	tree.root.add_child(v)
	v._dots.sync({"burn": 3000}, true)
	check(not v._dots.get_children().is_empty(), "tiene partículas para congelar")
	v.freeze(true)
	for c in v._dots.get_children():
		eq((c as CPUParticles3D).speed_scale, 0.0, "las partículas quedan quietas")
	v.freeze(false)
	for c in v._dots.get_children():
		eq((c as CPUParticles3D).speed_scale, 1.0, "y siguen")
	v.free()


func test_shots_land_with_their_own_sound() -> void:
	eq(AudioBank.shot_hit("shot"), "hitArrow", "la flecha del Cazador")
	eq(AudioBank.shot_hit("awp"), "hitBullet", "la bala del CT")
	eq(AudioBank.shot_hit("golazo"), "hitBall", "el pelotazo del Crack")
	eq(AudioBank.shot_hit("fireball"), "", "un hechizo no es un disparo")
	eq(AudioBank.shot_hit("strike"), "", "un golpe de arma tampoco")
	for ab in AudioBank.SHOT_HIT:
		var ev: String = AudioBank.SHOT_HIT[ab]
		check(SpellSchools.school_of(ab) == "physical", "%s es físico: pega con chispas, no con magia" % ab)
		for layer in AudioBank.LAYERS[ev]:
			check(AudioBank.SAMPLE_GROUPS.has(layer[0]), "%s usa grabaciones que existen" % ev)


func test_big_heals_weigh_more_than_ticks() -> void:
	eq(MatchView.heal_weight(150.0, 600.0), 1.0, "un cuarto de la vida es una cura grande")
	check(MatchView.heal_weight(20.0, 600.0) < 0.15, "un tic de renovar es chico")
	eq(MatchView.heal_weight(900.0, 600.0), 1.0, "con tope")
	eq(MatchView.heal_weight(10.0, 0.0), 1.0, "sin vida máxima no se rompe")


func test_a_control_landing_on_others_is_heard() -> void:
	check(AudioBank.LAYERS.has("ccLand"), "suena cuando el control le cae a otro")
	for layer in AudioBank.LAYERS["ccLand"]:
		check(AudioBank.SAMPLE_GROUPS.has(layer[0]), "con grabaciones que existen")
