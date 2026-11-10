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
