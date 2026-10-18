extends TestBase


func test_auto_keeps_aiming_for_sixty_at_resolution_floor() -> void:
	var a := AutoQuality.new()
	var level := "media"
	for i in 4:
		level = a.feed(50, i * 1000.0, level)
	eq(level, "baja", "50 FPS sostenidos también requieren bajar efectos, no conformarse con 40")


func test_fps_measurement_uses_unscaled_unclamped_time() -> void:
	near(AutoQuality.real_delta(0.04, 4.0), 0.01, 1e-6, "benchmark acelerado no reduce calidad por un FPS falso")
	near(AutoQuality.real_delta(0.1, 1.0), 0.1, 1e-6, "10 FPS no se convierte en 20 por clamp de simulación")
## Graphics quality levels and the automatic downgrade.


func test_levels_are_ordered_and_have_all_settings() -> void:
	for lvl in ["alta", "media", "baja"]:
		var s := Quality.settings(lvl)
		for k in ["scale", "msaa", "shadows", "shadow_size", "glow", "ssao", "ssr", "volumetric_fog", "particles", "embers", "decals", "sdfgi"]:
			check(s.has(k), "%s tiene %s" % [lvl, k])
	check(Quality.settings("baja").scale <= Quality.settings("media").scale, "escala baja <= media")
	check(Quality.settings("media").particles <= Quality.settings("alta").particles, "partículas media <= alta")
	check(not Quality.settings("baja").ssao and not Quality.settings("baja").sdfgi, "baja sin SSAO/SDFGI")
	eq(Quality.settings("rarísimo"), Quality.settings("alta"), "desconocido = alta")


func test_auto_drops_after_sustained_low_fps_only() -> void:
	var a := AutoQuality.new()
	var t := 10000.0
	for i in 3:
		eq(a.feed(30, t + i * 1000.0, "alta"), "alta", "todavía no (muestra %d)" % i)
	eq(a.feed(30, t + 3000.0, "alta"), "media", "baja un nivel tras 4 s malos")


func test_auto_ignores_spikes_and_cooldown() -> void:
	var a := AutoQuality.new()
	eq(a.feed(30, 0.0, "alta"), "alta", "")
	eq(a.feed(120, 1000.0, "alta"), "alta", "")
	eq(a.feed(30, 2000.0, "alta"), "alta", "un pico no cuenta: se reinicia")
	var b := AutoQuality.new()
	var lvl := "alta"
	for i in 4:
		lvl = b.feed(20, 1000.0 * i, lvl)
	eq(lvl, "media", "bajó")
	eq(b.feed(20, 4100.0, lvl), "media", "enfriamiento: no baja otra vez enseguida")
	for i in 4:
		lvl = b.feed(20, 9000.0 + 1000.0 * i, lvl)
	eq(lvl, "baja", "después del enfriamiento baja a baja")
	for i in 6:
		lvl = b.feed(10, 20000.0 + 1000.0 * i, lvl)
	eq(lvl, "baja", "no hay nada más abajo")


func test_choice_resolution() -> void:
	eq(Quality.resolve("auto", "media"), "media", "auto usa el nivel actual")
	eq(Quality.resolve("baja", "alta"), "baja", "fijo manda")
	eq(Quality.resolve("xyz", "alta"), "alta", "inválido")


func test_auto_starts_lower_on_weak_gpus_and_on_compatibility_renderer() -> void:
	eq(Quality.initial_level(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, false), "alta", "GPU dedicada")
	eq(Quality.initial_level(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, false), "media", "integrada")
	eq(Quality.initial_level(RenderingDevice.DEVICE_TYPE_CPU, false), "baja", "software")
	eq(Quality.initial_level(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, true), "baja", "renderer de compatibilidad (sin Vulkan)")
	eq(Quality.initial_level(RenderingDevice.DEVICE_TYPE_OTHER, false), "media", "desconocida")


func test_depth_of_field_only_on_the_highest_level() -> void:
	check(Quality.settings("alta").dof, "alta: profundidad de campo")
	check(not Quality.settings("media").dof and not Quality.settings("baja").dof, "media y baja: sin DoF")


# ---------------------------------------------------------------- Retina / dynamic resolution

func test_auto_scale_follows_pixel_budget() -> void:
	near(Quality.auto_scale(Vector2i(1280, 720), "media"), 1.0, 1e-6, "720p: resolución completa")
	near(Quality.auto_scale(Vector2i(1920, 1080), "media"), 1.0, 1e-6, "1080p: resolución completa")
	var retina := Quality.auto_scale(Vector2i(3200, 1800), "media")
	check(retina < 0.85 and retina > 0.55, "Retina 3200x1800 baja la escala 3D (%.2f)" % retina)
	var big := Quality.auto_scale(Vector2i(6016, 3384), "media")
	check(big >= 0.5 and big < retina, "pantallas enormes bajan más, pero con piso 0.5 (%.2f)" % big)
	check(Quality.auto_scale(Vector2i(3200, 1800), "baja") < retina, "baja usa menos píxeles que media")
	check(Quality.auto_scale(Vector2i(3200, 1800), "alta") >= retina, "alta usa más píxeles que media")


func test_upscaler_choice() -> void:
	eq(Quality.upscaler_for("macOS", 0.7), "metalfx", "macOS escalando: MetalFX espacial")
	eq(Quality.upscaler_for("macOS", 1.0), "bilinear", "sin escalar no hace falta")
	eq(Quality.upscaler_for("Windows", 0.7), "bilinear", "Windows: bilineal (barato)")


func test_dynamic_resolution_steps_down_then_recovers() -> void:
	var a := AutoQuality.new()
	var scale := 1.0
	for i in 2:
		scale = a.step_scale(40, 1000.0 * i, scale, 1.0, 60)
	check(scale < 1.0, "dos segundos por debajo de la meta bajan la escala (%.2f)" % scale)
	var s2 := scale
	scale = a.step_scale(40, 2500.0, scale, 1.0, 60)
	eq(scale, s2, "enfriamiento entre pasos")
	var b := AutoQuality.new()
	var sc := 0.5
	for i in 4:
		sc = b.step_scale(20, 10000.0 + 4000.0 * i, sc, 1.0, 60)
	near(sc, AutoQuality.MIN_SCALE, 1e-6, "piso de escala")
	var c := AutoQuality.new()
	var r := 0.6
	for i in AutoQuality.RECOVER_S + 1:
		r = c.step_scale(75, 1000.0 * i, r, 1.0, 60)
	check(r > 0.6, "con fps de sobra la escala vuelve a subir lentamente (%.2f)" % r)
	var d := AutoQuality.new()
	var q := 0.9
	for i in 40:
		q = d.step_scale(75, 1000.0 * i, q, 0.9, 60)
	check(q <= 0.9 + 1e-6, "nunca pasa de la escala base")
	check(a.at_floor(AutoQuality.MIN_SCALE) and not a.at_floor(0.8), "at_floor")
